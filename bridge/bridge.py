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
import math
import os
from pathlib import Path
import secrets
import tempfile
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


def lan_candidates():
    """Only connected physical adapters; never suggest stale Wi-Fi or VPN IPs."""
    if os.name != "nt":
        return []
    script = """$ErrorActionPreference='Stop'; @(
Get-NetAdapter -Physical | Where-Object Status -eq Up | ForEach-Object {
 $adapter=$_
 Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 | Where-Object AddressState -eq Preferred | ForEach-Object {
  [pscustomobject]@{ip=$_.IPAddress; wifi=($adapter.NdisPhysicalMedium -eq 9 -or $adapter.PhysicalMediaType -match '802.11')}
 }
}) | ConvertTo-Json -Compress"""
    try:
        raw = subprocess.check_output(["powershell.exe", "-NoProfile", "-Command", script],
            text=True, timeout=15, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        items = json.loads(raw or "[]")
        if isinstance(items, dict): items = [items]
        return sorted([item for item in items if is_lan_ip(item["ip"])], key=lambda item: not item["wifi"])
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


def is_lan_ip(host):
    try:
        ip = ipaddress.ip_address(host)
        return ip.version == 4 and any(ip in ipaddress.ip_network(net) for net in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))
    except ValueError:
        return False


def choose_host():
    candidates = lan_candidates()
    print("手机与电脑请连接同一个 Wi-Fi。电脑网线可以保留。")
    if candidates:
        for index, item in enumerate(candidates, 1):
            print(f"  {index}. {item['ip']}" + ("  (Wi-Fi)" if item["wifi"] else ""))
        value = input("选择手机能访问的地址编号，直接回车选择 1：").strip() or "1"
        if value.isdecimal() and 1 <= int(value) <= len(candidates):
            return candidates[int(value)-1]["ip"]
        return value
    return input("未找到已连接的局域网网卡，请连接 Wi-Fi 后输入电脑 IPv4：").strip()


def sanitize(data):
    """Whitelist only the documented quota fields; reject non-finite percentages."""
    now = time.time()
    result = {"status": "stale", "updatedAt": 0, "serverTime": int(now), "fiveHour": None, "weekly": None}
    # usage.json is a file on disk, so anything at all can be in it. Without this
    # guard a top-level array/string/null made data.get raise AttributeError, which
    # usage() only catches as (OSError, ValueError): the request thread died and the
    # phone saw a reset connection instead of JSON. desktop.py already guarded this.
    if not isinstance(data, dict):
        return result
    try:
        stamp = int(data.get("updatedAt", 0))
        result["updatedAt"] = stamp
        for field in ("fiveHour", "weekly"):
            window = data.get(field)
            if not isinstance(window, dict):
                continue
            raw = window["remaining"]
            # bool is a subclass of int, so float(True) used to clear the range check
            # and get published to the phone as "1% remaining".
            if isinstance(raw, bool) or not isinstance(raw, (int, float)):
                continue
            value = float(raw)
            if not math.isfinite(value) or not 0 <= value <= 100:
                continue
            result[field] = {"remaining": value, "resetsAt": int(window.get("resetsAt") or 0)}
        if data.get("status") == "ok" and -5 <= now - stamp < 120 and all(
            result[k] is not None and result[k]["resetsAt"] > now for k in ("fiveHour", "weekly")
        ):
            result["status"] = "ok"
    except (ValueError, TypeError, KeyError, OverflowError):
        pass
    return result


def _load_certificate_pair(cert_path, key_path):
    """Return the stored certificate, or None when it is missing or mismatched."""
    try:
        cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
        key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
        if cert.public_key().public_numbers() != key.public_key().public_numbers():
            return None
        return cert
    except Exception:
        # Anything unreadable counts as "no usable certificate"; the caller replaces it.
        return None


def _replace(path, data):
    """Write bytes through a unique temporary name so two processes cannot interleave."""
    handle, temp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + '.', suffix='.tmp')
    try:
        with os.fdopen(handle, 'wb') as stream:
            stream.write(data)
        os.replace(temp, path)
    except Exception:
        try:
            os.unlink(temp)
        except OSError:
            pass
        raise


