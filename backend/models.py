from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import (
    MONEY,
    Base,
    ClientIdMixin,
    SoftDeleteMixin,
    TimestampMixin,
)


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # Account profile. Nullable so existing users keep working.
    # gender/birthdate are also mirrored on UserSettings for the current sync path.
    gender: Mapped[str | None] = mapped_column(String(20), nullable=True)
    birthdate: Mapped[str | None] = mapped_column(String(40), nullable=True)
    country: Mapped[str | None] = mapped_column(String(80), nullable=True)
    city: Mapped[str | None] = mapped_column(String(80), nullable=True)
    street: Mapped[str | None] = mapped_column(String(160), nullable=True)
    photo_updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    transactions: Mapped[list["Transaction"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    savings_goals: Mapped[list["SavingsGoal"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    savings_transfers: Mapped[list["SavingsTransfer"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    shopping_lists: Mapped[list["ShoppingList"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    recurring_expenses: Mapped[list["RecurringExpense"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    notifications: Mapped[list["Notification"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    expense_categories: Mapped[list["ExpenseCategory"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    settings: Mapped["UserSettings | None"] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        uselist=False,
    )


class UserSettings(TimestampMixin, Base):
    __tablename__ = "user_settings"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_user_settings_user"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    notifications_enabled: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_low_balance: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_spending_threshold: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_goal_reached: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_recurring_expense: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    ai_data_enabled: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
    )
    monthly_income_amount: Mapped[Decimal | None] = mapped_column(
        MONEY,
        nullable=True,
    )
    weekly_income_amount: Mapped[Decimal | None] = mapped_column(
        MONEY,
        nullable=True,
    )
    processed_period_keys: Mapped[list] = mapped_column(
        JSONB,
        default=list,
        nullable=False,
    )
    gender: Mapped[str | None] = mapped_column(String(20), nullable=True)
    birthdate: Mapped[str | None] = mapped_column(String(40), nullable=True)
    dark_mode: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    usage_started_at: Mapped[str | None] = mapped_column(String(40), nullable=True)
    streak_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    streak_last_date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    enabled_currencies: Mapped[list] = mapped_column(
        JSONB,
        default=lambda: ["SYP"],
        nullable=False,
    )
    active_currency: Mapped[str] = mapped_column(
        String(10),
        default="SYP",
        nullable=False,
    )
    income_overrides_by_currency: Mapped[dict] = mapped_column(
        JSONB,
        default=dict,
        nullable=False,
    )

    user: Mapped[User] = relationship(back_populates="settings")


class Notification(ClientIdMixin, SoftDeleteMixin, TimestampMixin, Base):
    __tablename__ = "notifications"
    __table_args__ = (
        UniqueConstraint("user_id", "client_id", name="uq_notifications_user_client"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    type: Mapped[str] = mapped_column(String(50), index=True)
    title: Mapped[str] = mapped_column(String(255))
    message: Mapped[str] = mapped_column(Text)
    is_read: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        index=True,
    )
    event_key: Mapped[str] = mapped_column(String(255), nullable=False)
    related_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    event_metadata: Mapped[dict] = mapped_column(
        JSONB,
        default=dict,
        nullable=False,
    )

    user: Mapped[User] = relationship(back_populates="notifications")
