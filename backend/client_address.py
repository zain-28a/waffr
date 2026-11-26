"""The caller's IP address, for rate limits and security logs.

Behind Render the socket address is Render's proxy, so the client's address
comes from a header, and only from a header a client cannot forge:

1. ``True-Client-IP``. Render's Cloudflare edge sets it to the address that
   connected and overwrites any value the client sent.
2. Else, with ``TRUSTED_PROXY_HOPS=N``, the ``X-Forwarded-For`` entry N
   places from the right: each trusted proxy appends one entry, and a client
   can only add entries to the left of them.
3. Else the left-most ``X-Forwarded-For`` entry. A client can forge it, so
   this is only a last resort, kept so nothing changes where neither of the
   above is available.

Headers are read only when ``TRUST_PROXY_HEADERS`` is on (by default when
``RENDER=true``); otherwise the socket address is used.
"""

import ipaddress
import os


def _trust_forwarded() -> bool:
    raw = os.getenv("TRUST_PROXY_HEADERS")
    if raw is not None:
        return raw.strip().lower() in {"1", "true", "yes"}
    # Render sets RENDER=true. Its proxy is the only way in.
    return os.getenv("RENDER", "").lower() == "true"


def _trusted_hops() -> int:
    try:
        return max(0, int(os.getenv("TRUSTED_PROXY_HOPS") or 0))
    except ValueError:
        return 0


TRUST_FORWARDED = _trust_forwarded()
TRUSTED_PROXY_HOPS = _trusted_hops()


def _header(scope, name: bytes) -> str | None:
    for key, value in scope.get("headers") or ():
        if key.lower() == name:
            return value.decode("latin-1")
    return None


def _valid(value: str | None) -> str | None:
    if not value:
        return None
    try:
        return str(ipaddress.ip_address(value.strip()))
    except ValueError:
        return None


def _socket_address(scope) -> str:
    client = scope.get("client")
    if client:
        return str(client[0])
    return "unknown"


def client_ip(scope) -> str:
    """Best guess at the caller's address; "unknown" when there is none."""
    if not TRUST_FORWARDED:
        return _socket_address(scope)

    edge = _valid(_header(scope, b"true-client-ip"))
    if edge is not None:
        return edge

    forwarded = _header(scope, b"x-forwarded-for")
    if forwarded:
        entries = [entry.strip() for entry in forwarded.split(",") if entry.strip()]
        if TRUSTED_PROXY_HOPS:
            # Fewer entries than trusted proxies: the header did not come
            # through them, so none of it is trusted.
            if len(entries) <= TRUSTED_PROXY_HOPS:
                return _socket_address(scope)
            chosen = _valid(entries[-1 - TRUSTED_PROXY_HOPS])
            return chosen if chosen is not None else _socket_address(scope)
        if entries:
            first = _valid(entries[0])
            if first is not None:
                return first
    return _socket_address(scope)
