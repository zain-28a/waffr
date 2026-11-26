"""The switch for upgrading data-key wraps (POST /auth/key/rewrap).

``KEY_UPGRADE_ENABLED`` is **off unless set** to 1, true or yes. While it is
off, the rewrap route refuses every request with 403 before it reads the
password or touches the database, so no account's wrap can change.

The value is read on every request, not at start-up, so a test or an
operator's restart sees the current setting. Production changes to it need
the owner's explicit approval (RELEASE_B_READINESS_PLAN.md, §5).

Eligibility rules (app versions, the 90-day window, cohorts) will be added
here when the guard is built; until then this flag is the only gate.
"""

import os

FLAG = "KEY_UPGRADE_ENABLED"
REFUSED_DETAIL = "key_upgrade_not_allowed"


def enabled() -> bool:
    """True only when KEY_UPGRADE_ENABLED is 1, true or yes (any case)."""
    return (os.getenv(FLAG) or "").strip().lower() in {"1", "true", "yes"}
