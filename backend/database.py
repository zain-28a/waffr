import os
import uuid
from datetime import datetime, timezone

from dotenv import load_dotenv
from sqlalchemy import DateTime, Numeric, String, create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

load_dotenv()


def _engine_url(raw: str | None) -> str:
    # Render hands out postgresql://. SQLAlchemy needs the psycopg driver name.
    if raw is None or not raw.strip():
        raise RuntimeError("DATABASE_URL is not set")
    url = raw.strip()
    if url.startswith("postgres://"):
        url = "postgresql://" + url.removeprefix("postgres://")
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url.removeprefix("postgresql://")
    return url


DATABASE_URL = _engine_url(os.getenv("DATABASE_URL"))

engine = create_engine(DATABASE_URL)

SessionLocal = sessionmaker(
    bind=engine,
    autocommit=False,
    autoflush=False,
)


class Base(DeclarativeBase):
    pass


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def new_client_id() -> str:
    return str(uuid.uuid4())


MONEY = Numeric(18, 2)
RATE = Numeric(18, 6)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utc_now,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )


class CreatedAtMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utc_now,
        nullable=False,
    )


class ClientIdMixin:
    client_id: Mapped[str] = mapped_column(
        String(64),
        default=new_client_id,
        nullable=False,
    )


class SoftDeleteMixin:
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        index=True,
    )


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_tables() -> None:
    Base.metadata.create_all(bind=engine)
    _ensure_schema_updates()


def _ensure_schema_updates() -> None:
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())

    with engine.begin() as connection:
        _ensure_user_timestamp_columns(connection, inspector, tables)
        _ensure_user_photo_column(connection, inspector, tables)
        _ensure_user_profile_columns(connection, inspector, tables)
        _ensure_transaction_columns(connection, inspector, tables)
        _ensure_goal_columns(connection, inspector, tables)
        _ensure_transfer_columns(connection, inspector, tables)
        _ensure_shopping_item_columns(connection, inspector, tables)
        _ensure_recurring_columns(connection, inspector, tables)
        _ensure_notification_columns(connection, inspector, tables)
        _ensure_settings_columns(connection, inspector, tables)
        _ensure_soft_delete_columns(connection, inspector, tables)
        _ensure_transfer_updated_at(connection, inspector, tables)
        _ensure_notification_updated_at(connection, inspector, tables)
        _ensure_notification_event_unique(connection, tables)


def _columns(inspector, table: str) -> set[str]:
    return {column["name"] for column in inspector.get_columns(table)}


def _add_column(connection, inspector, tables: set[str], table: str, name: str, ddl: str) -> None:
    if table not in tables:
        return
    if name in _columns(inspector, table):
        return
    connection.execute(text(f"ALTER TABLE {table} ADD COLUMN {ddl}"))


def _ensure_user_timestamp_columns(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "users",
        "created_at",
        "created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "users",
        "updated_at",
        "updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
    )


def _ensure_user_photo_column(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "users",
        "photo_updated_at",
        "photo_updated_at TIMESTAMPTZ",
    )


def _ensure_user_profile_columns(connection, inspector, tables: set[str]) -> None:
    for name, ddl in (
        ("gender", "gender VARCHAR(20)"),
        ("birthdate", "birthdate VARCHAR(40)"),
        ("country", "country VARCHAR(80)"),
        ("city", "city VARCHAR(80)"),
        ("street", "street VARCHAR(160)"),
    ):
        _add_column(connection, inspector, tables, "users", name, ddl)


def _ensure_transaction_columns(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "transactions",
        "payment_method",
        "payment_method VARCHAR(100)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "transactions",
        "source_id",
        "source_id VARCHAR(255)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "transactions",
        "occurred_at",
        "occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "transactions",
        "frequency",
        "frequency VARCHAR(20) NOT NULL DEFAULT 'none'",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "transactions",
        "period_key",
        "period_key VARCHAR(50)",
    )
    if "transactions" not in tables:
        return
    connection.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_transactions_user_source "
            "ON transactions (user_id, source_id) "
            "WHERE source_id IS NOT NULL"
        )
    )
    connection.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_transactions_user_occurred "
            "ON transactions (user_id, occurred_at)"
        )
    )


def _ensure_goal_columns(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "completed_at",
        "completed_at TIMESTAMPTZ",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "completed_amount",
        "completed_amount NUMERIC(18, 2)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "duration",
        "duration VARCHAR(20) NOT NULL DEFAULT 'month'",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "allocate_percent",
        "allocate_percent NUMERIC(18, 2)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "allocate_amount",
        "allocate_amount NUMERIC(18, 2)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "deduct_frequency",
        "deduct_frequency VARCHAR(20) NOT NULL DEFAULT 'monthly'",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "is_periodic",
        "is_periodic BOOLEAN NOT NULL DEFAULT FALSE",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "duration_count",
        "duration_count INTEGER",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_goals",
        "priority",
        "priority INTEGER NOT NULL DEFAULT 0",
    )


