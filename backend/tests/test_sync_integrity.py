"""Data integrity scenarios for POST /sync across devices, retries and failures.

Tests marked ``xfail(strict=True)`` reproduce defects found in the backend
audit (BACKEND_AUDIT.md). They are expected to fail until the fix lands; a
strict xfail turns into a failure the moment the behaviour changes, so the
marker has to be removed together with the fix.
"""

import threading
import time
from datetime import timedelta

import pytest

from conftest import T0, at, bearer, deleted_ids, ids, sync, sync_payload, system_scalar


def _expense(client_id, *, minutes=0, amount="1000", source_id=None, **extra):
    row = {
        "client_id": client_id,
        "type": "expense",
        "amount": amount,
        "category": "enc1:category",
        "occurred_at": at(minutes),
        "updated_at": at(minutes),
        **extra,
    }
    if source_id is not None:
        row["source_id"] = source_id
    return row


def _count(table: str) -> int:
    return system_scalar(f"SELECT count(*) FROM {table}")


# --- New account, second device, restart ------------------------------------


def test_new_user_uploads_and_a_second_device_receives_everything(client, alice):
    """Register, push an offline ledger, then a fresh device pulls it all."""
    sync(
        client,
        alice,
        transactions=[_expense(f"tx-{n}", minutes=n) for n in range(25)],
        savings_goals=[
            {"client_id": "g1", "name": "enc1:goal", "target_amount": "5000", "updated_at": at()}
        ],
        savings_transfers=[
            {
                "client_id": "tr1",
                "goal_client_id": "g1",
                "amount": "100",
                "kind": "manual",
                "occurred_at": at(1),
                "updated_at": at(1),
            }
        ],
    )

    # A second device signs in to the same account with no local state.
    login = client.post(
        "/auth/login", json={"email": "alice@example.com", "password": "correct horse 1"}
    )
    other_device = login.json()["access_token"]
    pulled = sync(client, other_device)

    assert sorted(ids(pulled["transactions"])) == sorted(f"tx-{n}" for n in range(25))
    assert ids(pulled["savings_goals"]) == ["g1"]
    assert pulled["savings_transfers"]["upserts"][0]["goal_client_id"] == "g1"


def test_a_restarted_device_resumes_from_its_saved_cursor(client, alice):
    """After a restart the app sends its stored server_time; nothing is lost."""
    first = sync(client, alice, transactions=[_expense("a")])
    cursor = first["server_time"]
    # Another device writes while this one is closed.
    sync(client, alice, transactions=[_expense("b", minutes=5)])

    resumed = sync(client, alice, last_sync_at=cursor)
    assert "b" in ids(resumed["transactions"])


# --- Retries, interruptions, partial failures --------------------------------


def test_a_retried_push_after_a_lost_reply_stores_each_row_once(client, alice):
    """The reply was lost (timeout), so the app pushes the same rows again."""
    rows = [_expense(f"tx-{n}", minutes=n) for n in range(10)]
    for _ in range(3):
        sync(client, alice, transactions=rows)
    assert _count("transactions") == 10


def test_a_failing_row_rolls_back_the_whole_push(client, alice):
    """Partial failure: one bad row means nothing from that push is stored."""
    body = sync_payload(
        transactions=[_expense("good-1"), {"client_id": "bad", "type": "expense", "amount": "-5"}],
        savings_goals=[
            {"client_id": "g1", "name": "enc1:goal", "target_amount": "5000", "updated_at": at()}
        ],
    )
    response = client.post("/sync", json=body, headers=bearer(alice))
    assert response.status_code == 422
    assert _count("transactions") == 0
    assert _count("savings_goals") == 0


def test_a_database_error_mid_push_rolls_back_and_hides_details(client, alice, monkeypatch):
    """An unexpected failure half-way leaves no partial rows and leaks no SQL."""
    import routers.sync as sync_router

    calls = {"n": 0}
    original = sync_router._apply_transaction

    def flaky(db, user_id, data):
        calls["n"] += 1
        if calls["n"] == 3:
            raise RuntimeError("connection reset by peer (internal detail)")
        return original(db, user_id, data)

    monkeypatch.setattr(sync_router, "_apply_transaction", flaky)
    body = sync_payload(transactions=[_expense(f"tx-{n}", minutes=n) for n in range(5)])
    response = client.post("/sync", json=body, headers=bearer(alice))

    assert response.status_code >= 400
    assert "internal detail" not in response.text
    assert _count("transactions") == 0