def certificate(state, host):
    # The standalone bridge and the v2.2.1 desktop service share this state directory
    # by default and neither locked it here, so their first runs could interleave and
    # leave a key that does not match the certificate. load_cert_chain then failed on
    # every later start until both files were deleted by hand; a mismatched pair is
    # now treated as missing and regenerated.
    cert_path, key_path = state / "server.pem", state / "key.pem"
    cert = _load_certificate_pair(cert_path, key_path)
    if cert is None:
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "MaTuan local bridge")])
        cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                .public_key(key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(datetime.now(timezone.utc) - timedelta(minutes=5))
                .not_valid_after(datetime.now(timezone.utc) + timedelta(days=365))
                .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address(host))]), False)
                .sign(key, hashes.SHA256()))
        _replace(key_path, key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        _replace(cert_path, cert.public_bytes(serialization.Encoding.PEM))
        cert = _load_certificate_pair(cert_path, key_path)
        if cert is None:
            raise RuntimeError("Could not store a usable certificate under " + str(state))
    return cert_path, key_path, cert.fingerprint(hashes.SHA256()).hex()


class SourceRateLimit:
    """Bound how often one LAN address may call the API.

    The device token is 32 random bytes so guessing is hopeless, but nothing stopped a
    paired device - or anyone holding a copied token - from hammering the endpoints, and
    every request costs a TLS handshake and a worker slot. The map is bounded so a scanner
    cannot grow it without limit. Mirrors mobile-sync/protocol.py.
    """

    def __init__(self, limit, window=60.0, max_sources=256):
        self.limit = limit
        self.window = window
        self.max_sources = max_sources
        self.lock = threading.Lock()
        self.hits = {}

    def allow(self, address):
        now = time.monotonic()
        with self.lock:
            count, started = self.hits.get(address, (0, now))
            if now - started >= self.window:
                count, started = 0, now
            if count >= self.limit:
                self.hits[address] = (count, started)
                return False
            self.hits[address] = (count + 1, started)
            if len(self.hits) > self.max_sources:
                self.hits = {k: v for k, v in self.hits.items() if now - v[1] < self.window}
                if len(self.hits) > self.max_sources:
                    return False
            return True


class Bridge:
    def __init__(self, state):
        self.state = state
        self.invite = secrets.token_urlsafe(32)
        self.expires = time.time() + 600
        self.lock = threading.Lock()
        self.tokens_file = state / "devices.json"
        self.tokens = self._read_tokens()
        self.attempts = {}

    def _read_tokens(self):
        try:
            stored = json.loads(self.tokens_file.read_text())
            return stored if isinstance(stored, list) else []
        except (OSError, ValueError):
            return []

    def pair(self, code, address):
        # Headers are untrusted: bound their size, reject non-ASCII (http.client decodes
        # headers as latin-1 and hmac.compare_digest raises TypeError on non-ASCII, which
        # used to kill the request thread with no reply), and bound the rate-limit map.
        if not isinstance(code, str) or not code.isascii() or len(code) > 128:
            return None
        with self.lock:
            if len(self.attempts) > 256:
                self.attempts = {k: v for k, v in self.attempts.items() if time.time() - v[1] < 60}
                if len(self.attempts) > 256:
                    return None
            count, started = self.attempts.get(address, (0, time.time()))
            if time.time() - started > 60:
                count, started = 0, time.time()
            self.attempts[address] = (count + 1, started)
            if count >= 10 or not self.invite or time.time() > self.expires or not hmac.compare_digest(code, self.invite):
                return None
            token = secrets.token_urlsafe(32)
            # Re-read from disk first: the desktop service can share this directory, and
            # an in-memory list from start-up would silently drop a device it paired.
            self.tokens = self._read_tokens()
            self.tokens.append(hashlib.sha256(token.encode()).hexdigest())
            self.tokens = self.tokens[-10:]
            _replace(self.tokens_file, json.dumps(self.tokens).encode())
            self.invite = None
            return token

    def authorized(self, token):
        if not isinstance(token, str):
            return False
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            return any(hmac.compare_digest(digest, saved) for saved in self.tokens)

    def usage(self):
        try:
            return sanitize(json.loads((self.state / "usage.json").read_text(encoding="utf-8-sig")))
        except (OSError, ValueError, AttributeError):
            return sanitize({})


def _shutdown_socket(sock):
    """Close a socket from the reaper; this unblocks the worker that holds it."""
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    try:
        sock.close()
    except OSError:
        pass


class ConnectionDeadline:
    """Give every accepted connection an absolute lifetime.

    settimeout() bounds one send/recv, not the connection, so a client that dribbles a
    byte at a time can hold a worker slot forever. With all 16 slots held this server
    closed every new connection before the TLS handshake and the phone only saw a
    network error. The reaper closes anything past `limit`, freeing the slot.
    Mirrors mobile-sync/desktop.py; keep the two in sync.
    """

    def __init__(self, limit):
        self.limit = limit
        self.lock = threading.Lock()
        self.live = {}
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._reap, daemon=True)

    def start(self):
        self.thread.start()

    def add(self, sock):
        with self.lock:
            self.live[sock] = time.monotonic()

    def discard(self, sock):
        with self.lock:
            self.live.pop(sock, None)

    def close(self):
        self.stop.set()
        with self.lock:
            socks = list(self.live)
            self.live.clear()
        for sock in socks:
            _shutdown_socket(sock)

    def _reap(self):
        while not self.stop.wait(1.0):
            now = time.monotonic()
            with self.lock:
                expired = [sock for sock, accepted in self.live.items() if now - accepted > self.limit]
                for sock in expired:
                    self.live.pop(sock, None)
            for sock in expired:
                _shutdown_socket(sock)


