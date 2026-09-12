import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request

from desktop import ConnectionDeadline, DesktopBridge, atomic_json, make_desktop_server, read_json
from protocol import certificate


def quota():
    now = int(time.time())
    return dict(status='ok', updatedAt=now, fiveHour=dict(remaining=76, resetsAt=now+3600),
                weekly=dict(remaining=24, resetsAt=now+86400), privateField='NEVER EXPOSE')


def client(cert, port):
    context = ssl.create_default_context(cafile=str(cert))
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context))
    def request(path, token, method='GET'):
        r = urllib.request.Request(f'https://127.0.0.1:{port}'+path,
                                   headers={'Authorization': 'Bearer '+token}, method=method)
        return json.loads(opener.open(r, timeout=4).read())
    return request


class DesktopProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root/'desktop-usage.json'
        atomic_json(self.source, quota())
        self.bridge = DesktopBridge(self.root, self.source, 3)
        self.cert, key, self.pin = certificate(self.root, '127.0.0.1')
        self.server = make_desktop_server(self.bridge, '127.0.0.1', 0, self.cert, key)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.request = client(self.cert, self.server.server_port)

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
        self.temp.cleanup()

    def pair(self):
        return self.request('/pair', self.bridge.invite, 'POST')['token']

    def test_current_desktop_snapshot_and_whitelist(self):
        token = self.pair()
        data = self.request('/usage', token)
        self.assertEqual(data['fiveHour']['remaining'], 76)
        self.assertNotIn('privateField', data)
        changed = quota(); changed['weekly']['remaining'] = 0
        atomic_json(self.source, changed)
        self.assertEqual(self.request('/usage', token)['weekly']['remaining'], 0)
        self.assertEqual(self.bridge.snapshot()['online'], 1)
        for bad in ([], None, dict(status='ok', updatedAt=0), dict(quota(), updatedAt=int(time.time())+300)):
            atomic_json(self.source, bad)
            self.assertEqual(self.request('/usage', token)['status'], 'stale')

    def test_one_time_pairing_renewal_and_revocation(self):
        original = self.bridge.invite
        token = self.pair()
        with self.assertRaises(urllib.error.HTTPError): self.request('/pair', original, 'POST')
        self.bridge.renew()
        self.assertNotEqual(self.bridge.invite, original)
        self.assertEqual(self.request('/usage', token)['status'], 'ok')
        second = self.pair()
        self.bridge.revoke()
        for item in (token, second):
            with self.assertRaises(urllib.error.HTTPError): self.request('/usage', item)
        self.assertEqual(read_json(self.root/'devices.json'), [])
        self.assertIsNone(self.bridge.snapshot()['invite'])

    def test_existing_pair_survives_restart_and_certificate_unchanged(self):
        token = self.pair()
        self.assertNotIn(token, (self.root/'devices.json').read_text())
        restored = DesktopBridge(self.root, self.source, 10)
        self.assertIsNotNone(restored.authenticated_usage(token))
        _, _, new_pin = certificate(self.root, '192.168.1.20')
        self.assertEqual(new_pin, self.pin)

    def test_expiry_and_unauthorized_requests(self):
        self.bridge.expires = time.time()-1
        with self.assertRaises(urllib.error.HTTPError): self.request('/pair', self.bridge.invite, 'POST')
        for path in ('/usage', '/control', '/settings', '/credentials'):
            with self.assertRaises(urllib.error.HTTPError): self.request(path, 'invalid')
        self.assertEqual(self.bridge.snapshot()['online'], 0)

    def test_stalled_tls_does_not_block_real_client(self):
        stalled = socket.create_connection(('127.0.0.1', self.server.server_port))
        try:
            start = time.monotonic()
            token = self.pair()
            self.assertEqual(self.request('/usage', token)['status'], 'ok')
            self.assertLess(time.monotonic()-start, 3)
        finally:
            stalled.close()


class DesktopLifecycleTests(unittest.TestCase):
    def wait_for(self, predicate, timeout=15):
        end = time.monotonic()+timeout
        while time.monotonic() < end:
            value = predicate()
            if value: return value
            time.sleep(.1)
        self.fail('Timed out waiting for desktop service state')

    def test_process_qr_commands_and_owner_exit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); state = root/'state'; control = root/'control'
            source = root/'usage.json'; atomic_json(source, quota())
            s = socket.socket(); s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]; s.close()
            flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
            parent = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], creationflags=flags)
            exe = os.environ.get('MOBILE_TEST_EXE')
            command = [exe] if exe else [sys.executable, str(Path(__file__).with_name('desktop.py'))]
            command += ['--host','127.0.0.1','--test-loopback','--port',str(port),'--owner',str(parent.pid),
                        '--state',str(state),'--control',str(control),'--usage',str(source),'--session','test-session']
            process = subprocess.Popen(command, creationflags=flags)
            def status(): return read_json(control/'status.json', {})
            try:
                self.wait_for(lambda: status().get('state') == 'running')
                spec = json.loads(base64.urlsafe_b64decode((control/'pairing.txt').read_text()[5:]))
                request = client(state/'server.pem', port)
                token = request('/pair', spec['code'], 'POST')['token']
                self.assertEqual(request('/usage', token)['weekly']['remaining'], 24)
                self.wait_for(lambda: status().get('online') == 1 and not (control/'pairing.png').exists())
                atomic_json(control/'command-1.json', dict(session='wrong-session', action='revoke'))
                self.wait_for(lambda: not (control/'command-1.json').exists())
                self.assertEqual(request('/usage', token)['status'], 'ok')
                atomic_json(control/'command-2.json', dict(session='test-session', action='renew'))
                self.wait_for(lambda: (control/'pairing.png').exists())
                self.assertEqual(request('/usage', token)['status'], 'ok')
                atomic_json(control/'command-3.json', dict(session='test-session', action='revoke'))
                self.wait_for(lambda: status().get('paired') == 0)
                with self.assertRaises(urllib.error.HTTPError): request('/usage', token)
                atomic_json(control/'command-4.json', dict(session='test-session', action='renew'))
                self.wait_for(lambda: (control/'pairing.png').exists())
                parent.terminate(); parent.wait(timeout=5)
                self.assertEqual(process.wait(timeout=10), 0)
                self.assertEqual(status()['state'], 'stopped')
                self.assertFalse((control/'pairing.txt').exists())
                with self.assertRaises(OSError): socket.create_connection(('127.0.0.1', port), timeout=1)
            finally:
                for child in (process, parent):
                    if child.poll() is None: child.terminate(); child.wait(timeout=5)

