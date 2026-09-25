"""Desktop-owned companion service; uses the Android mdt1 HTTPS protocol.

No account credentials or remote control endpoints. Control files live in a
current-user-only directory, and all network responses use a quota whitelist.
"""
import argparse
import base64
import ctypes
import ipaddress
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import threading
import time

import qrcode
from protocol import Bridge, certificate, is_lan_ip, normalize_policy, sanitize
from sync_server import ConnectionDeadline, make_bounded_server


# Preserve the entry-specific public name used by the launcher and older tests.
make_desktop_server = make_bounded_server


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
    def __init__(self, state, usage_path, invite_minutes, policy=None):
        super().__init__(state, policy=policy)
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
        return sanitize(data, policy=self.policy)

    def _record_authorized(self, digest):
        self.last_seen[digest] = time.time()

    def snapshot(self):
        now = time.time()
        tokens = self.token_hashes()
        with self.lock:
            # Forget devices that are no longer paired. Their entries kept this map
            # growing, and 'lastSeen' could report a phone the user had replaced while
            # 'online' only counted the current tokens, so the two disagreed.
            live = set(tokens)
            self.last_seen = {k: v for k, v in self.last_seen.items() if k in live}
            return {
                'paired': len(tokens),
                'online': sum(now-self.last_seen.get(t, 0) < 120 for t in tokens),
                'lastSeen': int(max(self.last_seen.values(), default=0)),
                'expires': int(self.expires) if self.invite else 0,
                'invite': self.invite if self.invite and self.expires > now else None,
            }


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
    p.add_argument('--refresh-seconds', type=float, default=60)
    p.add_argument('--stale-seconds', type=float, default=120)
    p.add_argument('--happy-threshold', type=float, default=50)
    p.add_argument('--worried-threshold', type=float, default=20)
    args = p.parse_args()
    try:
        policy = normalize_policy({
            'refreshSeconds': args.refresh_seconds,
            'staleSeconds': args.stale_seconds,
            'clockSkewToleranceSeconds': 5,
            'happyMinRemaining': args.happy_threshold,
            'worriedMaxRemaining': args.worried_threshold,
            'exhaustedMaxRemaining': 0,
        })
    except ValueError as error:
        p.error(str(error))
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
        bridge = DesktopBridge(args.state, args.usage, args.invite_minutes, policy=policy)
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
