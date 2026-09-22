"""Live tests for POST /sync. Requires the API on localhost:8000."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4

BASE = "http://127.0.0.1:8000"


def stamp(offset_seconds: int = 0) -> str:
    return (
        datetime.now(timezone.utc) + timedelta(seconds=offset_seconds)
    ).isoformat()


def collection(upserts=None, deletes=None):
    return {"upserts": upserts or [], "deletes": deletes or []}


def empty_payload(last_sync_at=None, **overrides):
    body = {
        "last_sync_at": last_sync_at,
        "transactions": collection(),
        "savings_goals": collection(),
        "savings_transfers": collection(),
        "shopping_lists": collection(),
        "shopping_items": collection(),
        "recurring_expenses": collection(),
        "notifications": collection(),
        "expense_categories": collection(),
        "settings": None,
    }
    body.update(overrides)
    return body


def request(method: str, path: str, token: str | None = None, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = Request(f"{BASE}{path}", data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=20) as response:
            raw = response.read().decode("utf-8")
            parsed = json.loads(raw) if raw else None
            return response.status, parsed
    except HTTPError as error:
        raw = error.read().decode("utf-8")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        return error.code, parsed


def register(email: str, password: str) -> str:
    status, payload = request(
        "POST",
        "/auth/register",
        body={"email": email, "password": password, "name": "Sync Tester"},
    )
    if status == 400:
        status, payload = request(
            "POST",
            "/auth/login",
            body={"email": email, "password": password},
        )
    if status != 200:
        raise RuntimeError(f"auth failed: {status} {payload}")
    return payload["access_token"]


def client_ids(rows: list[dict]) -> list[str]:
    return [row["client_id"] for row in rows]


def main() -> int:
    failures: list[str] = []

    def check(condition: bool, message: str) -> None:
        if condition:
            print(f"  PASS  {message}")
        else:
            print(f"  FAIL  {message}")
            failures.append(message)

    try:
        status, payload = request("GET", "/")
    except URLError as error:
        print(f"API is not reachable: {error}")
        return 1

    check(status == 200, "API is running")

    status, _ = request("POST", "/sync", body=empty_payload())
    check(status == 401, "missing JWT is rejected")

    status, _ = request(
        "POST",
        "/sync",
        token="not-a-real-token",
        body=empty_payload(),
    )
    check(status == 401, "invalid JWT is rejected")

    email_a = f"sync.a.{uuid4().hex[:8]}@example.com"
    email_b = f"sync.b.{uuid4().hex[:8]}@example.com"
    token_a = register(email_a, "PasswordA1!")
    token_b = register(email_b, "PasswordB1!")

    tx_id = f"tx_{uuid4().hex[:10]}"
    goal_id = f"g{uuid4().hex[:10]}"
    transfer_id = f"sv_{uuid4().hex[:10]}"
    item_id = f"sh_{uuid4().hex[:10]}"
    rec_id = f"r{uuid4().hex[:10]}"
    note_id = f"n{uuid4().hex[:10]}"
    cat_id = f"cat_{uuid4().hex[:10]}"
    now = stamp()

    status, first_body = request(
        "POST",
        "/sync",
        token=token_a,
        body=empty_payload(
            transactions=collection(
                [
                    {
                        "client_id": tx_id,
                        "type": "expense",
                        "amount": "12.50",
                        "category": "طعام",
                        "payment_method": "نقد",
                        "note": "offline expense",
                        "occurred_at": now,
                        "updated_at": now,
                    }
                ]
            ),
            savings_goals=collection(
                [
                    {
                        "client_id": goal_id,
                        "name": "هدف تجريبي",
                        "target_amount": "100.00",
                        "duration": "month",
                        "is_periodic": False,
                        "priority": 0,
                        "created_at": now,
                        "updated_at": now,
                    }
                ]
            ),
            savings_transfers=collection(
                [
                    {
                        "client_id": transfer_id,
                        "goal_client_id": goal_id,
                        "amount": "20.00",
                        "kind": "manual",
                        "direction": "to_savings",
                        "occurred_at": now,
                        "updated_at": now,
                    }
                ]
            ),
            shopping_lists=collection(
                [
                    {
                        "client_id": "shopping_default",
                        "name": "المشتريات",
                        "updated_at": now,
                    }
                ]
            ),
            shopping_items=collection(
                [
                    {
                        "client_id": item_id,
                        "list_client_id": "shopping_default",
                        "name": "حليب",
                        "is_purchased": False,
                        "created_at": now,
                        "updated_at": now,
                    }
                ]
            ),
            recurring_expenses=collection(
                [
                    {
                        "client_id": rec_id,
                        "amount": "9.00",
                        "category": "فواتير",
                        "payment_method": "بطاقة",
                        "unit": "month",
                        "interval_count": 1,
                        "next_due_at": now,
                        "enabled": True,
                        "created_at": now,
                        "updated_at": now,
                    }
                ]
            ),
            notifications=collection(
                [
                    {
                        "client_id": note_id,
                        "type": "goalReached",
                        "title": "تم الهدف",
                        "message": "وصلت",
                        "event_key": f"goalReached:{goal_id}",
                        "related_id": goal_id,
                        "is_read": False,
                        "created_at": now,
                        "updated_at": now,
                    }
                ]
            ),
            expense_categories=collection(
                [
                    {
                        "client_id": cat_id,
                        "label": "قهوة",
                        "icon_index": 2,
                        "updated_at": now,
                    }
                ]
            ),
            settings={
                "notifications_muted": True,
                "monthly_income_amount": "800.00",
                "processed_period_keys": ["leftover:m:2026-01"],
                "display_name": "Sync Tester",
                "gender": "male",
                "dark_mode": True,
                "updated_at": now,
            },
        ),
    )
    check(status == 200, "first sync uploads offline data")
    if status != 200 or not isinstance(first_body, dict):
        print(json.dumps(first_body, ensure_ascii=False, default=str)[:2000])
        print(f"{len(failures)} failed before payload checks")
        return 1
    server_time = first_body["server_time"]
    check(tx_id in client_ids(first_body["transactions"]["upserts"]), "transaction returned")
    check(goal_id in client_ids(first_body["savings_goals"]["upserts"]), "goal returned")
    check(
        transfer_id in client_ids(first_body["savings_transfers"]["upserts"]),
        "savings transfer returned",
    )
    check(item_id in client_ids(first_body["shopping_items"]["upserts"]), "shopping item returned")
    check(rec_id in client_ids(first_body["recurring_expenses"]["upserts"]), "recurring returned")
    check(note_id in client_ids(first_body["notifications"]["upserts"]), "notification returned")
    check(cat_id in client_ids(first_body["expense_categories"]["upserts"]), "category returned")
    check(first_body["settings"]["notifications_muted"] is True, "muted setting stored")
    check(first_body["settings"]["display_name"] == "Sync Tester", "display name stored")
    check(first_body["settings"]["gender"] == "male", "gender stored")
    check(first_body["settings"]["dark_mode"] is True, "dark mode stored")
    check(first_body["settings"]["has_photo"] is False, "no photo by default")
    check(
        "leftover:m:2026-01" in first_body["settings"]["processed_period_keys"],
        "processed period keys stored",
    )

    status, listed = request("GET", "/transactions", token=token_a)
    check(status == 200, "CRUD list still works after sync")
    check(len(listed) == 1, "CRUD sees exactly one uploaded transaction")

    status, repeated = request(
        "POST",
        "/sync",
        token=token_a,
        body=empty_payload(
            last_sync_at=server_time,
            transactions=collection(
                [
                    {
                        "client_id": tx_id,
                        "type": "expense",
                        "amount": "12.50",
                        "category": "طعام",
                        "occurred_at": now,
                        "updated_at": now,
                    }
                ]
            ),
        ),
    )
    check(status == 200, "repeat sync is accepted")
    status, listed_again = request("GET", "/transactions", token=token_a)
    check(len(listed_again) == 1, "repeat sync does not duplicate transactions")

    status, incremental = request(
        "POST",
        "/sync",
        token=token_a,
        body=empty_payload(last_sync_at=repeated["server_time"]),
    )
    check(status == 200, "incremental sync with no local changes")
    check(
        incremental["transactions"]["upserts"] == [],
        "incremental sync returns no old transactions",
    )

    later = stamp(5)
    status, update = request(
        "POST",
        "/sync",
        token=token_a,
        body=empty_payload(
            transactions=collection(
                [
                    {
                        "client_id": tx_id,
                        "type": "expense",
                        "amount": "18.00",
                        "category": "طعام",
                        "note": "updated",
                        "occurred_at": now,
                        "updated_at": later,
                    }
                ]
            ),
        ),
    )
    check(status == 200, "update sync")
    updated = next(row for row in update["transactions"]["upserts"] if row["client_id"] == tx_id)
    check(updated["amount"] == "18.00", "updated amount wins")

    older = stamp(-30)
    status, conflict = request(
        "POST",
        "/sync",
        token=token_a,
        body=empty_payload(
            transactions=collection(
                [
                    {
                        "client_id": tx_id,
                        "type": "expense",
                        "amount": "1.00",
                        "category": "قديم",
                        "occurred_at": now,
                        "updated_at": older,
                    }
                ]
            ),
        ),
    )
    check(status == 200, "older conflict payload accepted")
    status, after_conflict = request("GET", "/transactions", token=token_a)
    check(after_conflict[0]["amount"] == "18.00", "older update loses last-write-wins")

    delete_at = stamp(10)
    status, deleted = request(
        "POST",
        "/sync",
        token=token_a,
        body=empty_payload(
            last_sync_at=conflict["server_time"],
            transactions=collection(
                deletes=[{"client_id": tx_id, "deleted_at": delete_at}]
            ),
        ),
    )
    check(status == 200, "delete tombstone accepted")
    check(
        any(item["client_id"] == tx_id for item in deleted["transactions"]["deletes"]),
        "delete returned to client",
    )
    status, missing = request("GET", "/transactions", token=token_a)
    check(missing == [], "soft-deleted transaction hidden from CRUD")

    status, other = request(
        "POST",
        "/sync",
        token=token_b,
        body=empty_payload(last_sync_at=None),
    )
    check(status == 200, "second user can sync")
    check(
        other["transactions"]["upserts"] == [],
        "second user does not see first user records",
    )

    print()
    if failures:
        print(f"{len(failures)} failed")
        return 1
    print("all sync tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