def make_server(bridge, host, port, cert, key, deadline_seconds=15):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            # Handshake in the worker thread, never in accept(); see Server.get_request.
            self.connection = self.request
            self.connection.settimeout(10)
            self.connection.do_handshake()
            super().setup()

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

        def guard(self):
            """Shared gate for every route: source rate limit, then the path check."""
            if not self.server.limiter.allow(self.client_address[0]):
                self.reply(429, {"error": "too_many_requests"}); return False
            return True

        def do_POST(self):
            if not self.guard():
                return
            if self.path != "/pair":
                self.reply(404, {"error": "not_found"}); return
            token = bridge.pair(self.headers.get("Authorization", "").removeprefix("Bearer "), self.client_address[0])
            self.reply(200 if token else 403, {"token": token} if token else {"error": "pairing_rejected"})

        def do_GET(self):
            if not self.guard():
                return
            if self.path != "/usage":
                self.reply(404, {"error": "not_found"}); return
            if not bridge.authorized(self.headers.get("Authorization", "").removeprefix("Bearer ")):
                self.reply(401, {"error": "unauthorized"}); return
            self.reply(200, bridge.usage())

    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.minimum_version = ssl.TLSVersion.TLSv1_2
    tls.load_cert_chain(cert, key)

    class Server(ThreadingHTTPServer):
        # The listener is *not* wrapped: wrapping it makes accept() perform the
        # handshake on the accept loop, so one client that connects and never
        # finishes the handshake wedges every other client. Accept in the clear,
        # then hand the socket to a bounded worker which does the handshake under
        # a timeout. This mirrors mobile-sync/desktop.py make_desktop_server;
        # keep the two in sync if either is touched.
        daemon_threads = True
        allow_reuse_address = False  # On Windows SO_REUSEADDR lets another process steal the port.

        def __init__(self):
            self.slots = threading.BoundedSemaphore(16)
            self.deadline = ConnectionDeadline(deadline_seconds)
            self.limiter = SourceRateLimit(60)
            super().__init__((host, port), Handler)
            self.deadline.start()

        def verify_request(self, request, client_address):
            # Enforce the "LAN only" promise in code instead of relying on the firewall
            # rule alone: a source routable from outside must never reach a handler.
            return is_lan_ip(client_address[0]) or client_address[0] == "127.0.0.1"

        def get_request(self):
            sock, address = self.socket.accept()
            try:
                wrapped = tls.wrap_socket(sock, server_side=True, do_handshake_on_connect=False)
            except Exception:
                sock.close()
                raise
            self.deadline.add(wrapped)
            return wrapped, address

        def shutdown_request(self, request):
            self.deadline.discard(request)
            super().shutdown_request(request)

        def process_request(self, request, address):
            if not self.slots.acquire(False):
                # Nothing can be reported in HTTP before the handshake, so just drop it.
                # The absolute deadline above is what stops this from lasting forever.
                self.deadline.discard(request)
                request.close()
                return
            try:
                super().process_request(request, address)
            except Exception:
                self.slots.release()
                raise

        def process_request_thread(self, request, address):
            try:
                super().process_request_thread(request, address)
            finally:
                self.slots.release()

        def handle_error(self, request, address):
            pass

        def server_close(self):
            # Close tracked sockets first so workers blocked in a read can finish.
            self.deadline.close()
            super().server_close()

    return Server()


