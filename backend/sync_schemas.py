from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_serializer, field_validator

from api_schemas import money_str, parse_decimal

# Private text arrives encrypted, which is longer than what the user typed.
PRIVATE_TEXT_MAX = 4000


class TombstoneIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    deleted_at: datetime | None = None


class TransactionSyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    type: str = Field(pattern="^(income|expense)$")
    amount: Decimal = Field(gt=0)
    category: str | None = None
    payment_method: str | None = None
    note: str | None = None
    source_id: str | None = None
    occurred_at: datetime | None = None
    frequency: str = Field(default="none", pattern="^(none|weekly|monthly)$")
    period_key: str | None = None
    currency_code: str | None = None
    updated_at: datetime | None = None

    @field_validator("amount", mode="before")
    @classmethod
    def _amount(cls, value):
        parsed = parse_decimal(value)
        if parsed is None:
            raise ValueError("amount is required")
        return parsed


class GoalSyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=PRIVATE_TEXT_MAX)
    target_amount: Decimal = Field(gt=0)
    duration: str = Field(default="month")
    deadline: datetime | None = None
    allocate_percent: Decimal | None = None
    allocate_amount: Decimal | None = None
    deduct_frequency: str = Field(default="monthly")
    is_periodic: bool = False
    duration_count: int | None = None
    priority: int = 0
    completed_at: datetime | None = None
    completed_amount: Decimal | None = None
    currency_code: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @field_validator(
        "target_amount",
        "allocate_percent",
        "allocate_amount",
        "completed_amount",
        mode="before",
    )
    @classmethod
    def _money(cls, value):
        return parse_decimal(value)


class TransferSyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    goal_client_id: str | None = None
    amount: Decimal = Field(gt=0)
    direction: str | None = Field(
        default=None,
        pattern="^(to_savings|to_balance)$",
    )
    kind: str | None = None
    note: str | None = None
    occurred_at: datetime | None = None
    processed_period_key: str | None = None
    currency_code: str | None = None
    updated_at: datetime | None = None

    @field_validator("amount", mode="before")
    @classmethod
    def _amount(cls, value):
        parsed = parse_decimal(value)
        if parsed is None:
            raise ValueError("amount is required")
        return parsed


class ShoppingListSyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=100)
    updated_at: datetime | None = None


class ShoppingItemSyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    list_client_id: str = Field(default="shopping_default", max_length=64)
    name: str = Field(min_length=1, max_length=PRIVATE_TEXT_MAX)
    quantity: int = 1
    price: Decimal | None = None
    is_purchased: bool = False
    purchased_at: datetime | None = None
    expense_client_id: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @field_validator("price", mode="before")
    @classmethod
    def _price(cls, value):
        return parse_decimal(value)


class RecurringSyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    amount: Decimal = Field(gt=0)
    category: str
    payment_method: str = ""
    note: str | None = None
    unit: str = "month"
    interval_count: int = 1
    next_due_at: datetime | None = None
    enabled: bool = True
    requires_confirmation: bool = False
    remind_at: datetime | None = None
    remind_on_income: bool = False
    currency_code: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @field_validator("amount", mode="before")
    @classmethod
    def _amount(cls, value):
        parsed = parse_decimal(value)
        if parsed is None:
            raise ValueError("amount is required")
        return parsed


class NotificationSyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    type: str
    title: str
    message: str
    event_key: str
    related_id: str | None = None
    metadata: dict[str, str] = Field(default_factory=dict)
    is_read: bool = False
    created_at: datetime | None = None
    updated_at: datetime | None = None


class CategorySyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    label: str = Field(min_length=1, max_length=PRIVATE_TEXT_MAX)
    icon_index: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None


class PresetSyncIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    amount: Decimal = Field(gt=0)
    multiplier: int = Field(default=1, ge=1, le=10)
    currency_code: str | None = None
    category: str = Field(min_length=1, max_length=PRIVATE_TEXT_MAX)
    payment_method: str = Field(default="", max_length=PRIVATE_TEXT_MAX)
    note: str | None = Field(default=None, max_length=PRIVATE_TEXT_MAX)
    recurring: bool = False
    unit: str = Field(default="month", pattern="^(day|week|month)$")
    interval_count: int = Field(default=1, ge=1, le=99)
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @field_validator("amount", mode="before")
    @classmethod
    def _amount(cls, value):
        parsed = parse_decimal(value)
        if parsed is None:
            raise ValueError("amount is required")
        return parsed


