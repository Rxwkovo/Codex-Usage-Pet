"""Desktop-owned companion service; uses the Android mdt1 HTTPS protocol.

No account credentials or remote control endpoints. Control files live in a
current-user-only directory, and all network responses use a quota whitelist.
"""
import argparse
import base64
import ctypes
import hashlib
import hmac
import http.client
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import qrcode
from protocol import Bridge, SourceConcurrencyLimit, SourceRateLimit, certificate, is_lan_ip, sanitize

# BaseHTTPRequestHandler otherwise accepts roughly 6 MiB of headers per connection.
# Keep the tiny local API bounded before any route or authentication code runs.
http.client._MAXLINE = 8192
http.client._MAXHEADERS = 32


def atomic_json(path, data):
    """Publish JSON through a unique temporary name, retrying Windows share collisions.

    os.replace needs DELETE access to the target, and the PowerShell settings UI reads
    status.json every second with a share mode that refuses it. One collision used to
    raise straight out of the main loop and shut the whole service down for good, so
    brief retries matter. The temporary name is unique because the standalone bridge
    can be writing the same state directory.
    """
    handle, temp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + '.', suffix='.tmp')
    try:
        with os.fdopen(handle, 'w', encoding='utf-8') as stream:
            stream.write(json.dumps(data, ensure_ascii=False, allow_nan=False))
        for attempt in range(5):
            try:
                os.replace(temp, path)
                return
            except OSError:
                if attempt == 4:
                    raise
                time.sleep(0.02)
    except Exception:
        try:
            os.unlink(temp)
        except OSError:
            pass
        raise


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
        super().revoke()
        with self.lock:
            self.last_seen.clear()

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
            # Forget devices that are no longer paired. Their entries kept this map
            # growing, and 'lastSeen' could report a phone the user had replaced while
            # 'online' only counted the current tokens, so the two disagreed.
            live = set(self.tokens)
            self.last_seen = {k: v for k, v in self.last_seen.items() if k in live}
            return {
                'paired': len(self.tokens),
                'online': sum(now-self.last_seen.get(t, 0) < 120 for t in self.tokens),
                'lastSeen': int(max(self.last_seen.values(), default=0)),
                'expires': int(self.expires) if self.invite else 0,
                'invite': self.invite if self.invite and self.expires > now else None,
            }


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

    socket.settimeout() bounds one send/recv, not the connection. A client that dribbles
    a byte at a time resets it on every read, so it can hold a worker slot forever - and
    with all 16 slots held the server closed every new connection before the TLS
    handshake, so the phone only ever saw a network error. The reaper closes anything
    that outlives `limit`, which makes the blocked read fail and frees the slot.
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


def make_desktop_server(bridge, host, port, cert, key, deadline_seconds=15):
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

        def guard(self):
            """Shared gate for every route: source rate limit, then the path check."""
            if not self.server.limiter.allow(self.client_address[0]):
                self.reply(429, {'error': 'too_many_requests'}); return False
            return True

        def do_POST(self):
            if not self.guard():
                return
            if self.path != '/pair':
                self.reply(404, {'error': 'not_found'}); return
            token = bridge.pair(self.headers.get('Authorization', '').removeprefix('Bearer '), self.client_address[0])
            self.reply(200 if token else 403, {'token': token} if token else {'error': 'pairing_rejected'})

        def do_GET(self):
            if not self.guard():
                return
            if self.path != '/usage':
                self.reply(404, {'error': 'not_found'}); return
            data = bridge.authenticated_usage(self.headers.get('Authorization', '').removeprefix('Bearer '))
            self.reply(401 if data is None else 200, {'error': 'unauthorized'} if data is None else data)

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = False

        def __init__(self):
            self.slots = threading.BoundedSemaphore(16)
            self.deadline = ConnectionDeadline(deadline_seconds)
            self.limiter = SourceRateLimit(60)
            self.peers = SourceConcurrencyLimit(4)
            super().__init__((host, port), Handler)
            self.deadline.start()

        def verify_request(self, request, client_address):
            # Enforce the "LAN only" promise in code instead of relying on the firewall
            # rule alone: a source routable from outside must never reach a handler.
            address = client_address[0]
            if not (is_lan_ip(address) or address == '127.0.0.1'):
                return False
            return self.peers.acquire(request, address)

        def get_request(self):
            sock, address = self.socket.accept()
            try:
                # Handshake happens in the bounded worker, never the accept loop.
                wrapped = tls.wrap_socket(sock, server_side=True, do_handshake_on_connect=False)
            except Exception:
                sock.close()
                raise
            self.deadline.add(wrapped)
            return wrapped, address

        def shutdown_request(self, request):
            self.deadline.discard(request)
            self.peers.release(request)
            super().shutdown_request(request)

        def process_request(self, request, address):
            if not self.slots.acquire(False):
                # Nothing can be reported in HTTP before the handshake, so just drop it.
                # The absolute deadline above is what stops this from lasting forever.
                self.deadline.discard(request)
                self.peers.release(request)
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
            # Append mode ignores seek() for writes, so writing unconditionally made
            # desktop.lock grow by one byte on every start. Only seed it when empty.
            lease.seek(0, os.SEEK_END)
            if lease.tell() == 0:
                lease.write(b'0'); lease.flush()
            lease.seek(0)
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
                    # Publish the code atomically and before the image. The UI copies
                    # pairing.txt verbatim, so a truncating write could put a half-written
                    # code on the clipboard; image-first also showed a new QR beside the
                    # previous (now invalid) code.
                    image.save(args.control / 'pairing.tmp', format='PNG')
                    text_temp = args.control / 'pairing.txt.tmp'
                    text_temp.write_text(code, encoding='utf-8')
                    text_temp.replace(args.control / 'pairing.txt')
                    (args.control / 'pairing.tmp').replace(args.control / 'pairing.png')
                else:
                    for name in ('pairing.txt', 'pairing.png'):
                        (args.control / name).unlink(missing_ok=True)
            status = dict(state, session=args.session, state='running', url=url,
                          updatedAt=int(time.time()), usage=bridge.usage(), qr=bool(invite))
            try:
                atomic_json(status_path, status)
            except OSError:
                # A transient sharing violation while the settings UI reads status.json
                # used to unwind into the handler below and shut the whole service down
                # as 'startup_failed'. Missing one status tick is harmless.
                pass
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
        # Nothing in here may raise: it runs on the way out of a clean stop too, and an
        # exception would replace the exit code 0 with a traceback, which the UI reports
        # as "the sync service stopped unexpectedly" when the user simply closed it.
        try:
            if server:
                server.shutdown(); server.server_close()
            if owned:
                for name in ('pairing.txt', 'pairing.png'):
                    try:
                        (args.control / name).unlink(missing_ok=True)
                    except OSError:
                        pass
            if parent:
                parent.close()
            if lease:
                lease.close()
            atomic_json(status_path, status)
        except Exception:
            pass
    return 1 if status.get('state') == 'error' else 0


if __name__ == '__main__':
    raise SystemExit(main())
