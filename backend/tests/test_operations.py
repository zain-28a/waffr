"""Operations: readiness check, database failures, password hashing limits,
and complete account deletion."""

import threading
import time

import pytest

from conftest import bearer, register, sync, system_execute, system_scalar


# Readiness


@pytest.fixture
def fresh_health(main_module, monkeypatch):
    monkeypatch.setitem(main_module._health, "checked_at", float("-inf"))
    return main_module


def test_healthz_reports_a_reachable_database(client, fresh_health):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_healthz_says_only_unavailable_when_the_database_is_down(
    client, fresh_health, monkeypatch
):
    def broken():
        raise RuntimeError("could not connect to db.internal:5432 as waffer_user")

    monkeypatch.setattr(fresh_health.engine, "connect", broken)
    response = client.get("/healthz")
    assert response.status_code == 503
    assert response.json() == {"status": "unavailable"}
    assert "db.internal" not in response.text


def test_healthz_answers_are_cached_briefly(client, fresh_health, monkeypatch):
    calls = []
    original = fresh_health._database_reachable

    def counted():
        calls.append(1)
        return original()

    monkeypatch.setattr(fresh_health, "_database_reachable", counted)
    for _ in range(5):
        assert client.get("/healthz").status_code == 200
    assert len(calls) == 1


def test_the_liveness_check_does_not_touch_the_database(client, main_module, monkeypatch):
    monkeypatch.setattr(main_module.engine, "connect", lambda: 1 / 0)
    assert client.get("/").status_code == 200


# Database failures


def test_a_database_outage_is_a_retryable_503_without_details(client, alice, monkeypatch):
    from sqlalchemy.exc import OperationalError

    import auth

    def down(*_args, **_kwargs):
        raise OperationalError("SELECT", {}, Exception("server at 10.0.0.5 closed the connection"))

    monkeypatch.setattr(auth, "bind_user", down)
    response = client.get("/auth/me", headers=bearer(alice))
    assert response.status_code == 503
    assert response.headers["Retry-After"]
    assert "10.0.0.5" not in response.text


def test_connections_carry_a_statement_timeout():
    from sqlalchemy import text

    from database import STATEMENT_TIMEOUT_MS, engine

    with engine.connect() as connection:
        value = connection.scalar(text("SHOW statement_timeout"))
    assert value == f"{STATEMENT_TIMEOUT_MS // 1000}s"


def test_a_query_over_the_timeout_is_cancelled(client):
    from sqlalchemy import text
    from sqlalchemy.exc import OperationalError

    from database import engine

    with engine.connect() as connection:
        connection.execute(text("SET LOCAL statement_timeout = 100"))
        with pytest.raises(OperationalError):
            connection.execute(text("SELECT pg_sleep(2)"))


# Password hashing


def test_new_passwords_use_the_lighter_argon2_settings(client, alice):
    stored = system_scalar("SELECT password_hash FROM users")
    assert stored.startswith("$argon2id$v=19$m=19456,t=2,p=1$")


def test_old_hashes_still_sign_in_and_are_upgraded_without_signing_out(client):
    from pwdlib import PasswordHash

    token = register(client, "alice@example.com", password="right password")
    heavy = PasswordHash.recommended().hash("right password")  # m=65536,t=3,p=4
    system_execute("UPDATE users SET password_hash = :h", h=heavy)

    response = client.post(
        "/auth/login", json={"email": "alice@example.com", "password": "right password"}
    )
    assert response.status_code == 200
    assert system_scalar("SELECT password_hash FROM users").startswith("$argon2id$v=19$m=19456")
    # The token from before still works: nobody is signed out.
    assert client.get("/auth/me", headers=bearer(token)).status_code == 200
    # And the new hash checks the same password.
    again = client.post(
        "/auth/login", json={"email": "alice@example.com", "password": "right password"}
    )
    assert again.status_code == 200