def refresh_loop(state, stop):
    while not stop.is_set():
        try:
            subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(state / "read-usage.ps1")],
                           timeout=50, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), check=True)
        except (OSError, subprocess.SubprocessError):
            try:
                path = state / "usage.json"
                data = json.loads(path.read_text(encoding="utf-8-sig"))
                if isinstance(data, dict):
                    data["status"] = "stale"
                    _replace(path, json.dumps(data).encode())
            except (OSError, ValueError, TypeError):
                # A TypeError here (usage.json holding a list, say) used to escape this
                # guard and end the refresh thread for good, after which the bridge kept
                # serving frozen data forever.
                pass
        stop.wait(60)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", help="This computer's private LAN IPv4 address")
    parser.add_argument("--port", type=int, default=47831)
    parser.add_argument("--reset", action="store_true", help="Revoke all paired phones")
    parser.add_argument("--state-dir", type=Path, help="Optional isolated bridge data directory")
    parser.add_argument("--no-refresh", action="store_true", help="Serve existing cache without querying Codex")
    parser.add_argument("--open-qr", action="store_true", help="Open the private pairing QR image")
    args = parser.parse_args()
    if not args.host:
        args.host = choose_host()
    address = ipaddress.ip_address(args.host)
    if address.version != 4 or not (is_lan_ip(args.host) or address.is_loopback):
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
    try:
        server = make_server(bridge, args.host, args.port, cert, key)
    except OSError as error:
        parser.exit(1, f"无法监听 {args.host}:{args.port}，请检查网卡已连接，以及同步端是否已启动。\n{error}\n")
    spec = {"url": f"https://{args.host}:{args.port}", "pin": pin, "code": bridge.invite}
    code = "mdt1:" + base64.urlsafe_b64encode(json.dumps(spec, separators=(",", ":")).encode()).decode()
    (state / "pairing.txt").write_text(code, encoding="utf-8")
    import qrcode
    qrcode.make(code).save(state / "pairing.png")
    if args.open_qr and os.name == "nt":
        os.startfile(state / "pairing.png")
    print(f"码团同步端已启动：{spec['url']}\n配对码有效期 10 分钟，仅限一台新设备使用。")
    print(f"在手机粘贴配对码，或导入二维码图片：\n{state / 'pairing.png'}\n")
    print(code)
    print("\n仅需允许专用网络访问此端口。Ctrl+C 停止同步；--reset 可撤销全部配对。")
    if address.is_loopback:
        print("注意：这是 USB 调试地址，拔线即断开。无线同步必须使用电脑的局域网地址。")
    else:
        print(f"手机无线地址：{args.host}:{args.port}。已配对同一同步端的手机可用“切换无线地址”，无需重新配对。")
        print("若手机连不上，请运行随附的 allow-wireless.ps1，仅放行本机此端口的局域网访问。")
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
