"""Security behaviour of the HTTP API."""

from datetime import datetime, timedelta, timezone

import jwt
import pytest
from sqlalchemy import text

from conftest import bearer, register


def _sync_payload(**collections):
    body = {
        "last_sync_at": None,
        "settings": None,
    }
    for name in (
        "transactions",
        "savings_goals",
        "savings_transfers",
        "shopping_lists",
        "shopping_items",
        "recurring_expenses",
        "notifications",
        "expense_categories",
        "expense_presets",
    ):
        body[name] = {"upserts": collections.get(name, []), "deletes": []}
    return body


def _system_scalar(sql: str, **params):
    from database import SessionLocal
    from row_security import bind_system

    session = SessionLocal()
    bind_system(session)
    try:
        return session.scalar(text(sql), params)
    finally:
        session.close()


# Row ownership through the API


def test_users_only_reach_their_own_rows(client):
    alice = register(client, "alice@example.com")
    bob = register(client, "bob@example.com")

    created = client.post(
        "/transactions",
        json={"type": "expense", "amount": "12.50", "note": "rent"},
        headers=bearer(alice),
    )
    assert created.status_code == 201
    row_id = created.json()["id"]

    assert client.get(f"/transactions/{row_id}", headers=bearer(bob)).status_code == 404
    assert client.patch(
        f"/transactions/{row_id}", json={"amount": "1"}, headers=bearer(bob)
    ).status_code == 404
    assert client.delete(f"/transactions/{row_id}", headers=bearer(bob)).status_code == 404
    assert client.get("/transactions", headers=bearer(bob)).json() == []
    assert len(client.get("/transactions", headers=bearer(alice)).json()) == 1


def test_sync_keeps_accounts_apart(client):
    alice = register(client, "alice@example.com")
    bob = register(client, "bob@example.com")
    row = {
        "client_id": "tx-1",
        "type": "expense",
        "amount": "40",
        "occurred_at": datetime.now(timezone.utc).isoformat(),
    }

    pushed = client.post(
        "/sync", json=_sync_payload(transactions=[row]), headers=bearer(alice)
    )
    assert pushed.status_code == 200, pushed.text
    assert [r["client_id"] for r in pushed.json()["transactions"]["upserts"]] == ["tx-1"]

    # Same client_id from Bob makes Bob's own row, not a change to Alice's.
    bob_row = {**row, "amount": "1"}
    bob_sync = client.post(
        "/sync", json=_sync_payload(transactions=[bob_row]), headers=bearer(bob)
    )
    assert bob_sync.status_code == 200
    assert [r["amount"] for r in bob_sync.json()["transactions"]["upserts"]] == ["1.00"]

    alice_again = client.post("/sync", json=_sync_payload(), headers=bearer(alice))
    assert [r["amount"] for r in alice_again.json()["transactions"]["upserts"]] == ["40.00"]


def test_delete_account_removes_every_row(client):
    alice = register(client, "alice@example.com")
    bob = register(client, "bob@example.com")
    goal = client.post(
        "/savings-goals", json={"name": "car", "target_amount": "100"}, headers=bearer(alice)
    ).json()
    client.post(
        "/savings-transfers",
        json={"goal_id": goal["id"], "amount": "5", "kind": "manual"},
        headers=bearer(alice),
    )
    shopping = client.post("/shopping-lists", json={"name": "food"}, headers=bearer(alice)).json()
    client.post(f"/shopping-lists/{shopping['id']}/items", json={"name": "milk"}, headers=bearer(alice))

    assert client.delete("/auth/account", headers=bearer(alice)).status_code == 204
    assert client.get("/auth/me", headers=bearer(alice)).status_code == 401
    assert _system_scalar("SELECT count(*) FROM users") == 1
    for table in ("savings_goals", "savings_transfers", "shopping_lists", "shopping_items"):
        assert _system_scalar(f"SELECT count(*) FROM {table}") == 0, table
    assert client.get("/auth/me", headers=bearer(bob)).status_code == 200


# Tokens