def test_concurrent_pushes_of_the_same_rows_do_not_duplicate(client, alice):
    """Two requests from one device race (double tap, retry while in flight)."""
    rows = [_expense(f"tx-{n}", minutes=n) for n in range(20)]
    statuses = []

    def push():
        response = client.post("/sync", json=sync_payload(transactions=rows), headers=bearer(alice))
        statuses.append(response.status_code)

    threads = [threading.Thread(target=push) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    # A loser may be refused (and retried by the app), never duplicated.
    assert 200 in statuses
    assert _count("transactions") == 20
    # The retry of a refused push succeeds.
    sync(client, alice, transactions=rows)
    assert _count("transactions") == 20


# --- Offline deletes and multi-device edits ----------------------------------


def test_a_delete_made_offline_reaches_the_other_device(client, alice):
    sync(client, alice, transactions=[_expense("tx")])
    cursor = sync(client, alice)["server_time"]

    # Device A deletes while offline and syncs later.
    sync(client, alice, deletes={"transactions": [{"client_id": "tx", "deleted_at": at(10)}]})

    pulled = sync(client, alice, last_sync_at=cursor)
    assert deleted_ids(pulled["transactions"]) == ["tx"]


def test_simultaneous_edits_keep_the_later_edit(client, alice):
    sync(client, alice, transactions=[_expense("tx", amount="100")])
    # Two devices edit the same row offline; B's edit is later but arrives first.
    sync(client, alice, transactions=[_expense("tx", amount="300", updated_at=at(20))])
    sync(client, alice, transactions=[_expense("tx", amount="200", updated_at=at(10))])

    row = sync(client, alice)["transactions"]["upserts"][0]
    assert row["amount"] == "300.00"


# --- Defects found in the audit ----------------------------------------------


@pytest.mark.xfail(strict=True, reason="AUDIT S-1: duplicate source_id blocks sync")
def test_two_devices_posting_the_same_recurring_charge_both_keep_syncing(client, alice):
    """Both phones post the same due recurring charge offline (same source_id,
    different random client ids). The second phone must still be able to sync,
    and the account must end with one charge, not two."""
    source = "recurring:r1:202503011200"
    sync(client, alice, transactions=[_expense("phone-a-tx", source_id=source)])

    body = sync_payload(transactions=[_expense("phone-b-tx", source_id=source)])
    response = client.post("/sync", json=body, headers=bearer(alice))

    assert response.status_code == 200, response.text
    live = system_scalar(
        "SELECT count(*) FROM transactions WHERE source_id = :s AND deleted_at IS NULL",
        s=source,
    )
    assert live == 1


@pytest.mark.xfail(strict=True, reason="AUDIT S-1: a deleted row keeps its source_id unique")
def test_reposting_a_charge_after_undoing_it_still_syncs(client, alice):
    """Undo a recurring charge (tombstone), then confirm it again: the app
    posts a new row with the same source_id and a new client id."""
    source = "recurring:r1:202503011200"
    sync(client, alice, transactions=[_expense("first", source_id=source)])
    sync(client, alice, deletes={"transactions": [{"client_id": "first", "deleted_at": at(5)}]})

    body = sync_payload(transactions=[_expense("second", minutes=10, source_id=source)])
    response = client.post("/sync", json=body, headers=bearer(alice))
    assert response.status_code == 200, response.text


@pytest.mark.xfail(strict=True, reason="AUDIT S-2: a future client clock wins forever")
def test_a_device_with_a_clock_years_ahead_cannot_freeze_a_row(client, alice):
    """A phone whose clock is set to 2099 edits a row. A later real edit or
    delete from a correct phone must still be able to change it."""
    sync(client, alice, transactions=[_expense("tx", amount="100", updated_at="2099-01-01T00:00:00+00:00")])
    sync(
        client,
        alice,
        deletes={"transactions": [{"client_id": "tx", "deleted_at": (T0 + timedelta(days=1)).isoformat()}]},
    )
    pulled = sync(client, alice)
    assert ids(pulled["transactions"]) == []


def test_first_sync_of_a_large_ledger_finishes_within_the_app_timeout(client, alice):
    """The app waits 75 s for a Render host. Measures a 3,000-row first sync
    locally (fast disk, no network); Render free is far slower, so the
    budget here is a small fraction of the app's timeout."""
    rows = [_expense(f"tx-{n}", minutes=n) for n in range(3000)]
    started = time.monotonic()
    sync(client, alice, transactions=rows)
    elapsed = time.monotonic() - started
    print(f"\n3000-row first sync took {elapsed:.2f}s")
    assert _count("transactions") == 3000
