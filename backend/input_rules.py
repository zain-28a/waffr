"""Shared rules for request bodies."""

import re
from decimal import Decimal

from pydantic import BaseModel, model_validator

# Largest value a NUMERIC(18, 2) column holds.
MONEY_MAX = Decimal("9999999999999999.99")
# Postgres INTEGER.
INT_MAX = 2_147_483_647

# C0 controls and DEL, except tab, newline and carriage return.
_CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
# Passwords are hashed, never stored or shown; they keep every character.
_RAW_FIELDS = frozenset({"password", "current_password", "new_password"})


def _clean(value):
    if isinstance(value, str):
        return _CONTROL_RE.sub("", value)
    if isinstance(value, dict):
        return {_clean(key): _clean(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_clean(item) for item in value]
    return value


class CleanModel(BaseModel):
    """A request body with control characters removed from its text.

    Postgres cannot store NUL, and nothing in the app types the others, so
    they only arrive in crafted requests.
    """

    @model_validator(mode="before")
    @classmethod
    def _strip_control_characters(cls, data):
        if not isinstance(data, dict):
            return data
        return {
            key: value if key in _RAW_FIELDS else _clean(value)
            for key, value in data.items()
        }