def test_tokens_without_expiry_or_with_other_keys_are_refused(client):
    import auth

    register(client, "alice@example.com")
    no_expiry = jwt.encode({"sub": "1", "ver": 0}, auth.SECRET_KEY, algorithm="HS256")
    other_key = jwt.encode(
        {"sub": "1", "ver": 0, "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
        "not-the-key-" + "y" * 40,
        algorithm="HS256",
    )
    unsigned = jwt.encode({"sub": "1", "ver": 0}, None, algorithm="none")
    for token in (no_expiry, other_key, unsigned, "garbage"):
        assert client.get("/auth/me", headers=bearer(token)).status_code == 401


def test_password_change_signs_out_old_tokens(client):
    old = register(client, "alice@example.com", password="first password")
    changed = client.post(
        "/auth/password/change",
        json={"current_password": "first password", "new_password": "second password"},
        headers=bearer(old),
    )
    assert changed.status_code == 200
    assert client.get("/auth/me", headers=bearer(old)).status_code == 401
    assert client.get("/auth/me", headers=bearer(changed.json()["access_token"])).status_code == 200


# Sign-in throttling and lockout


def test_wrong_passwords_lock_the_account(client):
    register(client, "alice@example.com", password="right password")
    for _ in range(5):
        response = client.post(
            "/auth/login", json={"email": "alice@example.com", "password": "wrong password"}
        )
        assert response.status_code == 401

    locked = client.post(
        "/auth/login", json={"email": "alice@example.com", "password": "right password"}
    )
    assert locked.status_code == 429
    assert int(locked.headers["Retry-After"]) > 0

    # The lock is stored on the account, so a restart does not lift it.
    from rate_limit import limiter

    limiter.clear()
    still_locked = client.post(
        "/auth/login", json={"email": "alice@example.com", "password": "right password"}
    )
    assert still_locked.status_code == 429
    assert _system_scalar("SELECT locked_until IS NOT NULL FROM users") is True


def test_unknown_emails_are_throttled_the_same_way(client):
    for _ in range(5):
        response = client.post(
            "/auth/login", json={"email": "nobody@example.com", "password": "whatever 1"}
        )
        assert response.status_code == 401
        assert response.json()["detail"] == "Invalid email or password"
    assert (
        client.post(
            "/auth/login", json={"email": "nobody@example.com", "password": "whatever 1"}
        ).status_code
        == 429
    )


def test_successful_sign_in_clears_the_failure_count(client):
    register(client, "alice@example.com", password="right password")
    for _ in range(4):
        client.post("/auth/login", json={"email": "alice@example.com", "password": "nope nope"})
    ok = client.post(
        "/auth/login", json={"email": "alice@example.com", "password": "right password"}
    )
    assert ok.status_code == 200
    assert _system_scalar("SELECT failed_login_count FROM users") == 0


# Password reset


def test_forgot_password_answers_the_same_for_any_email(client, sent_codes):
    known = client.post("/auth/password/forgot", json={"email": "nobody@example.com"})
    register(client, "alice@example.com")
    real = client.post("/auth/password/forgot", json={"email": "alice@example.com"})
    assert known.status_code == real.status_code == 200
    assert known.json() == real.json()
    assert list(sent_codes) == ["alice@example.com"]


def test_forgot_password_is_limited_per_email(client, sent_codes):
    for _ in range(3):
        assert client.post("/auth/password/forgot", json={"email": "a@example.com"}).status_code == 200
    assert client.post("/auth/password/forgot", json={"email": "a@example.com"}).status_code == 429


def test_reset_with_code_signs_out_everywhere_and_unlocks(client, sent_codes):
    old = register(client, "alice@example.com", password="old password")
    for _ in range(5):
        client.post("/auth/login", json={"email": "alice@example.com", "password": "bad guess!"})

    client.post("/auth/password/forgot", json={"email": "alice@example.com"})
    code = sent_codes["alice@example.com"]
    wrong = "000000" if code != "000000" else "111111"
    assert client.post(
        "/auth/password/reset",
        json={"email": "alice@example.com", "code": wrong, "new_password": "new password"},
    ).status_code == 400

    reset = client.post(
        "/auth/password/reset",
        json={"email": "alice@example.com", "code": code, "new_password": "new password"},
    )
    assert reset.status_code == 200
    assert client.get("/auth/me", headers=bearer(old)).status_code == 401
    # The code works once.
    assert client.post(
        "/auth/password/reset",
        json={"email": "alice@example.com", "code": code, "new_password": "other password"},
    ).status_code == 400
    login = client.post(
        "/auth/login", json={"email": "alice@example.com", "password": "new password"}
    )
    assert login.status_code == 200


def test_reset_code_expires(client, sent_codes):
    register(client, "alice@example.com")
    client.post("/auth/password/forgot", json={"email": "alice@example.com"})
    code = sent_codes["alice@example.com"]
    from database import SessionLocal
    from row_security import bind_system

    session = SessionLocal()
    bind_system(session)
    session.execute(text("UPDATE users SET reset_code_expires_at = now() - interval '1 minute'"))
    session.commit()
    session.close()
    assert client.post(
        "/auth/password/reset",
        json={"email": "alice@example.com", "code": code, "new_password": "new password"},
    ).status_code == 400


# Rate limits


def test_register_is_limited_per_address(client):
    for number in range(10):
        register(client, f"user{number}@example.com")
    blocked = client.post(
        "/auth/register", json={"email": "user10@example.com", "password": "long enough"}
    )
    assert blocked.status_code == 429
    assert "Retry-After" in blocked.headers


def test_every_endpoint_has_a_global_limit(client):
    # The limit refills while the loop runs, so allow a little slack.
    statuses = [client.get("/auth/me").status_code for _ in range(160)]
    assert statuses[:120] == [401] * 120
    assert 429 in statuses
    # The health check stays reachable.
    assert client.get("/").status_code == 200


def test_signed_in_users_are_counted_per_account(client):
    token = register(client, "alice@example.com")
    for _ in range(130):
        assert client.get("/auth/me", headers=bearer(token)).status_code == 200


def test_sync_is_limited_per_account(client):
    token = register(client, "alice@example.com")
    statuses = [
        client.post("/sync", json=_sync_payload(), headers=bearer(token)).status_code
        for _ in range(40)
    ]
    assert statuses[:30] == [200] * 30
    assert 429 in statuses


def test_news_refresh_needs_an_account(client):
    assert client.post("/online/news/refresh").status_code == 401


def test_client_ip_uses_the_proxy_header_only_when_trusted(monkeypatch):
    import client_address

    scope = {
        "client": ("10.0.0.5", 1234),
        "headers": [(b"x-forwarded-for", b"203.0.113.9, 10.0.0.1")],
    }
    monkeypatch.setattr(client_address, "TRUST_FORWARDED", False)
    assert client_address.client_ip(scope) == "10.0.0.5"
    monkeypatch.setattr(client_address, "TRUST_FORWARDED", True)
    assert client_address.client_ip(scope) == "203.0.113.9"
    bad = {**scope, "headers": [(b"x-forwarded-for", b"not-an-ip")]}
    assert client_address.client_ip(bad) == "10.0.0.5"


# HTTP hardening


def test_security_headers(client):
    response = client.get("/")
    assert response.headers["strict-transport-security"].startswith("max-age=")
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert response.headers["cache-control"] == "no-store"
    assert "default-src 'none'" in response.headers["content-security-policy"]


def test_api_docs_are_off(client):
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert client.get(path).status_code == 404


def test_large_bodies_are_refused(client):
    big = "x" * (300 * 1024)
    response = client.post(
        "/auth/login", content=big, headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 413

    def chunks():
        for _ in range(300):
            yield b"x" * 1024

    chunked = client.post(
        "/auth/login", content=chunks(), headers={"Content-Type": "application/json"}
    )
    assert chunked.status_code == 413


def test_only_signed_in_sync_gets_the_big_body_allowance(client):
    body = b"x" * (300 * 1024)
    headers = {"Content-Type": "application/json"}
    assert client.post("/sync", content=body, headers=headers).status_code == 413
    forged = {**headers, "Authorization": "Bearer not-a-token"}
    assert client.post("/sync", content=body, headers=forged).status_code == 413


def test_sync_allows_a_bigger_body(client):
    token = register(client, "alice@example.com")
    rows = [
        {"client_id": f"tx-{index}", "type": "expense", "amount": "1", "note": "n" * 400}
        for index in range(1000)
    ]
    response = client.post("/sync", json=_sync_payload(transactions=rows), headers=bearer(token))
    assert response.status_code == 200, response.text[:200]


# Input rules


def test_control_characters_are_removed(client):
    token = register(client, "alice@example.com", name="Ali\x00ce\x07")
    assert client.get("/auth/me", headers=bearer(token)).json()["name"] == "Alice"


@pytest.mark.parametrize(
    "row",
    [
        {"client_id": "a", "type": "expense", "amount": "1e20"},
        {"client_id": "a", "type": "expense", "amount": "1", "period_key": "k" * 51},
        {"client_id": "a" * 65, "type": "expense", "amount": "1"},
    ],
)
def test_out_of_range_sync_rows_get_a_clear_error(client, row):
    token = register(client, "alice@example.com")
    response = client.post("/sync", json=_sync_payload(transactions=[row]), headers=bearer(token))
    assert response.status_code == 422
    assert "SQL" not in response.text and "psycopg" not in response.text


def test_short_passwords_are_refused_at_sign_up(client):
    response = client.post(
        "/auth/register", json={"email": "alice@example.com", "password": "short"}
    )
    assert response.status_code == 422
