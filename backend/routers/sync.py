"""POST /sync: two-way sync of every collection and the settings object.

The app pushes rows changed since its last sync and tombstones for rows it
deleted; the reply holds every row changed on the server since
``last_sync_at``, plus the full settings. Rows match by (user, client_id)
and the newer ``updated_at`` wins. See backend/README.md for the rules.
"""

import logging
import re
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import ValidationError
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.exc import TimeoutError as SQLAlchemyTimeoutError
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from auth import get_current_user
from crud_utils import (
    apply_frequency,
    as_utc,
    as_utc_or_now,
    direction_from_kind,
    empty_to_none,
    normalize_currency,
    normalize_enabled_currencies,
    normalize_income_overrides,
    period_from_unit,
    unit_from_period,
    utc_now,
)
from database import get_db, scrub_private_text
from legacy_photo import photo_meta
from safe_errors import log_error
from category_model import ExpenseCategory
from goal_model import SavingsGoal, SavingsTransfer
from models import Notification, User, UserSettings
from preset_model import ExpensePreset
from shopping_model import ShoppingItem, ShoppingList
from sync_schemas import (
    CategorySyncIn,
    GoalSyncIn,
    NotificationSyncIn,
    PresetSyncIn,
    RecurringSyncIn,
    SettingsSyncIn,
    SettingsSyncOut,
    ShoppingItemSyncIn,
    ShoppingListSyncIn,
    SyncCollectionOut,
    SyncRequest,
    SyncResponse,
    TombstoneIn,
    TransactionSyncIn,
    TransferSyncIn,
)
from transaction_model import RecurringExpense, Transaction

router = APIRouter(tags=["sync"])
logger = logging.getLogger("waffr.sync")


# Device clocks can be wrong. A stamp later than the server's clock by more
# than this is stored as this far ahead, so one phone set to the wrong year
# cannot win every later conflict. A stamp stored that far ahead before this
# rule existed loses to any change.
CLOCK_SKEW = timedelta(minutes=5)

# Rows looked up per query when a push names many client ids.
_LOOKUP_CHUNK = 1000

# Postgres advisory lock class for "a sync of this user is running".
SYNC_LOCK_CLASS = 7461


def _newer_or_equal(
    incoming: datetime | None,
    current: datetime | None,
    cap: datetime | None = None,
) -> bool:
    if incoming is None:
        return current is None
    if current is None:
        return True
    incoming_utc = as_utc(incoming)
    current_utc = as_utc(current)
    if cap is not None:
        # A stored stamp past the cap came from a wrong clock before stamps
        # were capped; it loses to any real change.
        if current_utc > cap:
            return True
        incoming_utc = min(incoming_utc, cap)
    return incoming_utc >= current_utc


def _parse_many(model, items: list[dict]):
    parsed = []
    for index, item in enumerate(items):
        try:
            parsed.append(model.model_validate(item))
        except ValidationError as error:
            # Where and why, never the rejected values (private text, amounts).
            raise HTTPException(
                status_code=422,
                detail=[
                    {
                        "type": problem.get("type"),
                        "loc": [model.__name__, index, *problem.get("loc", ())],
                        "msg": problem.get("msg"),
                    }
                    for problem in error.errors()
                ],
            ) from error
        except Exception as error:
            raise HTTPException(status_code=422, detail="Invalid row") from error
    return parsed