class SettingsSyncIn(BaseModel):
    notifications_muted: bool | None = None
    notifications_enabled: bool | None = None
    notify_low_balance: bool | None = None
    notify_spending_threshold: bool | None = None
    notify_goal_reached: bool | None = None
    notify_recurring_expense: bool | None = None
    ai_data_enabled: bool | None = None
    monthly_income_amount: Decimal | None = None
    weekly_income_amount: Decimal | None = None
    income_overrides_by_currency: dict | None = None
    enabled_currencies: list[str] | None = None
    active_currency: str | None = None
    processed_period_keys: list[str] | None = None
    display_name: str | None = Field(default=None, max_length=100)
    gender: str | None = Field(default=None, max_length=20)
    birthdate: str | None = Field(default=None, max_length=40)
    country: str | None = Field(default=None, max_length=80)
    city: str | None = Field(default=None, max_length=80)
    street: str | None = Field(default=None, max_length=160)
    phone: str | None = Field(default=None, max_length=32)
    dark_mode: bool | None = None
    usage_started_at: str | None = Field(default=None, max_length=40)
    streak_count: int | None = None
    streak_last_date: str | None = Field(default=None, max_length=10)
    hidden_categories: list[str] | None = None
    updated_at: datetime | None = None

    @field_validator("monthly_income_amount", "weekly_income_amount", mode="before")
    @classmethod
    def _money(cls, value):
        return parse_decimal(value)


class SyncCollectionIn(BaseModel):
    upserts: list[dict] = Field(default_factory=list)
    deletes: list[TombstoneIn] = Field(default_factory=list)


class SyncRequest(BaseModel):
    last_sync_at: datetime | None = None
    transactions: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    savings_goals: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    savings_transfers: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    shopping_lists: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    shopping_items: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    recurring_expenses: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    notifications: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    expense_categories: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    expense_presets: SyncCollectionIn = Field(default_factory=SyncCollectionIn)
    settings: SettingsSyncIn | None = None


class SettingsSyncOut(BaseModel):
    notifications_enabled: bool
    notifications_muted: bool
    notify_low_balance: bool
    notify_spending_threshold: bool
    notify_goal_reached: bool
    notify_recurring_expense: bool
    ai_data_enabled: bool
    monthly_income_amount: Decimal | None
    weekly_income_amount: Decimal | None
    income_overrides_by_currency: dict = Field(default_factory=dict)
    enabled_currencies: list[str] = Field(default_factory=lambda: ["SYP"])
    active_currency: str = "SYP"
    processed_period_keys: list[str]
    display_name: str | None = None
    gender: str | None = None
    birthdate: str | None = None
    country: str | None = None
    city: str | None = None
    street: str | None = None
    phone: str | None = None
    dark_mode: bool | None = None
    usage_started_at: str | None = None
    streak_count: int | None = None
    streak_last_date: str | None = None
    hidden_categories: list[str] = Field(default_factory=list)
    has_photo: bool = False
    photo_updated_at: datetime | None = None
    updated_at: datetime

    @field_serializer("monthly_income_amount", "weekly_income_amount")
    def _money(self, value: Decimal | None) -> str | None:
        return money_str(value)


class SyncCollectionOut(BaseModel):
    upserts: list[dict] = Field(default_factory=list)
    deletes: list[TombstoneIn] = Field(default_factory=list)


class SyncResponse(BaseModel):
    server_time: datetime
    transactions: SyncCollectionOut
    savings_goals: SyncCollectionOut
    savings_transfers: SyncCollectionOut
    shopping_lists: SyncCollectionOut
    shopping_items: SyncCollectionOut
    recurring_expenses: SyncCollectionOut
    notifications: SyncCollectionOut
    expense_categories: SyncCollectionOut
    expense_presets: SyncCollectionOut
    settings: SettingsSyncOut
