import tempfile
import threading
import unittest
import time
import json
import socket
import ssl
import urllib.request
import urllib.error
from pathlib import Path
from bridge import (Bridge, ConnectionDeadline, SourceConcurrencyLimit,
                    SourceRateLimit, certificate, make_server, sanitize, is_lan_ip)

class BridgeTests(unittest.TestCase):
    def test_lan_addresses_exclude_loopback_stale_link_local_and_public(self):
        for host in ("192.168.3.44", "10.0.0.1", "172.16.1.5"):
            self.assertTrue(is_lan_ip(host))
        for host in ("127.0.0.1", "169.254.1.5", "8.8.8.8", "0.0.0.0", "::1", "bad"):
            self.assertFalse(is_lan_ip(host))
    def test_whitelist_and_staleness(self):
        data={"status":"ok","updatedAt":int(time.time()),"secret":"DO NOT SEND","fiveHour":{"remaining":75,"resetsAt":int(time.time())+600},"weekly":{"remaining":5,"resetsAt":int(time.time())+600}}
        self.assertEqual(sanitize(data)["status"],"ok")
        self.assertNotIn("secret",sanitize(data))
        data["weekly"]["remaining"]=float("nan")
        self.assertEqual(sanitize(data)["status"],"stale")

    def test_tls_pairing_one_use_and_authorization(self):
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp); b=Bridge(state); cert,key,pin=certificate(state,"127.0.0.1")
            server=make_server(b,"127.0.0.1",0,cert,key)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            context=ssl.create_default_context(cafile=str(cert))
            base=f"https://127.0.0.1:{server.server_port}"
            def request(path,token,method="GET"):
                r=urllib.request.Request(base+path,headers={"Authorization":"Bearer "+token},method=method)
                opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=context))
                return json.loads(opener.open(r,timeout=5).read())
            try:
                with self.assertRaises(urllib.error.HTTPError):request("/usage","bad")
                invite=b.invite
                token=request("/pair",invite,"POST")["token"]
                with self.assertRaises(urllib.error.HTTPError):request("/pair",invite,"POST")
                self.assertEqual(request("/usage",token)["status"],"stale")
                self.assertNotIn(token,(state/"devices.json").read_text())
                self.assertEqual(len(pin),64)
            finally:server.shutdown();server.server_close();thread.join()

    def test_stalled_handshake_does_not_block_a_real_client(self):
        # Regression: the listener used to be wrapped with ssl.wrap_socket, which moves
        # the handshake into accept() on the accept loop, so one client that connected
        # and never finished the handshake wedged every other client.
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp); b=Bridge(state); cert,key,pin=certificate(state,"127.0.0.1")
            server=make_server(b,"127.0.0.1",0,cert,key)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            stalled=socket.create_connection(("127.0.0.1",server.server_port))
            try:
                context=ssl.create_default_context(cafile=str(cert))
                opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=context))
                start=time.monotonic()
                request=urllib.request.Request(f"https://127.0.0.1:{server.server_port}/usage",
                                               headers={"Authorization":"Bearer bad"},method="GET")
                with self.assertRaises(urllib.error.HTTPError):opener.open(request,timeout=5)
                self.assertLess(time.monotonic()-start,3)
            finally:
                stalled.close();server.shutdown();server.server_close();thread.join()


class ConnectionDeadlineTests(unittest.TestCase):
    """The reaper is what bounds a connection that keeps trickling bytes.

    settimeout() bounds one send/recv, so a client that dribbles resets it on every read
    and can hold a worker slot forever. These tests pin the mechanism down directly
    rather than through a real dribbling client, whose behaviour depends on how the TLS
    stack happens to buffer its reads.
    """

    def test_reaper_closes_a_connection_that_outlives_its_limit(self):
        server_end, client_end = socket.socketpair()
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
        server_end, client_end = socket.socketpair()
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

    def test_close_releases_everything_still_tracked(self):
        server_end, client_end = socket.socketpair()
        deadline = ConnectionDeadline(600)
        deadline.add(server_end)
        deadline.start()
        try:
            deadline.close()
            client_end.settimeout(5)
            self.assertEqual(client_end.recv(1), b'')
        finally:
            server_end.close(); client_end.close()

