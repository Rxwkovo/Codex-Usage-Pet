"""Shared pairing, certificate and quota-filtering core for both sync entry points.

This module is deliberately *protocol only*: private-LAN source checks,
certificate identity, the device-token store and the quota whitelist. It must
not import an HTTP server or either entry point.

The TLS listener used to live here as ``make_server``, which wrapped the
*listening* socket (``ssl.wrap_socket(server.socket, ...)``). That performs the
handshake inside ``accept()`` on the server's accept loop, so a single client
that connects and never completes the handshake wedged the whole bridge. The
listener now lives in ``desktop.py`` and defers the handshake to a bounded
worker; see ``make_desktop_server``. Do not reintroduce a server here.
"""
import hashlib
import hmac
import ipaddress
import json
import math
import os
import secrets
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


PROTOCOL_VERSION = 2
POLICY = {
    "refreshSeconds": 60,
    "staleSeconds": 120,
    "clockSkewToleranceSeconds": 5,
    "happyMinRemaining": 50,
    "worriedMaxRemaining": 20,
    "exhaustedMaxRemaining": 0,
}


def _finite_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("expected a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("expected a finite number")
    return number


def _unix_seconds(value):
    number = _finite_number(value)
    if not number.is_integer():
        raise ValueError("expected integer Unix seconds")
    return int(number)


def normalize_policy(policy=None):
    """Validate a trusted policy source; never read policy from a usage snapshot."""
    if policy is None:
        return dict(POLICY)
    if not isinstance(policy, dict):
        raise ValueError("policy must be an object")
    required = set(POLICY)
    if not required.issubset(policy):
        raise ValueError("policy is incomplete")
    result = {key: _finite_number(policy[key]) for key in POLICY}
    if not 30 <= result["refreshSeconds"] <= 600:
        raise ValueError("refreshSeconds is out of range")
    if not 60 <= result["staleSeconds"] <= 3600:
        raise ValueError("staleSeconds is out of range")
    if result["staleSeconds"] < result["refreshSeconds"] + 30:
        raise ValueError("staleSeconds must exceed refreshSeconds")
    if result["clockSkewToleranceSeconds"] != 5:
        raise ValueError("clock skew tolerance is fixed")
    if not 1 <= result["happyMinRemaining"] <= 100:
        raise ValueError("happy threshold is out of range")
    if not 0 <= result["worriedMaxRemaining"] <= 99:
        raise ValueError("worried threshold is out of range")
    if result["happyMinRemaining"] <= result["worriedMaxRemaining"]:
        raise ValueError("happy threshold must exceed worried threshold")
    if result["exhaustedMaxRemaining"] != 0:
        raise ValueError("exhausted threshold is fixed")
    return result


def is_lan_ip(host):
    try:
        ip = ipaddress.ip_address(host)
        return ip.version == 4 and any(ip in ipaddress.ip_network(net) for net in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))
    except ValueError:
        return False


def sanitize(data, now=None, policy=None):
    """Whitelist only the documented quota fields; reject non-finite percentages."""
    now = time.time() if now is None else float(now)
    policy = normalize_policy(policy)
    result = {
        "protocolVersion": PROTOCOL_VERSION,
        "policy": policy,
        "status": "stale",
        "updatedAt": 0,
        "serverTime": int(now),
        "fiveHour": None,
        "weekly": None,
    }
    # usage.json is a file on disk, so anything at all can be in it. Without this
    # guard a top-level array/string/null made data.get raise AttributeError, which
    # the callers only catch as (OSError, ValueError): the request thread died and
    # the phone saw a reset connection instead of JSON.
    if not isinstance(data, dict):
        return result
    try:
        stamp = _unix_seconds(data.get("updatedAt", 0))
        result["updatedAt"] = stamp
        for field in ("fiveHour", "weekly"):
            window = data.get(field)
            if not isinstance(window, dict):
                continue
            value = _finite_number(window["remaining"])
            if not 0 <= value <= 100:
                continue
            result[field] = {"remaining": value,
                             "resetsAt": _unix_seconds(window.get("resetsAt"))}
        if (data.get("status") == "ok"
                and -policy["clockSkewToleranceSeconds"] <= now - stamp < policy["staleSeconds"]
                and all(
            result[k] is not None and result[k]["resetsAt"] > now for k in ("fiveHour", "weekly")
        )):
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
    """Return (cert_path, key_path, pin) for a self-signed cert bound to host.

    The pin is the SHA-256 of the DER-encoded certificate, which is exactly what
    the Android client computes over ``X509Certificate.encoded``.

    The desktop service and the standalone bridge share this state directory and
    neither takes a lock here, so a pair that does not actually match is treated as
    missing and regenerated. Previously a half-written pair (both processes finding
    no certificate and interleaving their writes) made ``load_cert_chain`` fail on
    every later start until the files were deleted by hand.
    """
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
    every request costs a TLS handshake and a worker slot. The map is bounded the same way
    the pairing limiter had to be: a scanner must not be able to grow it without limit.
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
            if address not in self.hits and len(self.hits) >= self.max_sources:
                self.hits = {k: v for k, v in self.hits.items() if now - v[1] < self.window}
                if len(self.hits) >= self.max_sources:
                    return False
            count, started = self.hits.get(address, (0, now))
            if now - started >= self.window:
                count, started = 0, now
            if count >= self.limit:
                self.hits[address] = (count, started)
                return False
            self.hits[address] = (count + 1, started)
            return True


