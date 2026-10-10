"""Offline tests for /ai. Claude is replaced by a stub; no API key needed.

Run: python -m pytest _test_ai.py
"""

from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import ai_service
from ai_schemas import CategorizeResponse, Insight, InsightsResponse
from auth import get_current_user
from routers.ai import router


class _StubMessages:
    def __init__(self, answer, stop_reason="end_turn"):
        self.answer = answer
        self.stop_reason = stop_reason
        self.calls = []

    def parse(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(
            stop_reason=self.stop_reason,
            parsed_output=self.answer,
        )


def _stub_client(monkeypatch, answer, stop_reason="end_turn"):
    messages = _StubMessages(answer, stop_reason)
    client = SimpleNamespace(beta=SimpleNamespace(messages=messages))
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test")
    monkeypatch.setattr(ai_service, "_client", client)
    return messages


@pytest.fixture
def api(monkeypatch):
    monkeypatch.setattr(ai_service, "_usage", ai_service.defaultdict(int))
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=7)
    return TestClient(app)


INSIGHTS_BODY = {
    "kind": "weekly",
    "currency": "SYP",
    "period_label": "هذا الأسبوع",
    "days_elapsed": 3,
    "days_total": 7,
    "monthly_income": 1000,
    "balance": 400,
    "cycle_spent": 600,
    "max_balance": 1000,
    "days_until_income": 12,
    "categories": [{"name": "طعام", "current": 300, "previous": 200}],
}


def _insights_answer(count=2):
    return InsightsResponse(
        headline="h",
        insights=[
            Insight(tone="tip", title=f"t{i}", body="b") for i in range(count)
        ],
        savings_suggestion=None,
        summary="s",
    )


def test_insights_returns_the_model_answer(api, monkeypatch):
    messages = _stub_client(monkeypatch, _insights_answer())

    response = api.post("/ai/insights", json=INSIGHTS_BODY)

    assert response.status_code == 200
    assert response.json()["headline"] == "h"
    call = messages.calls[0]
    assert call["model"] == ai_service.MODEL
    assert call["output_format"] is InsightsResponse
    assert call["fallbacks"] == "default"
    # Only totals travel: the payload is the request body as sent.
    assert "طعام" in call["messages"][0]["content"]


def test_insights_are_capped_at_four(api, monkeypatch):
    _stub_client(monkeypatch, _insights_answer(count=6))

    response = api.post("/ai/insights", json=INSIGHTS_BODY)

    assert len(response.json()["insights"]) == 4


def test_missing_key_is_503(api, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)

    response = api.post("/ai/insights", json=INSIGHTS_BODY)

    assert response.status_code == 503


def test_refusal_is_503(api, monkeypatch):
    _stub_client(monkeypatch, None, stop_reason="refusal")

    response = api.post("/ai/insights", json=INSIGHTS_BODY)

    assert response.status_code == 503


def test_daily_limit_is_429(api, monkeypatch):
    _stub_client(monkeypatch, _insights_answer())
    limit = ai_service.DAILY_LIMITS["insights"]

    codes = [
        api.post("/ai/insights", json=INSIGHTS_BODY).status_code
        for _ in range(limit + 1)
    ]

    assert codes[:limit] == [200] * limit
    assert codes[-1] == 429


def test_categorize_keeps_only_known_names(api, monkeypatch):
    body = {"note": "شاورما", "categories": ["طعام", "مواصلات"]}

    _stub_client(monkeypatch, CategorizeResponse(category="طعام"))
    assert api.post("/ai/categorize", json=body).json() == {"category": "طعام"}

    _stub_client(monkeypatch, CategorizeResponse(category="مطاعم"))
    assert api.post("/ai/categorize", json=body).json() == {"category": None}


def test_requests_need_a_user(monkeypatch):
    app = FastAPI()
    app.include_router(router)
    client = TestClient(app)

    response = client.post("/ai/categorize", json={"note": "x1", "categories": ["a"]})

    assert response.status_code == 401