class _Push:
    """One push: its clock, and the user's rows it touches, by client id.

    Rows are looked up per collection in a few queries up front instead of
    one query (and one flush) per pushed row.
    """

    def __init__(self, db: Session, user_id: int):
        self.db = db
        self.user_id = user_id
        self.now = utc_now()
        self.cap = self.now + CLOCK_SKEW
        self._rows: dict[type, dict[str, object]] = {}
        # Transactions with a source id that this push wrote, in push order,
        # with the stamp the device sent; and the live holder of each source
        # id before the push.
        self.sourced: list[tuple[Transaction, datetime]] = []
        self.source_holders: dict[str, Transaction] = {}

    def stamp(self, value: datetime | None) -> datetime:
        """A device stamp in UTC, no later than the server clock plus skew."""
        return min(as_utc_or_now(value), self.cap)

    def load(self, model, client_ids) -> None:
        """Fetch the user's rows of [model] for [client_ids] not yet known."""
        cache = self._rows.setdefault(model, {})
        wanted = sorted({cid for cid in client_ids if cid and cid not in cache})
        for start in range(0, len(wanted), _LOOKUP_CHUNK):
            chunk = wanted[start : start + _LOOKUP_CHUNK]
            for row in self.db.query(model).filter(
                model.user_id == self.user_id,
                model.client_id.in_(chunk),
            ):
                cache[row.client_id] = row

    def get(self, model, client_id: str):
        return self._rows.setdefault(model, {}).get(client_id)

    def add(self, model, row) -> None:
        self.db.add(row)
        self._rows.setdefault(model, {})[row.client_id] = row

    def load_source_holders(self, sources) -> None:
        wanted = sorted({source for source in sources if source})
        cache = self._rows.setdefault(Transaction, {})
        for start in range(0, len(wanted), _LOOKUP_CHUNK):
            chunk = wanted[start : start + _LOOKUP_CHUNK]
            for row in self.db.query(Transaction).filter(
                Transaction.user_id == self.user_id,
                Transaction.source_id.in_(chunk),
                Transaction.deleted_at.is_(None),
            ):
                self.source_holders[row.source_id] = row
                cache.setdefault(row.client_id, row)


def _apply_delete(row, deleted_at: datetime | None, push: _Push) -> None:
    stamp = push.stamp(deleted_at)
    if row.deleted_at is not None and not _newer_or_equal(stamp, row.deleted_at, push.cap):
        return
    if hasattr(row, "updated_at") and not _newer_or_equal(stamp, row.updated_at, push.cap):
        return
    row.deleted_at = stamp
    if hasattr(row, "updated_at"):
        row.updated_at = stamp
    scrub_private_text(row)


# A row written by a sync that started before another device's pull but
# committed after it carries a stamp just under that pull's server_time; the
# overlap sends such rows again on the next pull instead of losing them.
# Re-sent rows merge as no-ops (last write wins on updated_at).
PULL_OVERLAP = timedelta(minutes=2)


def _changed_since(query, model, last_sync: datetime | None):
    """Rows the server changed after last_sync, by its own clock.

    Filtering on the app-sent updated_at / deleted_at would miss an old
    offline edit pushed after the other device's last sync.
    """
    if last_sync is None:
        return query
    return query.filter(model.changed_at > last_sync - PULL_OVERLAP)


def _settings_row(db: Session, user: User) -> tuple[UserSettings, bool]:
    existing = db.query(UserSettings).filter(UserSettings.user_id == user.id).first()
    if existing is not None:
        return existing, False
    row = UserSettings(user_id=user.id, processed_period_keys=[])
    db.add(row)
    db.flush()
    return row, True


def _keep_event_time(current: datetime | None, incoming: datetime | None) -> datetime:
    """Keep the client's event time. Server receipt time is not a substitute."""
    parsed = as_utc(incoming)
    if parsed is not None:
        return parsed
    if current is not None:
        return current
    return utc_now()


def _apply_settings(
    row: UserSettings,
    user: User,
    data: SettingsSyncIn,
    *,
    created: bool = False,
    cap: datetime | None = None,
) -> None:
    incoming = as_utc(data.updated_at)
    if incoming is not None and cap is not None:
        incoming = min(incoming, cap)
    # The streak merges by calendar day, not by the settings timestamp, so a
    # device whose other settings are older still records today's open.
    _merge_streak(row, data)
    if (
        not created
        and incoming is not None
        and not _newer_or_equal(incoming, row.updated_at, cap)
    ):
        keys = set(row.processed_period_keys or [])
        keys.update(data.processed_period_keys or [])
        row.processed_period_keys = sorted(keys)
        # Write the stored stamp back as it is. Otherwise the column's
        # onupdate moves it to the server's clock whenever the keys or the
        # streak changed, and a newer edit pushed later looks stale.
        flag_modified(row, "updated_at")
        return

    if data.notifications_muted is not None:
        row.notifications_enabled = not data.notifications_muted
    if data.notifications_enabled is not None:
        row.notifications_enabled = data.notifications_enabled
    for field in (
        "notify_low_balance",
        "notify_spending_threshold",
        "notify_goal_reached",
        "notify_recurring_expense",
        "ai_data_enabled",
        "dark_mode",
    ):
        value = getattr(data, field)
        if value is not None:
            setattr(row, field, value)
    for field in ("gender", "birthdate"):
        value = getattr(data, field)
        if value is None:
            continue
        cleaned = value.strip() or None
        setattr(row, field, cleaned)
        setattr(user, field, cleaned)
    for field in ("country", "city", "street", "phone"):
        value = getattr(data, field)
        if value is None:
            continue
        setattr(user, field, value.strip() or None)
    if data.hidden_categories is not None:
        row.hidden_categories = _clean_labels(data.hidden_categories)
    # Null is meaningful: the user removed the configured income.
    for field in ("monthly_income_amount", "weekly_income_amount"):
        if field in data.model_fields_set:
            setattr(row, field, getattr(data, field))
    if "income_overrides_by_currency" in data.model_fields_set:
        row.income_overrides_by_currency = normalize_income_overrides(
            data.income_overrides_by_currency
        )
    if "enabled_currencies" in data.model_fields_set:
        row.enabled_currencies = normalize_enabled_currencies(data.enabled_currencies)
    if "active_currency" in data.model_fields_set:
        active = normalize_currency(data.active_currency)
        enabled = list(row.enabled_currencies or ["SYP"])
        row.active_currency = active if active in enabled else "SYP"
    if data.display_name is not None:
        name = data.display_name.strip()
        user.name = name or None
    keys = set(row.processed_period_keys or [])
    keys.update(data.processed_period_keys or [])
    row.processed_period_keys = sorted(keys)
    if incoming is not None:
        row.updated_at = incoming


