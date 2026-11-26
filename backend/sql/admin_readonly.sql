-- Read-only admin access: user accounts and money figures only.
--
-- Run once in pgAdmin's Query Tool while connected as the main database user
-- (waffer_user). Re-running it is safe; it refreshes the views.
--
-- Afterwards, connect pgAdmin with waffr_admin instead of waffer_user.
-- That login sees only the admin_view schema below: no notes, categories,
-- payment methods, goal names, shopping lists, notifications or settings,
-- and no password hashes.
--
-- It will not run unless you first say, in the same session, that you mean
-- to and which password the login gets (20+ characters, never committed):
--
--   SET waffr.confirm_admin = 'create-read-only-admin';
--   SET waffr.admin_password = '<a long random password>';
--
-- Running it again with a new password changes the login's password. When it
-- is done, run RESET waffr.admin_password; (or close the Query Tool tab).
-- Turn off statement logging first if it is on: the password is in the text.
--
-- Row level security: the API turns it on for every table (row_security.py)
-- and adds a read policy for waffr_admin, so these views keep working.
-- Connected as waffer_user the tables look empty unless you first run
--   SET app.system = 'on';
-- in that Query Tool session.

BEGIN;

-- Stop here, before anything changes, unless the run was asked for on purpose
-- and has a real password.
DO $$
DECLARE
    confirm text := current_setting('waffr.confirm_admin', true);
    secret text := current_setting('waffr.admin_password', true);
BEGIN
    IF confirm IS DISTINCT FROM 'create-read-only-admin' THEN
        RAISE EXCEPTION 'Refusing to run: SET waffr.confirm_admin = ''create-read-only-admin'' first';
    END IF;
    IF secret IS NULL OR length(secret) < 20 OR upper(secret) LIKE '%CHANGE_ME%' THEN
        RAISE EXCEPTION 'Refusing to run: SET waffr.admin_password to a random password of 20 or more characters first';
    END IF;
END
$$;

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

-- Created, or given the new password if it already exists (this also replaces
-- the CHANGE_ME password older versions of this script set).
DO $$
DECLARE
    secret text := current_setting('waffr.admin_password', true);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'waffr_admin') THEN
        EXECUTE format(
            'CREATE ROLE waffr_admin LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS PASSWORD %L',
            secret
        );
    ELSE
        EXECUTE format('ALTER ROLE waffr_admin WITH LOGIN PASSWORD %L', secret);
    END IF;
END
$$;

-- The views run with the owner's rights, so waffr_admin needs no grants
-- on the real tables in public.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM waffr_admin;
REVOKE ALL ON SCHEMA public FROM waffr_admin;
GRANT USAGE ON SCHEMA admin_view TO waffr_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA admin_view TO waffr_admin;

COMMIT;
