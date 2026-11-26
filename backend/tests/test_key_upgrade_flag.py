"""KEY_UPGRADE_ENABLED: key upgrades are off unless an operator turns them on.

The rewrap route exists on the branch but must not change any wrap until
Release B is approved. With the switch off (the default) it refuses every
request with 403 before reading the password or touching the database.
"""

import pytest

from conftest import bearer, register, system_scalar

PASSWORD = "correct horse 1"
OLD = {"salt": "s" * 16, "iterations": 210_000, "wrapped_key": "old-wrap-" + "w" * 40}
NEW = {"salt": "t" * 16, "iterations": 600_000, "wrapped_key": "new-wrap-" + "n" * 40}


def _with_key(client, email="alice@example.com"):
    token = register(client, email, password=PASSWORD)
    assert client.put("/auth/key", json=OLD, headers=bearer(token)).status_code == 200
    return token


def _rewrap(client, token, password=PASSWORD):
    return client.post(
        "/auth/key/rewrap",
        json={
            "current_password": password,
            "expected_wrapped_key": OLD["wrapped_key"],
            "data_key": NEW,
        },
        headers=bearer(token),
    )


def test_the_switch_is_off_when_unset(monkeypatch):
    import key_upgrade

    monkeypatch.delenv("KEY_UPGRADE_ENABLED", raising=False)
    assert key_upgrade.enabled() is False


@pytest.mark.parametrize("value", ["1", "true", "TRUE", "True", "yes", "YES", " 1 "])
def test_these_values_turn_it_on(monkeypatch, value):
    import key_upgrade

    monkeypatch.setenv("KEY_UPGRADE_ENABLED", value)
    assert key_upgrade.enabled() is True


@pytest.mark.parametrize("value", ["", "0", "false", "no", "off", "enabled", "2", "tru", "on"])
def test_everything_else_leaves_it_off(monkeypatch, value):
    import key_upgrade

    monkeypatch.setenv("KEY_UPGRADE_ENABLED", value)
    assert key_upgrade.enabled() is False


def test_off_by_default_the_route_refuses_and_changes_nothing(client):
    token = _with_key(client)
    response = _rewrap(client, token)
    assert response.status_code == 403
    assert response.json() == {"detail": "key_upgrade_not_allowed"}
    assert system_scalar("SELECT wrapped_key FROM users") == OLD["wrapped_key"]
    assert system_scalar("SELECT key_iterations FROM users") == 210_000


def test_off_it_never_reads_the_password(client, monkeypatch):
    """The refusal comes before any password hashing or database work."""
    import main

    token = _with_key(client)

    def forbidden(*_args, **_kwargs):
        raise AssertionError("the password was checked while upgrades are off")

    monkeypatch.setattr(main, "verify_password", forbidden)
    assert _rewrap(client, token).status_code == 403
    # Even a wrong password gets the same answer: it is not read.
    assert _rewrap(client, token, password="not my password").status_code == 403


def test_off_the_refusal_is_not_a_sign_out(client):
    token = _with_key(client)
    assert _rewrap(client, token).status_code == 403
    assert client.get("/auth/me", headers=bearer(token)).status_code == 200


def test_off_does_not_touch_the_other_key_routes(client):
    token = register(client, "alice@example.com", password=PASSWORD)
    assert client.put("/auth/key", json=OLD, headers=bearer(token)).status_code == 200
    assert client.get("/auth/me", headers=bearer(token)).json()["data_key"] == OLD
    # Setting the key twice is still the existing 409, not the new 403.
    assert client.put("/auth/key", json=OLD, headers=bearer(token)).status_code == 409


def test_off_a_password_change_still_re_wraps_the_key(client):
    """The flag gates upgrades only: the normal password-change flow is untouched."""
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
    assert system_scalar("SELECT wrapped_key FROM users").startswith("after-change-")


def test_without_a_token_it_is_a_401_whatever_the_switch_says(client, monkeypatch):
    body = {"current_password": PASSWORD, "expected_wrapped_key": OLD["wrapped_key"], "data_key": NEW}
    assert client.post("/auth/key/rewrap", json=body).status_code == 401
    monkeypatch.setenv("KEY_UPGRADE_ENABLED", "1")
    assert client.post("/auth/key/rewrap", json=body).status_code == 401


def test_the_switch_is_read_on_every_request(client, monkeypatch):
    token = _with_key(client)
    assert _rewrap(client, token).status_code == 403
    monkeypatch.setenv("KEY_UPGRADE_ENABLED", "1")
    assert _rewrap(client, token).status_code == 200
    monkeypatch.setenv("KEY_UPGRADE_ENABLED", "0")
    again = client.post(
        "/auth/key/rewrap",
        json={
            "current_password": PASSWORD,
            "expected_wrapped_key": NEW["wrapped_key"],
            "data_key": {**NEW, "wrapped_key": "newer-wrap-" + "z" * 40},
        },
        headers=bearer(token),
    )
    assert again.status_code == 403
    assert system_scalar("SELECT wrapped_key FROM users") == NEW["wrapped_key"]


def test_a_refusal_is_logged_without_values(client, caplog):
    import logging

    token = _with_key(client)
    with caplog.at_level(logging.INFO):
        _rewrap(client, token, password="secret-guess-xyz")
    assert "data_key_rewrap_refused" in caplog.text
    assert "disabled" in caplog.text
    assert "secret-guess-xyz" not in caplog.text
    assert OLD["wrapped_key"] not in caplog.text


def test_the_deploy_config_does_not_turn_it_on():
    """render.yaml must not set the switch: it is an explicit, approved change."""
    from pathlib import Path

    config = (Path(__file__).resolve().parents[2] / "render.yaml").read_text()
    assert "KEY_UPGRADE_ENABLED" not in config