class ConnectionDeadlineTests(unittest.TestCase):
    """The reaper is the only thing that can end a connection that keeps trickling bytes."""

    def _pair(self):
        return socket.socketpair()

    def test_reaper_closes_a_connection_that_outlives_its_limit(self):
        server_end, client_end = self._pair()
        deadline = ConnectionDeadline(1)
        deadline.add(server_end)
        deadline.start()
        try:
            client_end.settimeout(10)
            start = time.monotonic()
            self.assertEqual(client_end.recv(1), b'')   # EOF: the far end was closed
            self.assertLess(time.monotonic() - start, 5)
        finally:
            deadline.close(); server_end.close(); client_end.close()

    def test_discarded_connections_are_left_alone(self):
        server_end, client_end = self._pair()
        deadline = ConnectionDeadline(1)
        deadline.add(server_end)
        deadline.discard(server_end)
        deadline.start()
        try:
            time.sleep(2.0)
            server_end.sendall(b'x')
            client_end.settimeout(5)
            self.assertEqual(client_end.recv(1), b'x')
        finally:
            deadline.close(); server_end.close(); client_end.close()


class SecurityTests(unittest.TestCase):
    """A phone must never reach anything outside the documented quota."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        state = Path(self.tmp.name)
        usage = state / 'usage.json'
        now = int(time.time())
        atomic_json(usage, dict(status='ok', updatedAt=now,
                                fiveHour=dict(remaining=76, resetsAt=now+3600),
                                weekly=dict(remaining=24, resetsAt=now+86400),
                                chatContent='MUST NOT LEAK', privateField='MUST NOT LEAK'))
        self.bridge = DesktopBridge(state, usage, 10)
        self.cert, key, _ = certificate(state, '127.0.0.1')
        self.server = make_desktop_server(self.bridge, '127.0.0.1', 0, self.cert, key)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.request = client(self.cert, self.server.server_port)

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.tmp.cleanup()

    def token(self):
        return self.request('/pair', self.bridge.invite, 'POST')['token']

    def test_only_lan_and_loopback_peers_are_served(self):
        for host in ('192.168.1.9', '10.0.0.7', '172.16.0.1', '127.0.0.1'):
            self.assertTrue(self.server.verify_request(None, (host, 1)), host)
        for host in ('8.8.8.8', '172.32.0.1', '169.254.1.1', '0.0.0.0', '::1', 'not-an-ip'):
            self.assertFalse(self.server.verify_request(None, (host, 1)), host)

    def test_usage_carries_only_the_documented_fields(self):
        body = self.request('/usage', self.token())
        self.assertEqual(sorted(body), ['fiveHour', 'serverTime', 'status', 'updatedAt', 'weekly'])
        self.assertIsInstance(body['serverTime'], int)
        self.assertEqual(sorted(body['fiveHour']), ['remaining', 'resetsAt'])
        self.assertEqual(sorted(body['weekly']), ['remaining', 'resetsAt'])
        # the extra keys that were in the file must not survive the whitelist
        raw = json.dumps(body)
        self.assertNotIn('chatContent', raw)
        self.assertNotIn('privateField', raw)
        self.assertNotIn('MUST NOT LEAK', raw)

    def test_a_device_token_is_required_and_length_bounded(self):
        for bad in ('', 'x', 'x'*5000, self.bridge.invite):
            with self.assertRaises(urllib.error.HTTPError) as caught:
                self.request('/usage', bad)
            self.assertEqual(caught.exception.code, 401)

    def test_only_the_two_documented_paths_are_served(self):
        token = self.token()
        for path in ('/', '/devices.json', '/server.pem', '/key.pem', '/usage.json',
                     '/../usage.json', '/usage?x=1', '/pair'):
            with self.assertRaises(urllib.error.HTTPError) as caught:
                self.request(path, token)
            self.assertEqual(caught.exception.code, 404, path)

    def test_requests_are_rate_limited(self):
        token = self.token()
        codes = []
        for _ in range(70):
            try:
                self.request('/usage', token); codes.append(200)
            except urllib.error.HTTPError as error:
                codes.append(error.code)
        self.assertIn(429, codes, 'the request rate must be bounded')
        self.assertEqual(codes[0], 200)


if __name__ == '__main__': unittest.main()
