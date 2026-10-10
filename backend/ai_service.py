"""Spending insights and expense categories from Claude.

ANTHROPIC_API_KEY turns the feature on; without it every call raises
AiUnavailable and the app hides its AI cards. AI_MODEL swaps the model.
"""

import json
import os
import threading
import time
from collections import defaultdict

import anthropic
from pydantic import BaseModel

from ai_schemas import (
    CategorizeRequest,
    CategorizeResponse,
    InsightsRequest,
    InsightsResponse,
)

MODEL = os.getenv("AI_MODEL") or "claude-opus-5-5"

# Models that accept the server-side refusal fallback.
_FALLBACK_MODELS = {
    "claude-opus-5-5",
    "claude-opus-5",
    "claude-fable-5-1",
    "claude-sonnet-5-5",
}

# Requests per user per UTC day. The app caches insights, so these are
# ceilings against loops and abuse, not normal use.
DAILY_LIMITS = {"insights": 12, "categorize": 80}


class AiUnavailable(Exception):
    """No API key, a refused request, or an upstream failure."""


class AiRateLimited(Exception):
    """The user spent today's quota for this kind of request."""


_INSIGHTS_SYSTEM = """\
You are the analyst inside Waffr, a personal budgeting app for Arabic \
speakers. You receive a JSON summary of one user's spending (totals per \
category for the current and the previous period, balance, income, savings \
goals and recurring obligations) and return short, concrete observations.

Write every text field in clear Modern Standard Arabic with Western digits \
(0-9). Quote amounts with the currency code given in the summary.

- headline: one sentence, the single most useful thing to know right now.
- insights: two to four items. Each names a specific category, amount or \
date from the summary; skip generic advice. tone is "warning" for a risk \
(overspending, balance running out before income), "positive" for a real \
improvement, "tip" for an actionable suggestion.
- savings_suggestion: a realistic monthly amount the user could save given \
income, obligations and current spending, with a one-sentence reason. Use \
null when income is unknown or nothing can be spared.
- summary: for kind "monthly", three or four sentences reviewing the month; \
for kind "weekly", one sentence.

Base everything on the numbers given. If the data is too thin to say \
something meaningful, say so in the headline and keep insights to tips.\
"""

_CATEGORIZE_SYSTEM = """\
You file expenses for a budgeting app. Given the note a user typed for an \
expense (often Arabic, sometimes English or a brand name) and the user's \
category list, return the one category that fits best, exactly as written \
in the list. Return null when no category clearly fits.\
"""


_client: anthropic.Anthropic | None = None


def _get_client() -> anthropic.Anthropic:
    global _client
    if not os.getenv("ANTHROPIC_API_KEY"):
        raise AiUnavailable("AI is not configured")
    if _client is None:
        _client = anthropic.Anthropic(timeout=60.0, max_retries=2)
    return _client


_usage: dict[tuple[int, str, int], int] = defaultdict(int)
_usage_lock = threading.Lock()


def check_quota(user_id: int, kind: str) -> None:
    """Counts one request against the user's daily quota for [kind]."""
    day = int(time.time() // 86400)
    key = (user_id, kind, day)
    with _usage_lock:
        if _usage[key] >= DAILY_LIMITS[kind]:
            raise AiRateLimited(kind)
        _usage[key] += 1
        # Drop counters from earlier days so the map stays small.
        for stale in [k for k in _usage if k[2] < day]:
            del _usage[stale]


def _ask(system: str, payload: dict, output: type[BaseModel], effort: str):
    client = _get_client()
    extra: dict = {}
    if MODEL in _FALLBACK_MODELS:
        extra = {
            "betas": ["server-side-fallback-2026-07-01"],
            "fallbacks": "default",
        }
    try:
        response = client.beta.messages.parse(
            model=MODEL,
            max_tokens=16000,
            system=system,
            output_config={"effort": effort},
            output_format=output,
            messages=[
                {
                    "role": "user",
                    "content": json.dumps(payload, ensure_ascii=False),
                }
            ],
            **extra,
        )
    except anthropic.APIError as error:
        raise AiUnavailable(str(error)) from error

    if response.stop_reason == "refusal" or response.parsed_output is None:
        raise AiUnavailable(f"no usable answer ({response.stop_reason})")
    return response.parsed_output


def insights(request: InsightsRequest) -> InsightsResponse:
    result = _ask(
        _INSIGHTS_SYSTEM,
        request.model_dump(),
        InsightsResponse,
        effort="medium",
    )
    result.insights = result.insights[:4]
    return result


def categorize(request: CategorizeRequest) -> CategorizeResponse:
    result = _ask(
        _CATEGORIZE_SYSTEM,
        request.model_dump(),
        CategorizeResponse,
        effort="low",
    )
    # Only names the app sent are valid; anything else means no match.
    if result.category not in request.categories:
        result.category = None
    return result