class SecurityTests(unittest.TestCase):
    """A phone must never reach anything outside the documented quota."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        state = Path(self.tmp.name)
        now = int(time.time())
        (state / "usage.json").write_text(json.dumps(dict(
            status="ok", updatedAt=now, fiveHour=dict(remaining=76, resetsAt=now+3600),
            weekly=dict(remaining=24, resetsAt=now+86400),
            chatContent="MUST NOT LEAK", privateField="MUST NOT LEAK")), encoding="utf-8")
        self.bridge = Bridge(state)
        cert, key, _ = certificate(state, "127.0.0.1")
        self.cert = cert
        self.server = make_server(self.bridge, "127.0.0.1", 0, cert, key)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.tmp.cleanup()

    def call(self, path, token, method="GET"):
        context = ssl.create_default_context(cafile=str(self.cert))
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context))
        request = urllib.request.Request(f"https://127.0.0.1:{self.server.server_port}"+path,
                                         headers={"Authorization":"Bearer "+token}, method=method)
        return json.loads(opener.open(request, timeout=5).read())

    def token(self):
        return self.call("/pair", self.bridge.invite, "POST")["token"]

    def test_only_lan_and_loopback_peers_are_served(self):
        for host in ("192.168.1.9", "10.0.0.7", "172.16.0.1", "127.0.0.1"):
            self.assertTrue(self.server.verify_request(None, (host, 1)), host)
        for host in ("8.8.8.8", "172.32.0.1", "169.254.1.1", "0.0.0.0", "::1", "not-an-ip"):
            self.assertFalse(self.server.verify_request(None, (host, 1)), host)

    def test_usage_carries_only_the_documented_fields(self):
        body = self.call("/usage", self.token())
        self.assertEqual(sorted(body), ["fiveHour", "serverTime", "status", "updatedAt", "weekly"])
        self.assertIsInstance(body["serverTime"], int)
        self.assertEqual(sorted(body["fiveHour"]), ["remaining", "resetsAt"])
        raw = json.dumps(body)
        for leak in ("chatContent", "privateField", "MUST NOT LEAK"):
            self.assertNotIn(leak, raw)

    def test_only_the_two_documented_paths_are_served(self):
        token = self.token()
        for path in ("/", "/devices.json", "/server.pem", "/key.pem", "/usage.json", "/usage?x=1", "/pair"):
            with self.assertRaises(urllib.error.HTTPError) as caught:
                self.call(path, token)
            self.assertEqual(caught.exception.code, 404, path)

    def test_oversized_headers_are_rejected_before_route_handling(self):
        context = ssl.create_default_context(cafile=str(self.cert))
        with socket.create_connection(("127.0.0.1", self.server.server_port), timeout=5) as raw:
            with context.wrap_socket(raw, server_hostname="127.0.0.1") as connection:
                connection.sendall(b"GET /usage HTTP/1.1\r\nX-Fill: "+b"x"*9000+b"\r\n\r\n")
                self.assertIn(b"431", connection.recv(4096).split(b"\r\n", 1)[0])

    def test_requests_are_rate_limited(self):
        token = self.token()
        codes = []
        for _ in range(70):
            try:
                self.call("/usage", token); codes.append(200)
            except urllib.error.HTTPError as error:
                codes.append(error.code)
        self.assertIn(429, codes, "the request rate must be bounded")
        self.assertEqual(codes[0], 200)


class LimitTests(unittest.TestCase):
    def test_new_sources_cannot_grow_rate_limit_memory_past_its_cap(self):
        limiter = SourceRateLimit(10, window=600, max_sources=2)
        self.assertTrue(limiter.allow('192.168.1.1'))
        self.assertTrue(limiter.allow('192.168.1.2'))
        self.assertFalse(limiter.allow('192.168.1.3'))
        self.assertEqual(set(limiter.hits), {'192.168.1.1', '192.168.1.2'})

    def test_one_source_cannot_occupy_all_tls_workers(self):
        limiter = SourceConcurrencyLimit(4)
        requests = [object() for _ in range(5)]
        for request in requests[:4]:
            self.assertTrue(limiter.acquire(request, '192.168.1.9'))
        self.assertFalse(limiter.acquire(requests[4], '192.168.1.9'))
        limiter.release(requests[0])
        self.assertTrue(limiter.acquire(requests[4], '192.168.1.9'))

if __name__ == '__main__': unittest.main()