class SourceConcurrencyLimit:
    """Prevent one LAN peer from occupying every bounded TLS worker."""

    def __init__(self, limit=4):
        self.limit = limit
        self.lock = threading.Lock()
        self.counts = {}
        self.accepted = {}

    def acquire(self, request, address):
        with self.lock:
            count = self.counts.get(address, 0)
            if count >= self.limit:
                return False
            self.counts[address] = count + 1
            self.accepted[request] = address
            return True

    def release(self, request):
        with self.lock:
            address = self.accepted.pop(request, None)
            if address is None:
                return
            count = self.counts.get(address, 0) - 1
            if count > 0:
                self.counts[address] = count
            else:
                self.counts.pop(address, None)


class Bridge:
    """One-use invitation codes and hashed device tokens.

    Both entry points use this class directly or subclass it for local UI state.
    """

    def __init__(self, state, policy=None):
        self.state = state
        self.invite = secrets.token_urlsafe(32)
        self.expires = time.time() + 600
        self.lock = threading.Lock()
        self.tokens_file = state / "devices.json"
        self.policy = normalize_policy(policy)
        self.tokens = self._read_tokens()
        self.attempts = {}

    def _read_tokens(self):
        try:
            stored = json.loads(self.tokens_file.read_text())
            return stored if isinstance(stored, list) else []
        except (OSError, ValueError):
            return []

    def pair(self, code, address):
        # Headers are untrusted, and http.client decodes them as latin-1, so a
        # non-ASCII Authorization value reaches hmac.compare_digest and makes it
        # raise TypeError. That used to kill the request thread with no reply.
        if not isinstance(code, str) or not code.isascii() or len(code) > 128:
            return None
        with self.lock:
            if address not in self.attempts and len(self.attempts) >= 256:
                self.attempts = {k: v for k, v in self.attempts.items()
                                 if time.time() - v[1] < 60}
                if len(self.attempts) >= 256:
                    return None
            count, started = self.attempts.get(address, (0, time.time()))
            if time.time() - started > 60:
                count, started = 0, time.time()
            self.attempts[address] = (count + 1, started)
            if count >= 10 or not self.invite or time.time() > self.expires or not hmac.compare_digest(code, self.invite):
                return None
            token = secrets.token_urlsafe(32)
            # Re-read from disk first: the desktop service and the standalone bridge
            # can share this directory, and an in-memory list from start-up would
            # silently drop a device that the other process paired.
            self.tokens = self._read_tokens()
            self.tokens.append(hashlib.sha256(token.encode()).hexdigest())
            self.tokens = self.tokens[-10:]
            _replace(self.tokens_file, json.dumps(self.tokens).encode())
            self.invite = None
            return token

    def revoke(self):
        """Atomically revoke every device token and the current invitation."""
        with self.lock:
            _replace(self.tokens_file, b"[]")
            self.tokens = []
            self.invite = None
            self.expires = 0

    def authorized(self, token):
        # A device token is 32 random bytes; anything longer was never issued by us.
        if not isinstance(token, str) or len(token) > 128:
            return False
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            return any(hmac.compare_digest(digest, saved) for saved in self.tokens)

    def authenticated_usage(self, token):
        """Return a snapshot only while the token remains paired."""
        if not isinstance(token, str) or len(token) > 128:
            return None
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            if not any(hmac.compare_digest(digest, saved) for saved in self.tokens):
                return None
            # Holding the pairing lock prevents a successful response from racing
            # with revoke(). Entry-specific Bridge subclasses may also record use.
            return self.usage()

    def usage(self):
        try:
            return sanitize(json.loads((self.state / "usage.json").read_text(encoding="utf-8-sig")),
                            policy=self.policy)
        except (OSError, ValueError, AttributeError):
            return sanitize({}, policy=self.policy)
