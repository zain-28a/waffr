"""Tests run against a real, throwaway Postgres: row security needs one.

    TEST_DATABASE_URL=postgresql://user:pass@localhost:5432/waffer_test \
        python -m pytest backend/tests

Every table in that database is emptied between tests. Without the variable
the tests are skipped.
"""

import os
import sys
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parents[1]
TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL")

if TEST_DATABASE_URL:
    os.environ["DATABASE_URL"] = TEST_DATABASE_URL
    os.environ.setdefault("SECRET_KEY", "test-secret-" + "x" * 40)
    os.environ.pop("ENABLE_API_DOCS", None)
    os.environ.pop("CORS_ORIGINS", None)
    os.environ["TRUST_PROXY_HEADERS"] = "0"
    for name in ("SMTP_HOST", "SMTP_USERNAME", "SMTP_PASSWORD", "SMTP_FROM"):
        os.environ[name] = "test"
    sys.path.insert(0, str(BACKEND))


def pytest_collection_modifyitems(config, items):
    if TEST_DATABASE_URL:
        return
    skip = pytest.mark.skip(reason="TEST_DATABASE_URL is not set")
    for item in items:
        item.add_marker(skip)


@pytest.fixture(scope="session")
def main_module():
    import main

    return main


@pytest.fixture(autouse=True)
def clean_state(request):
    if not TEST_DATABASE_URL:
        yield
        return
    from sqlalchemy import text

    import main  # noqa: F401  (creates the tables and policies)
    from database import Base, engine
    from rate_limit import limiter

    tables = ", ".join(Base.metadata.tables)
    with engine.begin() as connection:
        connection.execute(text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE"))
    limiter.clear()
    yield


@pytest.fixture
def client(main_module):
    from fastapi.testclient import TestClient

    # No "with": the lifespan would start the hourly news fetch.
    return TestClient(main_module.app)


@pytest.fixture
def sent_codes(monkeypatch):
    """Reset emails, captured instead of sent."""
    import password_reset

    sent: dict[str, str] = {}
    monkeypatch.setattr(password_reset, "send_code", lambda to, code: sent.__setitem__(to, code))
    return sent


def register(client, email, password="correct horse 1", **extra):
    response = client.post(
        "/auth/register",
        json={"email": email, "password": password, **extra},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}
