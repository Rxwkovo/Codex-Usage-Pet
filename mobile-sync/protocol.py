"""Compatibility import for the shared sync core.

The embedded service historically imported protocol from this directory.
Keep that import stable while both Python entry points use the one root module.
"""
import sys
from pathlib import Path


_ROOT = Path(__file__).resolve().parents[1]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from sync_core import (  # noqa: E402,F401
    POLICY,
    PROTOCOL_VERSION,
    Bridge,
    SourceConcurrencyLimit,
    SourceRateLimit,
    _load_certificate_pair,
    _replace,
    certificate,
    is_lan_ip,
    sanitize,
)


__all__ = [
    "POLICY",
    "PROTOCOL_VERSION",
    "Bridge",
    "SourceConcurrencyLimit",
    "SourceRateLimit",
    "certificate",
    "is_lan_ip",
    "sanitize",
]