def test_only_a_few_password_hashes_run_at_once(monkeypatch):
    import auth

    running = []
    peak = []
    lock = threading.Lock()
    original = auth.password_hash.verify

    def slow_verify(password, hashed):
        with lock:
            running.append(1)
            peak.append(len(running))
        time.sleep(0.05)
        try:
            return original(password, hashed)
        finally:
            with lock:
                running.pop()

    monkeypatch.setattr(auth.password_hash, "verify", slow_verify)
    threads = [threading.Thread(target=auth.burn_password_check, args=("x",)) for _ in range(12)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert max(peak) <= auth.HASH_CONCURRENCY


def test_a_full_hashing_queue_answers_503(client, monkeypatch):
    import auth

    monkeypatch.setattr(auth, "HASH_WAIT_SECONDS", 0.05)
    taken = [auth._hash_slots.acquire(timeout=1) for _ in range(auth.HASH_CONCURRENCY)]
    try:
        response = client.post(
            "/auth/login", json={"email": "nobody@example.com", "password": "whatever 1"}
        )
    finally:
        for ok in taken:
            if ok:
                auth._hash_slots.release()
    assert response.status_code == 503
    assert response.headers["Retry-After"]


# Account deletion


def _owned_rows(user_id: int) -> dict[str, int]:
    from row_security import OWNED_TABLES

    return {
        table: system_scalar(f"SELECT count(*) FROM {table} WHERE user_id = :u", u=user_id)
        for table in OWNED_TABLES
    }


def _fill(client, token):
    sync(
        client,
        token,
        transactions=[{"client_id": "t", "type": "expense", "amount": "5", "updated_at": "2025-01-01T00:00:00Z"}],
        savings_goals=[{"client_id": "g", "name": "enc1:x", "target_amount": "9"}],
        savings_transfers=[{"client_id": "tr", "goal_client_id": "g", "amount": "1", "kind": "manual"}],
        shopping_items=[{"client_id": "i", "name": "enc1:milk"}],
        recurring_expenses=[{"client_id": "r", "amount": "3", "category": "enc1:c"}],
        notifications=[{"client_id": "n", "type": "t", "title": "x", "message": "y", "event_key": "k"}],
        expense_categories=[{"client_id": "c", "label": "enc1:l"}],
        expense_presets=[{"client_id": "p", "amount": "2", "category": "enc1:c"}],
        settings={"dark_mode": True},
    )


def test_deleting_an_account_removes_every_owned_row_and_nothing_else(client, alice, bob):
    _fill(client, alice)
    _fill(client, bob)
    alice_id = system_scalar("SELECT id FROM users WHERE email = 'alice@example.com'")
    bob_id = system_scalar("SELECT id FROM users WHERE email = 'bob@example.com'")
    assert all(count >= 1 for count in _owned_rows(alice_id).values())

    response = client.delete("/auth/account", headers=bearer(alice))
    assert response.status_code == 204

    assert all(count == 0 for count in _owned_rows(alice_id).values())
    assert system_scalar("SELECT count(*) FROM users WHERE id = :u", u=alice_id) == 0
    assert all(count >= 1 for count in _owned_rows(bob_id).values())
    assert client.get("/auth/me", headers=bearer(alice)).status_code == 401


def test_a_failed_account_deletion_keeps_everything(client, alice, main_module, monkeypatch):
    from sqlalchemy.exc import OperationalError

    _fill(client, alice)
    alice_id = system_scalar("SELECT id FROM users")
    before = _owned_rows(alice_id)

    real_delete = main_module.delete
    calls = []

    def flaky_delete(model):
        calls.append(model)
        if len(calls) == 5:
            raise OperationalError("DELETE", {}, Exception("connection lost"))
        return real_delete(model)

    monkeypatch.setattr(main_module, "delete", flaky_delete)
    response = client.delete("/auth/account", headers=bearer(alice))
    assert response.status_code == 503
    assert _owned_rows(alice_id) == before
    assert system_scalar("SELECT count(*) FROM users") == 1


def test_the_delete_order_covers_every_owned_table(main_module):
    from row_security import OWNED_TABLES

    assert {m.__tablename__ for m in main_module.ACCOUNT_DELETE_ORDER} == set(OWNED_TABLES)
