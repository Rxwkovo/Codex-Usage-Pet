"""Bounded HTTPS transport shared by both phone-sync entry points.

The protocol and persisted pairing state live in ``sync_core``.  This module
owns only the network boundary: TLS handshakes, connection deadlines, worker
and per-source limits, routing, and deterministic socket cleanup.
"""
import http.client
import json
import socket
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from sync_core import SourceConcurrencyLimit, SourceRateLimit, is_lan_ip


# BaseHTTPRequestHandler otherwise accepts roughly 6 MiB of headers per
# connection. Keep the tiny local API bounded before routing or authentication.
http.client._MAXLINE = 8192
http.client._MAXHEADERS = 32


def _shutdown_socket(sock):
    """Close a socket from another thread and unblock any pending read."""
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    try:
        sock.close()
    except OSError:
        pass


class ConnectionDeadline:
    """Enforce an absolute lifetime for every accepted connection."""

    def __init__(self, limit, poll_seconds=0.25):
        self.limit = limit
        self.poll_seconds = poll_seconds
        self.lock = threading.Lock()
        self.live = {}
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._reap, name="sync-connection-reaper", daemon=True)
        self.started = False

    def start(self):
        if not self.started:
            self.started = True
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
        if self.started and self.thread is not threading.current_thread():
            self.thread.join(timeout=max(1.0, self.poll_seconds * 4))

    def _reap(self):
        while not self.stop.wait(self.poll_seconds):
            now = time.monotonic()
            with self.lock:
                expired = [sock for sock, accepted in self.live.items()
                           if now - accepted > self.limit]
                for sock in expired:
                    self.live.pop(sock, None)
            for sock in expired:
                _shutdown_socket(sock)


class QuotaHandler(BaseHTTPRequestHandler):
    """The complete public API: one-use pairing and authenticated quota read."""

    def setup(self):
        self.connection = self.request
        self.connection.settimeout(self.server.handshake_timeout)
        self.connection.do_handshake()
        super().setup()

    def log_message(self, *args):
        pass  # Never log headers, tokens, invitations, or quota values.

    def reply(self, status, value):
        raw = json.dumps(value, allow_nan=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def guard(self):
        if not self.server.limiter.allow(self.client_address[0]):
            self.reply(429, {"error": "too_many_requests"})
            return False
        return True

    def do_POST(self):
        if not self.guard():
            return
        if self.path != "/pair":
            self.reply(404, {"error": "not_found"})
            return
        invitation = self.headers.get("Authorization", "").removeprefix("Bearer ")
        token = self.server.bridge.pair(invitation, self.client_address[0])
        self.reply(200 if token else 403,
                   {"token": token} if token else {"error": "pairing_rejected"})

    def do_GET(self):
        if not self.guard():
            return
        if self.path != "/usage":
            self.reply(404, {"error": "not_found"})
            return
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        data = self.server.bridge.authenticated_usage(token)
        self.reply(401 if data is None else 200,
                   {"error": "unauthorized"} if data is None else data)


class BoundedTLSServer(ThreadingHTTPServer):
    """TLS server with bounded workers, peers, request rate, and lifetime."""

    daemon_threads = True
    allow_reuse_address = False  # SO_REUSEADDR lets another Windows process steal the port.

    def __init__(self, bridge, host, port, cert, key, *, deadline_seconds=15,
                 handshake_timeout=5, max_workers=16, max_per_source=4,
                 requests_per_minute=60):
        self.bridge = bridge
        self.handshake_timeout = handshake_timeout
        self.slots = threading.BoundedSemaphore(max_workers)
        self.deadline = ConnectionDeadline(deadline_seconds)
        self.limiter = SourceRateLimit(requests_per_minute)
        self.peers = SourceConcurrencyLimit(max_per_source)
        self.tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.tls.minimum_version = ssl.TLSVersion.TLSv1_2
        self.tls.load_cert_chain(cert, key)
        self._close_lock = threading.Lock()
        self._closed = False
        super().__init__((host, port), QuotaHandler)
        self.deadline.start()

    def verify_request(self, request, client_address):
        address = client_address[0]
        if not (is_lan_ip(address) or address == "127.0.0.1"):
            return False
        return self.peers.acquire(request, address)

    def get_request(self):
        sock, address = self.socket.accept()
        try:
            wrapped = self.tls.wrap_socket(sock, server_side=True,
                                           do_handshake_on_connect=False)
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
        with self._close_lock:
            if self._closed:
                return
            self._closed = True
            self.deadline.close()
            super().server_close()


def make_bounded_server(bridge, host, port, cert, key, deadline_seconds=15):
    return BoundedTLSServer(bridge, host, port, cert, key,
                            deadline_seconds=deadline_seconds)
