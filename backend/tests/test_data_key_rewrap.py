"""POST /auth/key/rewrap: a stronger wrap of the same data key.

The app upgrades the PBKDF2 wrap of the data key (210,000 → 600,000
iterations) at sign-in. These tests pin the server's side of that: it needs
the password, replaces only the copy the device opened, never weakens the
wrap, and signs no device out.
"""

import threading

import pytest

from conftest import bearer, register, system_execute, system_scalar

PASSWORD = "correct horse 1"
OLD = {"salt": "s" * 16, "iterations": 210_000, "wrapped_key": "old-wrap-" + "w" * 40}
NEW = {"salt": "t" * 16, "iterations": 600_000, "wrapped_key": "new-wrap-" + "n" * 40}


@pytest.fixture(autouse=True)
def upgrades_on(monkeypatch):
    """These tests cover the route itself, so the switch is on (it is off by
    default, see test_key_upgrade_flag.py)."""
    monkeypatch.setenv("KEY_UPGRADE_ENABLED", "1")


def _with_key(client, email="alice@example.com"):
    token = register(client, email, password=PASSWORD)
    assert client.put("/auth/key", json=OLD, headers=bearer(token)).status_code == 200
    return token


def _rewrap(client, token, *, password=PASSWORD, expected=OLD["wrapped_key"], data_key=NEW):
    return client.post(
        "/auth/key/rewrap",
        json={"current_password": password, "expected_wrapped_key": expected, "data_key": data_key},
        headers=bearer(token),
    )


def test_a_stronger_wrap_replaces_the_old_one(client):
    token = _with_key(client)
    response = _rewrap(client, token)
    assert response.status_code == 200
    assert response.json() == {"data_key": NEW}
    assert client.get("/auth/me", headers=bearer(token)).json()["data_key"] == NEW


def test_no_device_is_signed_out(client):
    token = _with_key(client)
    other_device = client.post(
        "/auth/login", json={"email": "alice@example.com", "password": PASSWORD}
    ).json()["access_token"]
    version = system_scalar("SELECT token_version FROM users")

    assert _rewrap(client, token).status_code == 200
    assert system_scalar("SELECT token_version FROM users") == version
    assert client.get("/auth/me", headers=bearer(other_device)).status_code == 200


def test_the_password_is_required(client):
    token = _with_key(client)
    response = _rewrap(client, token, password="not my password")
    assert response.status_code == 400
    assert system_scalar("SELECT wrapped_key FROM users") == OLD["wrapped_key"]


def test_a_copy_changed_meanwhile_is_not_overwritten(client):
    """Another device or a password change replaced the wrap first."""
    token = _with_key(client)
    system_execute("UPDATE users SET wrapped_key = :w", w="other-device-" + "x" * 40)
    response = _rewrap(client, token)
    assert response.status_code == 409
    assert system_scalar("SELECT wrapped_key FROM users").startswith("other-device-")


def test_the_wrap_never_gets_weaker(client):
    token = _with_key(client)
    weaker = {**NEW, "iterations": 300_000}
    assert _rewrap(client, token, data_key=weaker).status_code == 422
    assert _rewrap(client, token).status_code == 200
    # Already at 600,000: the same or a higher count is fine, lower is not.
    again = _rewrap(client, token, expected=NEW["wrapped_key"], data_key={**NEW, "iterations": 599_999})
    assert again.status_code == 422


def test_an_account_without_a_key_has_nothing_to_rewrap(client, alice):
    assert _rewrap(client, alice).status_code == 409


def test_it_needs_a_token(client):
    response = client.post(
        "/auth/key/rewrap",
        json={"current_password": PASSWORD, "expected_wrapped_key": OLD["wrapped_key"], "data_key": NEW},
    )
    assert response.status_code == 401


def test_it_only_touches_the_callers_account(client):
    alice = _with_key(client, "alice@example.com")
    _with_key(client, "bob@example.com")
    assert _rewrap(client, alice).status_code == 200
    bob_key = system_scalar("SELECT wrapped_key FROM users WHERE email = 'bob@example.com'")
    assert bob_key == OLD["wrapped_key"]


def test_two_devices_rewrapping_at_once_leave_one_wrap(client):
    token = _with_key(client)
    barrier = threading.Barrier(2)
    statuses = []
    lock = threading.Lock()

    def go(n):
        barrier.wait()
        data_key = {**NEW, "wrapped_key": f"device-{n}-" + "d" * 40}
        status = _rewrap(client, token, data_key=data_key).status_code
        with lock:
            statuses.append((n, status))

    threads = [threading.Thread(target=go, args=(n,)) for n in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert sorted(status for _, status in statuses) == [200, 409]
    winner = next(n for n, status in statuses if status == 200)
    assert system_scalar("SELECT wrapped_key FROM users").startswith(f"device-{winner}-")


def test_a_password_change_in_between_wins(client):
    token = _with_key(client)
    changed = client.post(
        "/auth/password/change",
        json={
            "current_password": PASSWORD,
            "new_password": "a new password 2",
            "data_key": {**OLD, "wrapped_key": "after-change-" + "c" * 40},
        },
        headers=bearer(token),
    )
    assert changed.status_code == 200
    fresh = changed.json()["access_token"]
    # The device that opened the old copy, with the old password, is refused.
    assert _rewrap(client, fresh).status_code == 400
    assert _rewrap(client, fresh, password="a new password 2").status_code == 409
    assert system_scalar("SELECT wrapped_key FROM users").startswith("after-change-")


def test_retries_are_limited(client):
    from rate_limit import DATA_KEY_REWRAP_USER

    token = _with_key(client)
    statuses = [
        _rewrap(client, token, password="wrong guess").status_code
        for _ in range(DATA_KEY_REWRAP_USER.limit + 1)
    ]
    assert statuses[:-1] == [400] * DATA_KEY_REWRAP_USER.limit
    assert statuses[-1] == 429


def test_the_encrypted_rows_are_not_touched(client):
    from conftest import sync

    token = _with_key(client)
    sync(client, token, transactions=[{"client_id": "t", "type": "expense", "amount": "5", "note": "enc1:sealed"}])
    assert _rewrap(client, token).status_code == 200
    assert system_scalar("SELECT note FROM transactions") == "enc1:sealed"
