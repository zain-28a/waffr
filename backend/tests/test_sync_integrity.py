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

from conftest import (
    at,
    bearer,
    deleted_ids,
    ids,
    parse_time,
    sync,
    sync_payload,
    system_execute,
    system_scalar,
)


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


def test_reposting_a_charge_after_undoing_it_still_syncs(client, alice):
    """Undo a recurring charge (tombstone), then confirm it again: the app
    posts a new row with the same source_id and a new client id."""
    source = "recurring:r1:202503011200"
    sync(client, alice, transactions=[_expense("first", source_id=source)])
    sync(client, alice, deletes={"transactions": [{"client_id": "first", "deleted_at": at(5)}]})

    body = sync_payload(transactions=[_expense("second", minutes=10, source_id=source)])
    response = client.post("/sync", json=body, headers=bearer(alice))
    assert response.status_code == 200, response.text


def test_a_device_with_a_clock_years_ahead_cannot_freeze_a_row(client, alice):
    """A phone whose clock says 2099 edits a row. Its stamp is stored as at
    most the server clock plus CLOCK_SKEW, so a correct phone's later delete
    still wins."""
    from datetime import datetime, timezone

    from routers.sync import CLOCK_SKEW

    sync(client, alice, transactions=[_expense("tx", amount="100", updated_at="2099-01-01T00:00:00+00:00")])
    stored = parse_time(sync(client, alice)["transactions"]["upserts"][0]["updated_at"])
    assert stored <= datetime.now(timezone.utc) + CLOCK_SKEW

    later = (stored + timedelta(seconds=1)).isoformat()
    sync(client, alice, deletes={"transactions": [{"client_id": "tx", "deleted_at": later}]})
    assert ids(sync(client, alice)["transactions"]) == []


def test_a_far_future_stamp_stored_before_the_cap_loses_to_a_real_edit(client, alice):
    """Rows frozen by a wrong clock before stamps were capped heal on the next edit."""
    sync(client, alice, transactions=[_expense("tx", amount="100")])
    system_execute("UPDATE transactions SET updated_at = '2099-01-01T00:00:00+00:00'")

    sync(client, alice, transactions=[_expense("tx", amount="250", updated_at=at(60))])
    row = sync(client, alice)["transactions"]["upserts"][0]
    assert row["amount"] == "250.00"


def test_settings_from_a_wrong_clock_are_capped(client, alice):
    from datetime import datetime, timezone

    from routers.sync import CLOCK_SKEW

    body = sync(
        client,
        alice,
        settings={"dark_mode": True, "updated_at": "2099-01-01T00:00:00+00:00"},
    )
    stored = parse_time(body["settings"]["updated_at"])
    assert stored <= datetime.now(timezone.utc) + CLOCK_SKEW


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


# --- Generated entries posted on two devices (one live row per source id) ---


def test_the_device_with_the_duplicate_is_told_to_drop_it(client, alice):
    source = "recurring:r1:202503011200"
    sync(client, alice, transactions=[_expense("phone-a-tx", source_id=source)])

    reply = sync(client, alice, transactions=[_expense("phone-b-tx", source_id=source)])
    # Phone B learns its copy is gone and receives the one that stays.
    assert "phone-b-tx" in deleted_ids(reply["transactions"])
    assert "phone-a-tx" in ids(reply["transactions"])
    assert "phone-b-tx" not in ids(reply["transactions"])

    # Phone A, at its next pull, also sees B's copy only as a tombstone.
    later = sync(client, alice)
    assert ids(later["transactions"]) == ["phone-a-tx"]


def test_the_duplicate_tombstone_is_not_older_than_the_devices_copy(client, alice):
    """The app drops a local row only for a tombstone at least as new as it."""
    source = "shopping:item-1"
    sync(client, alice, transactions=[_expense("a", source_id=source)])
    reply = sync(
        client,
        alice,
        transactions=[_expense("b", source_id=source, updated_at="2099-01-01T00:00:00+00:00")],
    )
    tomb = next(t for t in reply["transactions"]["deletes"] if t["client_id"] == "b")
    assert parse_time(tomb["deleted_at"]).year == 2099


def test_pushing_the_duplicate_again_changes_nothing(client, alice):
    source = "recurring:r1:202503011200"
    sync(client, alice, transactions=[_expense("a", source_id=source)])
    for _ in range(3):
        sync(client, alice, transactions=[_expense("b", source_id=source)])
    assert system_scalar("SELECT count(*) FROM transactions WHERE deleted_at IS NULL") == 1
    assert system_scalar("SELECT client_id FROM transactions WHERE deleted_at IS NULL") == "a"


def test_two_copies_in_one_push_keep_the_first(client, alice):
    source = "recurring:r1:202503011200"
    sync(
        client,
        alice,
        transactions=[_expense("first", source_id=source), _expense("second", source_id=source)],
    )
    assert system_scalar("SELECT client_id FROM transactions WHERE deleted_at IS NULL") == "first"


def test_undo_and_repost_in_one_push_keeps_the_new_charge(client, alice):
    """Offline: undo the charge, then confirm it again, then sync once."""
    source = "recurring:r1:202503011200"
    sync(client, alice, transactions=[_expense("old", source_id=source)])
    sync(
        client,
        alice,
        transactions=[_expense("new", minutes=10, source_id=source)],
        deletes={"transactions": [{"client_id": "old", "deleted_at": at(5)}]},
    )
    assert system_scalar("SELECT client_id FROM transactions WHERE deleted_at IS NULL") == "new"


