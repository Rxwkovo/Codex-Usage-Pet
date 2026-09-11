"""Desktop-owned companion service; uses the Android mdt1 HTTPS protocol.

No account credentials or remote control endpoints. Control files live in a
current-user-only directory, and all network responses use a quota whitelist.
"""
import argparse
import base64
import ctypes
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import qrcode
from protocol import Bridge, certificate, is_lan_ip, sanitize


def atomic_json(path, data):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, allow_nan=False), encoding='utf-8')
    temp.replace(path)


def read_json(path, default=None):
    try:
        return json.loads(path.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError):
        return default


def secure_directory(path):
    path.mkdir(parents=True, exist_ok=True)
    if os.name == 'nt':
        identity = subprocess.check_output(['whoami'], text=True, creationflags=subprocess.CREATE_NO_WINDOW).strip()
        subprocess.run(['icacls', str(path), '/inheritance:r', '/grant:r', identity+':(OI)(CI)F'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    else:
        path.chmod(0o700)


class ParentWatch:
    def __init__(self, pid):
        self.pid = pid
        self.handle = None
        if os.name == 'nt':
            self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            self.kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
            self.kernel.OpenProcess.restype = ctypes.c_void_p
            self.kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
            self.kernel.CloseHandle.argtypes = [ctypes.c_void_p]
            self.handle = self.kernel.OpenProcess(0x100000, False, pid)
            if not self.handle:
                raise RuntimeError('parent_unavailable')

    def alive(self):
        if os.name == 'nt':
            return self.kernel.WaitForSingleObject(self.handle, 0) == 258
        try:
            os.kill(self.pid, 0)
            return True
        except OSError:
            return False

    def close(self):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


class DesktopBridge(Bridge):
    def __init__(self, state, usage_path, invite_minutes):
        super().__init__(state)
        self.usage_path = usage_path
        self.invite_minutes = invite_minutes
        self.last_seen = {}
        self.renew()

    def renew(self):
        with self.lock:
            self.invite = secrets.token_urlsafe(32)
            self.expires = time.time() + self.invite_minutes * 60
            self.attempts.clear()

    def revoke(self):
        with self.lock:
            # Commit revocation to disk before reporting it as effective.
            atomic_json(self.tokens_file, [])
            self.tokens = []
            self.last_seen.clear()
            self.invite = None
            self.expires = 0

    def pair(self, code, address):
        # Headers are untrusted. Bound their size and the source rate-limit map.
        if len(code) > 128:
            return None
        with self.lock:
            if len(self.attempts) > 256:
                self.attempts = {k: v for k, v in self.attempts.items() if time.time()-v[1] < 60}
                if len(self.attempts) > 256:
                    return None
        try:
            return super().pair(code, address)
        except (TypeError, UnicodeError):
            return None

    def usage(self):
        data = read_json(self.usage_path, {})
        if not isinstance(data, dict):
            data = {}
        return sanitize(data)

    def authenticated_usage(self, token):
        if len(token) > 128:
            return None
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            if not any(hmac.compare_digest(digest, saved) for saved in self.tokens):
                return None
            self.last_seen[digest] = time.time()
            # Revocation cannot race with an authorized snapshot being created.
            return self.usage()

    def snapshot(self):
        now = time.time()
        with self.lock:
            return {
                'paired': len(self.tokens),
                'online': sum(now-self.last_seen.get(t, 0) < 120 for t in self.tokens),
                'lastSeen': int(max(self.last_seen.values(), default=0)),
                'expires': int(self.expires) if self.invite else 0,
                'invite': self.invite if self.invite and self.expires > now else None,
            }


def make_desktop_server(bridge, host, port, cert, key):
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.minimum_version = ssl.TLSVersion.TLSv1_2
    tls.load_cert_chain(cert, key)

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            self.connection = self.request
            self.connection.settimeout(5)
            self.connection.do_handshake()
            super().setup()

        def log_message(self, *args):
            pass

        def reply(self, status, value):
            raw = json.dumps(value, allow_nan=False).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_POST(self):
            if self.path != '/pair':
                self.reply(404, {'error': 'not_found'}); return
            token = bridge.pair(self.headers.get('Authorization', '').removeprefix('Bearer '), self.client_address[0])
            self.reply(200 if token else 403, {'token': token} if token else {'error': 'pairing_rejected'})

        def do_GET(self):
            if self.path != '/usage':
                self.reply(404, {'error': 'not_found'}); return
            data = bridge.authenticated_usage(self.headers.get('Authorization', '').removeprefix('Bearer '))
            self.reply(401 if data is None else 200, {'error': 'unauthorized'} if data is None else data)

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = False

        def __init__(self):
            self.slots = threading.BoundedSemaphore(16)
            super().__init__((host, port), Handler)

        def get_request(self):
            sock, address = self.socket.accept()
            try:
                # Handshake happens in the bounded worker, never the accept loop.
                return tls.wrap_socket(sock, server_side=True, do_handshake_on_connect=False), address
            except Exception:
                sock.close()
                raise

        def process_request(self, request, address):
            if not self.slots.acquire(False):
                request.close(); return
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

    return Server()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--host', required=True)
    p.add_argument('--port', type=int, default=47831)
    p.add_argument('--invite-minutes', type=int, default=10)
    p.add_argument('--state', type=Path, required=True)
    p.add_argument('--control', type=Path, required=True)
    p.add_argument('--usage', type=Path, required=True)
    p.add_argument('--owner', type=int, required=True)
    p.add_argument('--session', required=True)
    p.add_argument('--test-loopback', action='store_true')
    args = p.parse_args()
    if not is_lan_ip(args.host) and not (args.test_loopback and args.host == '127.0.0.1'):
        p.error('Use a connected private LAN IPv4')
    if not 1024 <= args.port <= 65535 or not 1 <= args.invite_minutes <= 60:
        p.error('Invalid port or invitation lifetime')
    secure_directory(args.control)
    status_path = args.control / 'status.json'
    status = {'session': args.session, 'state': 'starting'}
    server = parent = lease = None
    owned = False
    try:
        secure_directory(args.state)
        # Serialize desktop adapters even if they choose different NICs/ports.
        lease = (args.state / 'desktop.lock').open('a+b')
        if os.name == 'nt':
            import msvcrt
            lease.seek(0); lease.write(b'0'); lease.flush(); lease.seek(0)
            try:
                msvcrt.locking(lease.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError:
                raise RuntimeError('already_running')
        parent = ParentWatch(args.owner)
        cert, key, pin = certificate(args.state, args.host)
        bridge = DesktopBridge(args.state, args.usage, args.invite_minutes)
        server = make_desktop_server(bridge, args.host, args.port, cert, key)
        owned = True
        url = f'https://{args.host}:{args.port}'
        threading.Thread(target=server.serve_forever, daemon=True).start()
        qr_invite = None
        while parent.alive():
            stop = False
            for path in sorted(args.control.glob('command-*.json')):
                command = read_json(path, {})
                path.unlink(missing_ok=True)
                if not isinstance(command, dict) or command.get('session') != args.session:
                    continue
                action = command.get('action')
                if action == 'stop':
                    stop = True
                elif action == 'renew':
                    bridge.renew()
                elif action == 'revoke':
                    bridge.revoke()
            if stop:
                break
            state = bridge.snapshot()
            invite = state.pop('invite')
            if invite != qr_invite:
                qr_invite = invite
                if invite:
                    spec = {'url': url, 'pin': pin, 'code': invite}
                    code = 'mdt1:' + base64.urlsafe_b64encode(json.dumps(spec, separators=(',', ':')).encode()).decode()
                    image = qrcode.make(code)
                    image.save(args.control / 'pairing.tmp', format='PNG')
                    (args.control / 'pairing.tmp').replace(args.control / 'pairing.png')
                    (args.control / 'pairing.txt').write_text(code, encoding='utf-8')
                else:
                    for name in ('pairing.txt', 'pairing.png'):
                        (args.control / name).unlink(missing_ok=True)
            status = dict(state, session=args.session, state='running', url=url,
                          updatedAt=int(time.time()), usage=bridge.usage(), qr=bool(invite))
            atomic_json(status_path, status)
            time.sleep(0.4)
        status['state'] = 'stopped'
        status['qr'] = False
    except Exception as error:
        reason = str(error)
        if isinstance(error, OSError) and (error.errno in (98, 10048) or getattr(error, 'winerror', 0) == 10048):
            reason = 'address_in_use'
        elif isinstance(error, OSError) and (error.errno in (99, 10049) or getattr(error, 'winerror', 0) == 10049):
            reason = 'address_unavailable'
        elif reason not in ('already_running', 'parent_unavailable'):
            reason = 'startup_failed'
        status = {'session': args.session, 'state': 'error', 'error': reason, 'qr': False}
    finally:
        if server:
            server.shutdown(); server.server_close()
        if owned:
            for name in ('pairing.txt', 'pairing.png'):
                (args.control / name).unlink(missing_ok=True)
        if parent:
            parent.close()
        if lease:
            lease.close()
        atomic_json(status_path, status)
    return 1 if status['state'] == 'error' else 0


if __name__ == '__main__':
    raise SystemExit(main())