_DAY_KEY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _merge_streak(row: UserSettings, data: SettingsSyncIn) -> None:
    """Keep the streak with the later last day; same day keeps the longer one.

    ``usage_started_at`` keeps the earliest value seen. Mirrors
    ``StreakMath.merge`` in the app.
    """
    started = (data.usage_started_at or "").strip()
    if started:
        current = (row.usage_started_at or "").strip()
        parsed = as_utc(_parse_iso(started))
        if not current:
            row.usage_started_at = started
        elif parsed is not None:
            existing = as_utc(_parse_iso(current))
            if existing is None or parsed < existing:
                row.usage_started_at = started

    day = (data.streak_last_date or "").strip()
    if data.streak_count is None or not _DAY_KEY_RE.match(day):
        return
    count = max(int(data.streak_count), 0)
    current_day = (row.streak_last_date or "").strip()
    if not _DAY_KEY_RE.match(current_day) or day > current_day:
        row.streak_last_date = day
        row.streak_count = count
    elif day == current_day:
        row.streak_count = max(count, row.streak_count or 0)


def _parse_iso(value: str) -> datetime | None:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _clean_labels(raw: list[str]) -> list[str]:
    labels: list[str] = []
    for item in raw[:50]:
        label = (item or "").strip()[:40]
        if label and label not in labels:
            labels.append(label)
    return labels


def _settings_out(row: UserSettings, user: User) -> SettingsSyncOut:
    return SettingsSyncOut(
        notifications_enabled=row.notifications_enabled,
        notifications_muted=not row.notifications_enabled,
        notify_low_balance=row.notify_low_balance,
        notify_spending_threshold=row.notify_spending_threshold,
        notify_goal_reached=row.notify_goal_reached,
        notify_recurring_expense=row.notify_recurring_expense,
        ai_data_enabled=row.ai_data_enabled,
        monthly_income_amount=row.monthly_income_amount,
        weekly_income_amount=row.weekly_income_amount,
        income_overrides_by_currency=dict(row.income_overrides_by_currency or {}),
        enabled_currencies=list(row.enabled_currencies or ["SYP"]),
        active_currency=row.active_currency or "SYP",
        processed_period_keys=list(row.processed_period_keys or []),
        display_name=user.name,
        gender=user.gender or row.gender,
        birthdate=user.birthdate or row.birthdate,
        country=user.country,
        city=user.city,
        street=user.street,
        phone=user.phone,
        dark_mode=row.dark_mode,
        usage_started_at=row.usage_started_at,
        streak_count=row.streak_count,
        streak_last_date=row.streak_last_date,
        hidden_categories=list(row.hidden_categories or []),
        **photo_meta(),
        updated_at=row.updated_at,
    )