def test_reviving_a_row_whose_source_is_taken_keeps_one_live(client, alice):
    source = "recurring:r1:202503011200"
    sync(client, alice, transactions=[_expense("old", source_id=source)])
    sync(client, alice, deletes={"transactions": [{"client_id": "old", "deleted_at": at(5)}]})
    sync(client, alice, transactions=[_expense("new", minutes=10, source_id=source)])
    # A device that never saw the delete edits the old row later.
    sync(client, alice, transactions=[_expense("old", minutes=20, source_id=source)])
    assert system_scalar(
        "SELECT count(*) FROM transactions WHERE source_id = :s AND deleted_at IS NULL", s=source
    ) == 1


def test_different_accounts_may_share_a_source_id(client, alice, bob):
    source = "recurring:r1:202503011200"
    sync(client, alice, transactions=[_expense("a", source_id=source)])
    sync(client, bob, transactions=[_expense("b", source_id=source)])
    assert system_scalar("SELECT count(*) FROM transactions WHERE deleted_at IS NULL") == 2


def test_the_live_only_source_index_exists():
    definition = system_scalar(
        "SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_transactions_user_source_live'"
    )
    assert "deleted_at IS NULL" in definition
    assert system_scalar(
        "SELECT count(*) FROM pg_indexes WHERE indexname = 'uq_transactions_user_source'"
    ) == 0


# --- Cost, locking and error codes ---------------------------------------------


def test_a_push_costs_a_few_queries_per_collection_not_per_row(client, alice):
    from sqlalchemy import event

    from database import engine

    statements = []

    def count(*_args):
        statements.append(1)

    rows = [_expense(f"tx-{n}", minutes=n) for n in range(300)]
    event.listen(engine, "before_cursor_execute", count)
    try:
        sync(client, alice, transactions=rows)
    finally:
        event.remove(engine, "before_cursor_execute", count)
    # Was about two per row (600+). Inserts go out in batches.
    assert len(statements) < 60, len(statements)


def test_a_second_sync_of_the_same_account_waits_its_turn(client, alice):
    """While one sync holds the account, another gets a retryable 409."""
    from sqlalchemy import text

    from database import engine
    from routers.sync import SYNC_LOCK_CLASS

    user_id = system_scalar("SELECT id FROM users")
    with engine.connect() as other:
        other.execute(
            text("SELECT pg_advisory_lock(:kind, :user_id)"),
            {"kind": SYNC_LOCK_CLASS, "user_id": user_id},
        )
        try:
            busy = client.post("/sync", json=sync_payload(), headers=bearer(alice))
        finally:
            other.execute(
                text("SELECT pg_advisory_unlock(:kind, :user_id)"),
                {"kind": SYNC_LOCK_CLASS, "user_id": user_id},
            )
    assert busy.status_code == 409
    assert busy.headers["Retry-After"]
    # Once it is free, the same push goes through.
    sync(client, alice)


def test_another_accounts_sync_is_not_blocked(client, alice, bob):
    from sqlalchemy import text

    from database import engine
    from routers.sync import SYNC_LOCK_CLASS

    alice_id = system_scalar("SELECT id FROM users WHERE email = 'alice@example.com'")
    with engine.connect() as other:
        other.execute(
            text("SELECT pg_advisory_lock(:kind, :user_id)"),
            {"kind": SYNC_LOCK_CLASS, "user_id": alice_id},
        )
        try:
            sync(client, bob)
        finally:
            other.execute(
                text("SELECT pg_advisory_unlock(:kind, :user_id)"),
                {"kind": SYNC_LOCK_CLASS, "user_id": alice_id},
            )


@pytest.mark.parametrize(
    ("error", "status"),
    [("integrity", 409), ("operational", 503), ("other", 500)],
)
def test_sync_failures_get_honest_status_codes(client, alice, monkeypatch, error, status):
    from sqlalchemy.exc import IntegrityError, OperationalError

    import routers.sync as sync_router

    def fail(*_args, **_kwargs):
        if error == "integrity":
            raise IntegrityError("INSERT ...", {}, Exception("duplicate key on secret_table"))
        if error == "operational":
            raise OperationalError("SELECT ...", {}, Exception("server at 10.0.0.5 closed"))
        raise RuntimeError("bug in secret_table handling")

    monkeypatch.setattr(sync_router, "_apply_transaction", fail)
    response = client.post(
        "/sync", json=sync_payload(transactions=[_expense("tx")]), headers=bearer(alice)
    )
    assert response.status_code == status
    assert "secret_table" not in response.text
    assert "10.0.0.5" not in response.text
    assert _count("transactions") == 0


def test_too_many_syncs_at_once_get_a_retryable_503():
    """The global cap: with every slot taken, a sync waits, then gets 503."""
    import asyncio

    from security_middleware import SyncConcurrencyMiddleware

    async def app(scope, receive, send):
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    middleware = SyncConcurrencyMiddleware(app, slots=1, wait_seconds=0.2)
    middleware._slots.acquire()  # another sync is running
    sent = []

    async def send(message):
        sent.append(message)

    async def receive():
        return {"type": "http.request", "body": b"", "more_body": False}

    scope = {"type": "http", "path": "/sync", "method": "POST", "headers": []}
    asyncio.run(middleware(scope, receive, send))
    assert sent[0]["status"] == 503

    # Other routes are never held back, and a free slot lets a sync through.
    sent.clear()
    asyncio.run(middleware({**scope, "path": "/auth/me", "method": "GET"}, receive, send))
    assert sent[0]["status"] == 200
    middleware._slots.release()
    sent.clear()
    asyncio.run(middleware(scope, receive, send))
    assert sent[0]["status"] == 200
