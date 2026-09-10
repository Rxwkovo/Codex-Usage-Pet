"""Local TLS quota bridge. Codex credentials never leave the desktop.

Run from the source checkout; pairing code is a short-lived, one-use invitation.
Only generated state (never source) contains certificates and device tokens.
"""
import argparse
import base64
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import ssl
import sys
import subprocess
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def sanitize(data):
    """Whitelist only the documented quota fields; reject non-finite percentages."""
    result = {"status": "stale", "updatedAt": 0, "fiveHour": None, "weekly": None}
    try:
        stamp = int(data.get("updatedAt", 0))
        result["updatedAt"] = stamp
        for field in ("fiveHour", "weekly"):
            window = data.get(field)
            if not isinstance(window, dict):
                continue
            value = float(window["remaining"])
            if not 0 <= value <= 100:
                continue
            result[field] = {"remaining": value, "resetsAt": int(window.get("resetsAt") or 0)}
        now = time.time()
        if data.get("status") == "ok" and -5 <= now - stamp < 120 and all(
            result[k] is not None and result[k]["resetsAt"] > now for k in ("fiveHour", "weekly")
        ):
            result["status"] = "ok"
    except (ValueError, TypeError, KeyError, OverflowError):
        pass
    return result


def certificate(state, host):
    cert_path, key_path = state / "server.pem", state / "key.pem"
    if not cert_path.exists() or not key_path.exists():
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "MaTuan local bridge")])
        cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                .public_key(key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(datetime.now(timezone.utc) - timedelta(minutes=5))
                .not_valid_after(datetime.now(timezone.utc) + timedelta(days=365))
                .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address(host))]), False)
                .sign(key, hashes.SHA256()))
        key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
    return cert_path, key_path, cert.fingerprint(hashes.SHA256()).hex()


class Bridge:
    def __init__(self, state):
        self.state = state
        self.invite = secrets.token_urlsafe(32)
        self.expires = time.time() + 600
        self.lock = threading.Lock()
        self.tokens_file = state / "devices.json"
        self.tokens = json.loads(self.tokens_file.read_text()) if self.tokens_file.exists() else []
        self.attempts = {}

    def pair(self, code, address):
        with self.lock:
            count, started = self.attempts.get(address, (0, time.time()))
            if time.time() - started > 60:
                count, started = 0, time.time()
            self.attempts[address] = (count + 1, started)
            if count >= 10 or not self.invite or time.time() > self.expires or not hmac.compare_digest(code, self.invite):
                return None
            token = secrets.token_urlsafe(32)
            self.tokens.append(hashlib.sha256(token.encode()).hexdigest())
            self.tokens = self.tokens[-10:]
            temp = self.tokens_file.with_suffix(".tmp")
            temp.write_text(json.dumps(self.tokens))
            temp.replace(self.tokens_file)
            self.invite = None
            return token

    def authorized(self, token):
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            return any(hmac.compare_digest(digest, saved) for saved in self.tokens)

    def usage(self):
        try:
            return sanitize(json.loads((self.state / "usage.json").read_text(encoding="utf-8-sig")))
        except (OSError, ValueError):
            return sanitize({})


def make_server(bridge, host, port, cert, key):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, *args):
            pass  # Never log headers, tokens, invitations, or quota values.

        def reply(self, status, data):
            raw = json.dumps(data, allow_nan=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_POST(self):
            if self.path != "/pair":
                self.reply(404, {"error": "not_found"}); return
            token = bridge.pair(self.headers.get("Authorization", "").removeprefix("Bearer "), self.client_address[0])
            self.reply(200 if token else 403, {"token": token} if token else {"error": "pairing_rejected"})

        def do_GET(self):
            if self.path != "/usage":
                self.reply(404, {"error": "not_found"}); return
            if not bridge.authorized(self.headers.get("Authorization", "").removeprefix("Bearer ")):
                self.reply(401, {"error": "unauthorized"}); return
            self.reply(200, bridge.usage())

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.minimum_version = ssl.TLSVersion.TLSv1_2
    tls.load_cert_chain(cert, key)
    server.socket = tls.wrap_socket(server.socket, server_side=True)
    return server


def refresh_loop(state, stop):
    while not stop.is_set():
        try:
            subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(state / "read-usage.ps1")],
                           timeout=50, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), check=True)
        except (OSError, subprocess.SubprocessError):
            try:
                data = json.loads((state / "usage.json").read_text(encoding="utf-8-sig"))
                data["status"] = "stale"
                (state / "usage.json").write_text(json.dumps(data))
            except (OSError, ValueError):
                pass
        stop.wait(60)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", help="This computer's private LAN IPv4 address")
    parser.add_argument("--port", type=int, default=47831)
    parser.add_argument("--reset", action="store_true", help="Revoke all paired phones")
    parser.add_argument("--state-dir", type=Path, help="Optional isolated bridge data directory")
    parser.add_argument("--no-refresh", action="store_true", help="Serve existing cache without querying Codex")
    args = parser.parse_args()
    if not args.host:
        print("请输入电脑的局域网 IPv4 地址（Windows 设置 → 网络属性中查看）。")
        args.host = input("电脑 IP：").strip()
    address = ipaddress.ip_address(args.host)
    if address.version != 4 or not (address.is_private or address.is_loopback) or address.is_unspecified:
        parser.error("Use a specific private IPv4 address")
    state = args.state_dir or Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "CodexUsagePet" / "android-bridge"
    state.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        identity = subprocess.check_output(["whoami"], text=True).strip()
        subprocess.run(["icacls", str(state), "/inheritance:r", "/grant:r", f"{identity}:(OI)(CI)F"], check=True, stdout=subprocess.DEVNULL)
    if args.reset:
        (state / "devices.json").unlink(missing_ok=True)
    root = Path(sys._MEIPASS) if getattr(sys, "frozen", False) else Path(__file__).resolve().parents[1]
    for filename in ("read-usage.ps1", "usage-core.ps1"):
        shutil.copy2(root / filename, state / filename)
    cert, key, pin = certificate(state, args.host)
    bridge = Bridge(state)
    server = make_server(bridge, args.host, args.port, cert, key)
    spec = {"url": f"https://{args.host}:{args.port}", "pin": pin, "code": bridge.invite}
    code = "mdt1:" + base64.urlsafe_b64encode(json.dumps(spec, separators=(",", ":")).encode()).decode()
    (state / "pairing.txt").write_text(code, encoding="utf-8")
    import qrcode
    qrcode.make(code).save(state / "pairing.png")
    print(f"码团同步端已启动：{spec['url']}\n配对码有效期 10 分钟，仅限一台新设备使用。")
    print(f"在手机粘贴配对码，或导入二维码图片：\n{state / 'pairing.png'}\n")
    print(code)
    print("\n仅需允许专用网络访问此端口。Ctrl+C 停止同步；--reset 可撤销全部配对。")
    stop = threading.Event()
    worker = threading.Thread(target=refresh_loop, args=(state, stop), daemon=True)
    if not args.no_refresh:
        worker.start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set(); server.server_close()
        (state / "pairing.txt").unlink(missing_ok=True)
        (state / "pairing.png").unlink(missing_ok=True)


if __name__ == "__main__":
    main()