def _ensure_transfer_columns(connection, inspector, tables: set[str]) -> None:
    if "savings_transfers" not in tables:
        return

    _add_column(
        connection,
        inspector,
        tables,
        "savings_transfers",
        "kind",
        "kind VARCHAR(30)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_transfers",
        "note",
        "note VARCHAR(255)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_transfers",
        "occurred_at",
        "occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "savings_transfers",
        "processed_period_key",
        "processed_period_key VARCHAR(50)",
    )

    connection.execute(
        text("ALTER TABLE savings_transfers ALTER COLUMN goal_id DROP NOT NULL")
    )

    fk_rows = connection.execute(
        text(
            """
            SELECT con.conname, pg_get_constraintdef(con.oid)
            FROM pg_constraint con
            JOIN pg_class rel ON rel.oid = con.conrelid
            JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
            WHERE nsp.nspname = 'public'
              AND rel.relname = 'savings_transfers'
              AND con.contype = 'f'
            """
        )
    ).all()

    for name, definition in fk_rows:
        if "goal_id" not in definition:
            continue
        if "ON DELETE SET NULL" in definition.upper():
            return
        connection.execute(
            text(f'ALTER TABLE savings_transfers DROP CONSTRAINT "{name}"')
        )
        connection.execute(
            text(
                "ALTER TABLE savings_transfers "
                "ADD CONSTRAINT savings_transfers_goal_id_fkey "
                "FOREIGN KEY (goal_id) REFERENCES savings_goals(id) "
                "ON DELETE SET NULL"
            )
        )
        return


def _ensure_shopping_item_columns(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "shopping_items",
        "purchased_at",
        "purchased_at TIMESTAMPTZ",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "shopping_items",
        "expense_client_id",
        "expense_client_id VARCHAR(64)",
    )


def _ensure_recurring_columns(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "recurring_expenses",
        "payment_method",
        "payment_method VARCHAR(100) NOT NULL DEFAULT ''",
    )


def _ensure_notification_columns(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "notifications",
        "event_key",
        "event_key VARCHAR(255) NOT NULL DEFAULT ''",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "notifications",
        "related_id",
        "related_id VARCHAR(64)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "notifications",
        "event_metadata",
        "event_metadata JSONB NOT NULL DEFAULT '{}'::jsonb",
    )
    if "notifications" not in tables:
        return
    connection.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_user_event "
            "ON notifications (user_id, event_key)"
        )
    )


def _ensure_soft_delete_columns(connection, inspector, tables: set[str]) -> None:
    for table in (
        "transactions",
        "savings_goals",
        "savings_transfers",
        "shopping_lists",
        "shopping_items",
        "recurring_expenses",
        "notifications",
        "expense_categories",
    ):
        _add_column(
            connection,
            inspector,
            tables,
            table,
            "deleted_at",
            "deleted_at TIMESTAMPTZ",
        )
        if table in tables:
            connection.execute(
                text(
                    f"CREATE INDEX IF NOT EXISTS ix_{table}_deleted_at "
                    f"ON {table} (deleted_at)"
                )
            )


def _ensure_transfer_updated_at(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "savings_transfers",
        "updated_at",
        "updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
    )


def _ensure_notification_updated_at(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "notifications",
        "updated_at",
        "updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
    )


def _ensure_notification_event_unique(connection, tables: set[str]) -> None:
    if "notifications" not in tables:
        return
    connection.execute(
        text(
            "ALTER TABLE notifications "
            "DROP CONSTRAINT IF EXISTS uq_notifications_user_event"
        )
    )
    connection.execute(
        text("DROP INDEX IF EXISTS uq_notifications_user_event")
    )
    connection.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_user_event_live "
            "ON notifications (user_id, event_key) "
            "WHERE deleted_at IS NULL"
        )
    )


def _ensure_settings_columns(connection, inspector, tables: set[str]) -> None:
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "monthly_income_amount",
        "monthly_income_amount NUMERIC(18, 2)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "weekly_income_amount",
        "weekly_income_amount NUMERIC(18, 2)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "processed_period_keys",
        "processed_period_keys JSONB NOT NULL DEFAULT '[]'::jsonb",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "gender",
        "gender VARCHAR(20)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "birthdate",
        "birthdate VARCHAR(40)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "dark_mode",
        "dark_mode BOOLEAN",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "usage_started_at",
        "usage_started_at VARCHAR(40)",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "streak_count",
        "streak_count INTEGER",
    )
    _add_column(
        connection,
        inspector,
        tables,
        "user_settings",
        "streak_last_date",
        "streak_last_date VARCHAR(10)",
    )
