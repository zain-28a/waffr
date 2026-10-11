"""The caller's IP address, for rate limits and security logs."""

import ipaddress
import os


def _trust_forwarded() -> bool:
    raw = os.getenv("TRUST_PROXY_HEADERS")
    if raw is not None:
        return raw.strip().lower() in {"1", "true", "yes"}
    # Render sets RENDER=true. Its proxy is the only way in, and it puts the
    # client's address first in X-Forwarded-For.
    return os.getenv("RENDER", "").lower() == "true"


TRUST_FORWARDED = _trust_forwarded()


def _header(scope, name: bytes) -> str | None:
    for key, value in scope.get("headers") or ():
        if key.lower() == name:
            return value.decode("latin-1")
    return None


def client_ip(scope) -> str:
    """Best guess at the caller's address; "unknown" when there is none."""
    if TRUST_FORWARDED:
        forwarded = _header(scope, b"x-forwarded-for")
        if forwarded:
            first = forwarded.split(",")[0].strip()
            try:
                return str(ipaddress.ip_address(first))
            except ValueError:
                pass
    client = scope.get("client")
    if client:
        return str(client[0])
    return "unknown"
