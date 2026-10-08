-- Read-only admin access: user accounts and money figures only.
--
-- Run once in pgAdmin's Query Tool while connected as the main database user
-- (waffer_user). Re-running it is safe; it refreshes the views.
--
-- Afterwards, connect pgAdmin with waffer_admin instead of waffer_user.
-- That login sees only the admin_view schema below: no notes, categories,
-- payment methods, goal names, shopping lists, notifications or settings,
-- and no password hashes.
--
-- Before running: replace CHANGE_ME with a strong password. Do not commit
-- the real password.

BEGIN;

CREATE SCHEMA IF NOT EXISTS admin_view;

-- Account details without the password hash.
CREATE OR REPLACE VIEW admin_view.users AS
SELECT
    id,
    email,
    name,
    gender,
    birthdate,
    country,
    city,
    street,
    created_at,
    updated_at
FROM public.users;

-- One row per transaction: amount, type and date only.
CREATE OR REPLACE VIEW admin_view.transaction_amounts AS
SELECT
    id,
    user_id,
    type,
    amount,
    currency_code,
    occurred_at
FROM public.transactions
WHERE deleted_at IS NULL;

-- Per-user totals for each currency.
CREATE OR REPLACE VIEW admin_view.user_totals AS
SELECT
    user_id,
    currency_code,
    COUNT(*) AS transaction_count,
    COALESCE(SUM(amount) FILTER (WHERE type = 'income'), 0) AS total_income,
    COALESCE(SUM(amount) FILTER (WHERE type = 'expense'), 0) AS total_expense,
    COALESCE(SUM(amount) FILTER (WHERE type = 'income'), 0)
        - COALESCE(SUM(amount) FILTER (WHERE type = 'expense'), 0) AS balance
FROM public.transactions
WHERE deleted_at IS NULL
GROUP BY user_id, currency_code;

-- Savings goal amounts without the goal name.
CREATE OR REPLACE VIEW admin_view.savings_amounts AS
SELECT
    id,
    user_id,
    currency_code,
    target_amount,
    saved_amount,
    is_completed,
    created_at
FROM public.savings_goals
WHERE deleted_at IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'waffer_admin') THEN
        CREATE ROLE waffer_admin LOGIN PASSWORD 'CHANGE_ME';
    END IF;
END
$$;

-- The views run with the owner's rights, so waffer_admin needs no grants
-- on the real tables in public.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM waffer_admin;
REVOKE ALL ON SCHEMA public FROM waffer_admin;
GRANT USAGE ON SCHEMA admin_view TO waffer_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA admin_view TO waffer_admin;

COMMIT;