def _apply_transaction(push: _Push, data: TransactionSyncIn) -> None:
    row = push.get(Transaction, data.client_id)
    sent = as_utc_or_now(data.updated_at or data.occurred_at)
    incoming = push.stamp(sent)
    frequency, is_recurring, recurring_period = apply_frequency(data.frequency)
    if row is None:
        row = Transaction(user_id=push.user_id, client_id=data.client_id)
        push.add(Transaction, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    row.type = data.type
    row.amount = data.amount
    row.currency_code = normalize_currency(data.currency_code)
    row.category = empty_to_none(data.category)
    row.payment_method = empty_to_none(data.payment_method)
    row.note = empty_to_none(data.note)
    row.source_id = empty_to_none(data.source_id)
    row.occurred_at = _keep_event_time(row.occurred_at, data.occurred_at)
    row.frequency = frequency
    row.period_key = empty_to_none(data.period_key)
    row.is_recurring = is_recurring
    row.recurring_period = recurring_period
    row.deleted_at = None
    row.updated_at = incoming
    if row.source_id is not None:
        push.sourced.append((row, sent))


def _dedupe_sources(push: _Push) -> list[Transaction]:
    """One live transaction per source id; returns the rows turned into tombstones.

    Generated entries (a recurring charge, a shopping purchase) carry a
    source id that every device derives the same way, but each device gives
    its copy a random client id. The copy the server already had stays (or,
    for a new source, the first one in this push); later copies become
    tombstones, so the device that sent one drops it at its next pull and
    the charge is counted once everywhere.
    """
    keep: dict[str, Transaction] = {}
    for source, holder in push.source_holders.items():
        if holder.deleted_at is None and holder.source_id == source:
            keep[source] = holder
    dropped: list[Transaction] = []
    for row, sent in push.sourced:
        if row.deleted_at is not None or row.source_id is None:
            continue
        winner = keep.setdefault(row.source_id, row)
        if winner is row:
            continue
        # The device's own (unclamped) stamp, so its copy is never newer
        # than this tombstone and is removed on the device.
        stamp = max(row.updated_at, sent)
        row.deleted_at = stamp
        row.updated_at = stamp
        scrub_private_text(row)
        dropped.append(row)
    return dropped


def _apply_goal(push: _Push, data: GoalSyncIn) -> None:
    row = push.get(SavingsGoal, data.client_id)
    incoming = push.stamp(data.updated_at or data.created_at)
    if row is None:
        row = SavingsGoal(user_id=push.user_id, client_id=data.client_id)
        push.add(SavingsGoal, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    row.name = data.name
    row.currency_code = normalize_currency(data.currency_code)
    row.target_amount = data.target_amount
    row.duration = data.duration
    row.deadline = as_utc(data.deadline)
    row.allocate_percent = data.allocate_percent
    row.allocate_amount = data.allocate_amount
    row.deduct_frequency = data.deduct_frequency
    row.is_periodic = data.is_periodic
    row.duration_count = data.duration_count
    row.priority = data.priority
    row.completed_at = as_utc(data.completed_at)
    row.completed_amount = data.completed_amount
    row.is_completed = row.completed_at is not None
    if data.created_at is not None:
        row.created_at = as_utc_or_now(data.created_at)
    row.deleted_at = None
    row.updated_at = incoming


def _apply_transfer(push: _Push, data: TransferSyncIn) -> None:
    row = push.get(SavingsTransfer, data.client_id)
    incoming = push.stamp(data.updated_at or data.occurred_at)
    goal = None
    goal_client_id = empty_to_none(data.goal_client_id)
    if goal_client_id is not None:
        goal = push.get(SavingsGoal, goal_client_id)
    if row is None:
        row = SavingsTransfer(user_id=push.user_id, client_id=data.client_id)
        push.add(SavingsTransfer, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    row.goal_id = None if goal is None else goal.id
    row.amount = data.amount
    row.currency_code = normalize_currency(data.currency_code)
    row.direction = direction_from_kind(data.kind, data.direction)
    row.kind = data.kind
    row.note = empty_to_none(data.note)
    row.occurred_at = _keep_event_time(row.occurred_at, data.occurred_at)
    row.processed_period_key = empty_to_none(data.processed_period_key)
    row.deleted_at = None
    row.updated_at = incoming


def _apply_list(push: _Push, data: ShoppingListSyncIn) -> None:
    row = push.get(ShoppingList, data.client_id)
    incoming = push.stamp(data.updated_at)
    if row is None:
        row = ShoppingList(user_id=push.user_id, client_id=data.client_id)
        push.add(ShoppingList, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    row.name = data.name
    row.deleted_at = None
    row.updated_at = incoming


def _ensure_lists(push: _Push, items: list[ShoppingItemSyncIn]) -> bool:
    """Create the lists that items name but nobody pushed. True when any was."""
    created = False
    for data in items:
        if push.get(ShoppingList, data.list_client_id) is not None:
            continue
        push.add(
            ShoppingList,
            ShoppingList(
                user_id=push.user_id,
                client_id=data.list_client_id,
                name="المشتريات",
            ),
        )
        created = True
    return created


def _apply_item(push: _Push, data: ShoppingItemSyncIn) -> None:
    shopping_list = push.get(ShoppingList, data.list_client_id)
    row = push.get(ShoppingItem, data.client_id)
    incoming = push.stamp(data.updated_at or data.created_at)
    if row is None:
        row = ShoppingItem(user_id=push.user_id, client_id=data.client_id)
        push.add(ShoppingItem, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    row.list_id = shopping_list.id
    row.name = data.name
    row.quantity = max(1, data.quantity)
    row.price = data.price
    row.is_purchased = data.is_purchased
    row.purchased_at = as_utc(data.purchased_at)
    row.expense_client_id = empty_to_none(data.expense_client_id)
    if data.created_at is not None:
        row.created_at = as_utc_or_now(data.created_at)
    row.deleted_at = None
    row.updated_at = incoming


def _apply_recurring(push: _Push, data: RecurringSyncIn) -> None:
    row = push.get(RecurringExpense, data.client_id)
    incoming = push.stamp(data.updated_at or data.created_at)
    if row is None:
        row = RecurringExpense(user_id=push.user_id, client_id=data.client_id)
        push.add(RecurringExpense, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    row.amount = data.amount
    row.currency_code = normalize_currency(data.currency_code)
    row.category = data.category
    row.payment_method = data.payment_method
    row.note = empty_to_none(data.note)
    row.period = period_from_unit(data.unit)
    row.interval_count = max(1, data.interval_count)
    row.next_run_at = as_utc_or_now(data.next_due_at)
    row.is_active = data.enabled
    row.requires_confirmation = data.requires_confirmation
    row.remind_at = None if data.remind_at is None else as_utc_or_now(data.remind_at)
    row.remind_on_income = data.remind_on_income
    if data.created_at is not None:
        row.created_at = as_utc_or_now(data.created_at)
    row.deleted_at = None
    row.updated_at = incoming


def _apply_category(push: _Push, data: CategorySyncIn) -> None:
    row = push.get(ExpenseCategory, data.client_id)
    incoming = push.stamp(data.updated_at or data.created_at)
    if row is None:
        row = ExpenseCategory(user_id=push.user_id, client_id=data.client_id)
        push.add(ExpenseCategory, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    row.label = data.label.strip()
    row.icon_index = max(0, data.icon_index)
    row.deleted_at = None
    row.updated_at = incoming


def _apply_preset(push: _Push, data: PresetSyncIn) -> None:
    row = push.get(ExpensePreset, data.client_id)
    incoming = push.stamp(data.updated_at or data.created_at)
    if row is None:
        row = ExpensePreset(user_id=push.user_id, client_id=data.client_id)
        push.add(ExpensePreset, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    row.amount = data.amount
    row.multiplier = data.multiplier
    row.currency_code = normalize_currency(data.currency_code)
    row.category = data.category
    row.payment_method = data.payment_method
    row.note = empty_to_none(data.note)
    row.recurring = data.recurring
    row.unit = data.unit
    row.interval_count = data.interval_count
    if data.created_at is not None:
        row.created_at = as_utc_or_now(data.created_at)
    row.deleted_at = None
    row.updated_at = incoming


def _live_notifications_by_event(push: _Push, keys) -> dict[str, Notification]:
    wanted = sorted({key for key in keys if key is not None})
    found: dict[str, Notification] = {}
    cache = push._rows.setdefault(Notification, {})
    for start in range(0, len(wanted), _LOOKUP_CHUNK):
        chunk = wanted[start : start + _LOOKUP_CHUNK]
        for row in push.db.query(Notification).filter(
            Notification.user_id == push.user_id,
            Notification.event_key.in_(chunk),
            Notification.deleted_at.is_(None),
        ):
            found.setdefault(row.event_key, row)
            cache.setdefault(row.client_id, row)
    return found


def _apply_notification(
    push: _Push,
    data: NotificationSyncIn,
    by_event: dict[str, Notification],
) -> None:
    row = push.get(Notification, data.client_id)
    if row is None:
        candidate = by_event.get(data.event_key)
        if candidate is not None and candidate.deleted_at is None:
            row = candidate
    incoming = push.stamp(data.updated_at or data.created_at)
    if row is None:
        row = Notification(user_id=push.user_id, client_id=data.client_id)
        push.add(Notification, row)
    elif not _newer_or_equal(incoming, row.updated_at, push.cap):
        return
    if by_event.get(row.event_key) is row and row.event_key != data.event_key:
        by_event.pop(row.event_key, None)
    row.type = data.type
    row.title = data.title
    row.message = data.message
    row.event_key = data.event_key
    row.related_id = empty_to_none(data.related_id)
    row.event_metadata = data.metadata
    row.is_read = data.is_read
    if data.created_at is not None:
        row.created_at = as_utc_or_now(data.created_at)
    row.deleted_at = None
    row.updated_at = incoming
    by_event.setdefault(row.event_key, row)


def _apply_deletes(push: _Push, model, deletes: list[TombstoneIn]) -> None:
    for item in deletes:
        row = push.get(model, item.client_id)
        if row is None:
            continue
        _apply_delete(row, item.deleted_at, push)


def _collection_out(live_rows, tombstones, serialize) -> SyncCollectionOut:
    return SyncCollectionOut(
        upserts=[serialize(row) for row in live_rows],
        deletes=tombstones,
    )


@router.post("/sync", response_model=SyncResponse)
def sync_changes(
    payload: SyncRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Apply the pushed changes, then return what changed since last_sync_at.

    Upserts run parent first (goals and lists before the rows that point at
    them), then tombstones, then settings. Everything happens in one
    transaction: a bad row rolls the whole push back. Device stamps are
    capped at the server clock plus CLOCK_SKEW, and a generated entry that
    another device already posted (same source id) is kept once.
    """
    # Its rate limit runs in RateLimitMiddleware, before the body is read.
    user_id = current_user.id
    last_sync = as_utc(payload.last_sync_at)

    try:
        # One sync per account at a time, held until this transaction ends.
        # A second one (two taps, a retry while the first is still running)
        # would race the first on the same rows.
        locked = db.scalar(
            text("SELECT pg_try_advisory_xact_lock(:kind, :user_id)"),
            {"kind": SYNC_LOCK_CLASS, "user_id": user_id},
        )
        if not locked:
            raise HTTPException(
                status_code=409,
                detail="Sync already running",
                headers={"Retry-After": "5"},
            )

        goals_in = _parse_many(GoalSyncIn, payload.savings_goals.upserts)
        lists_in = _parse_many(ShoppingListSyncIn, payload.shopping_lists.upserts)
        transactions_in = _parse_many(TransactionSyncIn, payload.transactions.upserts)
        transfers_in = _parse_many(TransferSyncIn, payload.savings_transfers.upserts)
        items_in = _parse_many(ShoppingItemSyncIn, payload.shopping_items.upserts)
        recurring_in = _parse_many(RecurringSyncIn, payload.recurring_expenses.upserts)
        notifications_in = _parse_many(NotificationSyncIn, payload.notifications.upserts)
        categories_in = _parse_many(CategorySyncIn, payload.expense_categories.upserts)
        presets_in = _parse_many(PresetSyncIn, payload.expense_presets.upserts)

        push = _Push(db, user_id)

        def ids_of(rows, deletes):
            return [row.client_id for row in rows] + [item.client_id for item in deletes]

        # Every row this push names, a few queries per collection.
        push.load(
            SavingsGoal,
            ids_of(goals_in, payload.savings_goals.deletes)
            + [empty_to_none(row.goal_client_id) for row in transfers_in],
        )
        push.load(
            ShoppingList,
            ids_of(lists_in, payload.shopping_lists.deletes)
            + [row.list_client_id for row in items_in],
        )
        push.load(Transaction, ids_of(transactions_in, payload.transactions.deletes))
        push.load_source_holders(empty_to_none(row.source_id) for row in transactions_in)
        push.load(SavingsTransfer, ids_of(transfers_in, payload.savings_transfers.deletes))
        push.load(ShoppingItem, ids_of(items_in, payload.shopping_items.deletes))
        push.load(RecurringExpense, ids_of(recurring_in, payload.recurring_expenses.deletes))
        push.load(Notification, ids_of(notifications_in, payload.notifications.deletes))
        push.load(ExpenseCategory, ids_of(categories_in, payload.expense_categories.deletes))
        push.load(ExpensePreset, ids_of(presets_in, payload.expense_presets.deletes))
        by_event = _live_notifications_by_event(push, [row.event_key for row in notifications_in])

        # Upserts, parents first: goals and lists before the rows that point
        # at them. Parents get their ids in one flush.
        for item in goals_in:
            _apply_goal(push, item)
        for item in lists_in:
            _apply_list(push, item)
        _ensure_lists(push, items_in)
        db.flush()
        for item in transactions_in:
            _apply_transaction(push, item)
        for item in transfers_in:
            _apply_transfer(push, item)
        for item in items_in:
            _apply_item(push, item)
        for item in recurring_in:
            _apply_recurring(push, item)
        for item in notifications_in:
            _apply_notification(push, item, by_event)
        for item in categories_in:
            _apply_category(push, item)
        for item in presets_in:
            _apply_preset(push, item)

        # Tombstones, children first, so a list goes after its items.
        _apply_deletes(push, ShoppingItem, payload.shopping_items.deletes)
        _apply_deletes(push, SavingsTransfer, payload.savings_transfers.deletes)
        _apply_deletes(push, Transaction, payload.transactions.deletes)
        _apply_deletes(push, RecurringExpense, payload.recurring_expenses.deletes)
        _apply_deletes(push, Notification, payload.notifications.deletes)
        _apply_deletes(push, ExpenseCategory, payload.expense_categories.deletes)
        _apply_deletes(push, ExpensePreset, payload.expense_presets.deletes)
        _apply_deletes(push, SavingsGoal, payload.savings_goals.deletes)
        _apply_deletes(push, ShoppingList, payload.shopping_lists.deletes)

        # After the tombstones: a charge deleted and posted again in one push
        # keeps the new copy.
        _dedupe_sources(push)
        # Rows leaving a source id go out before rows taking it, so the
        # one-live-row-per-source index never sees two at once.
        leaving = [
            row
            for row in push._rows.get(Transaction, {}).values()
            if row.source_id is not None and row.deleted_at is not None
        ]
        if leaving:
            db.flush(leaving)

        # Settings: one row per user, created here if it is missing.
        settings, settings_created = _settings_row(db, current_user)
        if payload.settings is not None:
            _apply_settings(
                settings,
                current_user,
                payload.settings,
                created=settings_created,
                cap=push.cap,
            )

        # Reply: every row changed since last_sync_at, live rows and tombstones apart.
        db.flush()
        server_time = utc_now()

        def dump_changed(model, serialize_live):
            # populate_existing: rows written above go out as stored (amounts
            # rounded by the column), not as the Python values that were set.
            rows = _changed_since(
                db.query(model).populate_existing().filter(model.user_id == user_id),
                model,
                last_sync,
            ).all()
            live = [row for row in rows if row.deleted_at is None]
            deleted = [
                TombstoneIn(client_id=row.client_id, deleted_at=row.deleted_at)
                for row in rows
                if row.deleted_at is not None
            ]
            return _collection_out(live, deleted, serialize_live)

        # Lookups that turn foreign keys back into client ids.
        goals = {row.id: row for row in db.query(SavingsGoal).filter(SavingsGoal.user_id == user_id).all()}
        lists = {row.id: row for row in db.query(ShoppingList).filter(ShoppingList.user_id == user_id).all()}

        response = SyncResponse(
            server_time=server_time,
            transactions=dump_changed(
                Transaction,
                lambda row: {
                    "client_id": row.client_id,
                    "type": row.type,
                    "amount": str(row.amount),
                    "currency_code": row.currency_code,
                    "category": row.category,
                    "payment_method": row.payment_method,
                    "note": row.note,
                    "source_id": row.source_id,
                    "occurred_at": row.occurred_at,
                    "frequency": row.frequency,
                    "period_key": row.period_key,
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            savings_goals=dump_changed(
                SavingsGoal,
                lambda row: {
                    "client_id": row.client_id,
                    "name": row.name,
                    "currency_code": row.currency_code,
                    "target_amount": str(row.target_amount),
                    "duration": row.duration,
                    "deadline": row.deadline,
                    "allocate_percent": None if row.allocate_percent is None else str(row.allocate_percent),
                    "allocate_amount": None if row.allocate_amount is None else str(row.allocate_amount),
                    "deduct_frequency": row.deduct_frequency,
                    "is_periodic": row.is_periodic,
                    "duration_count": row.duration_count,
                    "priority": row.priority,
                    "completed_at": row.completed_at,
                    "completed_amount": None if row.completed_amount is None else str(row.completed_amount),
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            savings_transfers=dump_changed(
                SavingsTransfer,
                lambda row: {
                    "client_id": row.client_id,
                    "goal_client_id": None if row.goal_id is None else getattr(goals.get(row.goal_id), "client_id", None),
                    "amount": str(row.amount),
                    "currency_code": row.currency_code,
                    "direction": row.direction,
                    "kind": row.kind,
                    "note": row.note,
                    "occurred_at": row.occurred_at,
                    "processed_period_key": row.processed_period_key,
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            shopping_lists=dump_changed(
                ShoppingList,
                lambda row: {
                    "client_id": row.client_id,
                    "name": row.name,
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            shopping_items=dump_changed(
                ShoppingItem,
                lambda row: {
                    "client_id": row.client_id,
                    "list_client_id": getattr(lists.get(row.list_id), "client_id", "shopping_default"),
                    "name": row.name,
                    "quantity": row.quantity,
                    "price": None if row.price is None else str(row.price),
                    "is_purchased": row.is_purchased,
                    "purchased_at": row.purchased_at,
                    "expense_client_id": row.expense_client_id,
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            recurring_expenses=dump_changed(
                RecurringExpense,
                lambda row: {
                    "client_id": row.client_id,
                    "amount": str(row.amount),
                    "currency_code": row.currency_code,
                    "category": row.category,
                    "payment_method": row.payment_method,
                    "note": row.note,
                    "unit": unit_from_period(row.period),
                    "interval_count": row.interval_count,
                    "next_due_at": row.next_run_at,
                    "enabled": row.is_active,
                    "requires_confirmation": bool(row.requires_confirmation),
                    "remind_at": row.remind_at,
                    "remind_on_income": bool(row.remind_on_income),
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            notifications=dump_changed(
                Notification,
                lambda row: {
                    "client_id": row.client_id,
                    "type": row.type,
                    "title": row.title,
                    "message": row.message,
                    "event_key": row.event_key,
                    "related_id": row.related_id,
                    "metadata": row.event_metadata or {},
                    "is_read": row.is_read,
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            expense_categories=dump_changed(
                ExpenseCategory,
                lambda row: {
                    "client_id": row.client_id,
                    "label": row.label,
                    "icon_index": row.icon_index,
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            expense_presets=dump_changed(
                ExpensePreset,
                lambda row: {
                    "client_id": row.client_id,
                    "amount": str(row.amount),
                    "multiplier": row.multiplier,
                    "currency_code": row.currency_code,
                    "category": row.category,
                    "payment_method": row.payment_method,
                    "note": row.note,
                    "recurring": row.recurring,
                    "unit": row.unit,
                    "interval_count": row.interval_count,
                    "created_at": row.created_at,
                    "updated_at": row.updated_at,
                },
            ),
            settings=_settings_out(settings, current_user),
        )
        db.commit()
        return response
    except HTTPException:
        db.rollback()
        raise
    except IntegrityError as error:
        # A constraint refused a row, most likely another write racing this
        # one. Nothing was saved; the app retries the same push later.
        db.rollback()
        logger.warning("sync conflict for user %s: %s", user_id, type(error.orig).__name__)
        raise HTTPException(
            status_code=409,
            detail="Sync conflict, try again",
            headers={"Retry-After": "5"},
        ) from error
    except (OperationalError, SQLAlchemyTimeoutError) as error:
        # Database unreachable, too slow (statement timeout) or pool exhausted.
        db.rollback()
        logger.warning("sync unavailable for user %s: %s", user_id, type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable",
            headers={"Retry-After": "10"},
        ) from error
    except Exception as error:
        db.rollback()
        # The type and stack go to the log; the message can quote row values.
        log_error("sync failed for user %s", error, user_id)
        raise HTTPException(status_code=500, detail="Sync failed") from error
