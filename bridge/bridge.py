"""Local TLS quota bridge. Codex credentials never leave the desktop.

Run from the source checkout; pairing code is a short-lived, one-use invitation.
Only generated state (never source) contains certificates and device tokens.
"""
import argparse
import base64
import ipaddress
import json
import os
from pathlib import Path
import shutil
import sys
import subprocess
import threading
import time

_ROOT = Path(__file__).resolve().parents[1]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from sync_core import (  # noqa: E402
    POLICY,
    PROTOCOL_VERSION,
    Bridge,
    SourceConcurrencyLimit,
    SourceRateLimit,
    _replace,
    certificate,
    is_lan_ip,
    sanitize,
)
from sync_server import ConnectionDeadline, make_bounded_server  # noqa: E402


# Preserve the standalone entry's existing public factory name.
make_server = make_bounded_server


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


class RefreshWorker:
    """Run quota refreshes without leaving PowerShell or its Codex child behind."""

    def __init__(self, state, command=None, interval=60, timeout=50):
        self.state = state
        self.command = command or [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(state / "read-usage.ps1"),
        ]
        self.interval = interval
        self.timeout = timeout
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.process = None
        self.thread = threading.Thread(target=self._run, name="sync-quota-refresh", daemon=True)

    def start(self):
        self.thread.start()

    def _mark_stale(self):
        try:
            path = self.state / "usage.json"
            data = json.loads(path.read_text(encoding="utf-8-sig"))
            if isinstance(data, dict):
                data["status"] = "stale"
                _replace(path, json.dumps(data).encode())
        except (OSError, ValueError, TypeError):
            pass

    @staticmethod
    def _terminate(process):
        if process.poll() is not None:
            return
        if os.name == "nt":
            try:
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                               timeout=5, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, check=False,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            except (OSError, subprocess.SubprocessError):
                process.kill()
        else:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)

    def _run(self):
        while not self.stop.is_set():
            failed = False
            process = None
            try:
                process = subprocess.Popen(
                    self.command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
                with self.lock:
                    self.process = process
                try:
                    if process.wait(timeout=self.timeout) != 0:
                        failed = True
                except subprocess.TimeoutExpired:
                    failed = True
                    self._terminate(process)
            except OSError:
                failed = True
            finally:
                with self.lock:
                    if self.process is process:
                        self.process = None
            if failed and not self.stop.is_set():
                self._mark_stale()
            self.stop.wait(self.interval)

    def close(self):
        self.stop.set()
        deadline = time.monotonic() + 7
        while self.thread.is_alive() and time.monotonic() < deadline:
            with self.lock:
                process = self.process
            if process is not None:
                self._terminate(process)
            self.thread.join(timeout=0.05)


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
    root = Path(sys._MEIPASS) if getattr(sys, "frozen", False) else Path(__file__).resolve().parents[1]
    for filename in ("read-usage.ps1", "usage-core.ps1"):
        shutil.copy2(root / filename, state / filename)
    cert, key, pin = certificate(state, args.host)
    bridge = Bridge(state)
    if args.reset:
        bridge.revoke()
        bridge.renew_invite()
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
    worker = RefreshWorker(state)
    if not args.no_refresh:
        worker.start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        worker.close()
        server.server_close()
        (state / "pairing.txt").unlink(missing_ok=True)
        (state / "pairing.png").unlink(missing_ok=True)


if __name__ == "__main__":
    main()
