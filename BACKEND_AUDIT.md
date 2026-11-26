# Waffr backend audit: security, data integrity, sync

Date: 2026-11-26. Scope: `backend/` (FastAPI, SQLAlchemy, Postgres), `render.yaml`,
and the Flutter sync client in `lib/core/sync/` plus the stores it reads.

**Status: phase 2 done. The approved fixes are in the code and tested. No
production system was touched**: nothing has been deployed, migrated or rotated.
Section 7 lists what changed. Section 8 lists what still needs you.

All tests ran against a throwaway local Postgres 16, using a role that is not a
superuser and does not have BYPASSRLS, as the suite requires.

| Check | At the audit | After the fixes |
| --- | --- | --- |
| Test suite | 368 passed | **418 passed, 0 failed**. 50 tests were added; the 3 defect reproductions now pass |
| `pip-audit -r requirements.txt --strict` | 2 advisories (PyJWT 2.14.0, not reachable) | **no known vulnerabilities** |
| `bandit -r backend -x tests` at medium severity and confidence | 0 (5 low-confidence false positives) | 0 |
| `ruff check --select E9,F63,F7,F401,F811,F841` | — | clean (this is the CI gate; full style lint not enforced) |
| SQL statements for a 200-row first sync | 414 | **17** |
| 3,000-row first sync, local | 3.3 s | 0.6 s |

Nothing here means the backend is "secure". These are the risks found and
checked on 2026-11-26. Security work has to continue after this.

---

## 1. Architecture assessment

- **Shape.** The backend has one FastAPI process (`backend/main.py`), routers under
  `backend/routers/`, and synchronous SQLAlchemy sessions, one per request (`database.get_db`).
  The app uses only these routes: `/auth/*`, `POST /sync` and `GET /online/news`. The REST
  CRUD routers for transactions, savings, shopping, recurring, notifications and settings
  are still mounted, but nothing in the app calls them.
- **Isolation.** There are two locks. Each route filters on `user_id`, and
  Postgres row level security is enabled and forced on every table
  (`backend/row_security.py`). Startup refuses to run if a model table has no policy.
  Cross-table links (item→list, transfer→goal) are checked in the policies. **Verified strong.**
- **Auth.** Passwords use Argon2id through pwdlib (m=64 MiB, t=3, p=4). Tokens are HS256 JWTs.
  The algorithm is pinned, and `exp` and `sub` are required. Tokens last 7 days, and
  `token_version` revokes them on a password change or reset. There is a lockout after 5 wrong
  passwords, and the reset flow gives the same reply whether or not the email has an account.
- **Privacy.** The app encrypts free text before upload (`enc1:` columns, listed in
  `database.PRIVATE_TEXT_COLUMNS`). Amounts, dates and ids stay readable on the server.
  When a row is soft-deleted, its private text is wiped.
- **Hardening already in place.** Security headers, HSTS, `no-store`, request size limits
  (256 KB, or 25 MB for a signed-in `/sync`), GCRA rate limits, API docs off by default,
  control characters stripped from input, and SQL errors hidden from clients.
- **Weak spots.** Schema migrations are hand-written `ALTER`s that run at import time, with
  no version tracking. Rate limits are in memory, for a single instance only. No CI runs the
  backend tests. The production database is on Render's Free plan (C-1).

## 2. Sync audit

### What is synced

| Entity | Synced | Matched by | Conflict rule | Deletes |
| --- | --- | --- | --- | --- |
| Transactions (income and expense) | yes | (user, client_id) | LWW on client `updated_at` | tombstone, soft delete |
| Savings goals | yes | (user, client_id) | LWW | tombstone |
| Savings transfers | yes | (user, client_id); goal by goal client id | LWW | tombstone |
| Shopping lists | yes (the app uses one default list) | (user, client_id) | LWW | tombstone |
| Shopping items | yes | (user, client_id); list by client id | LWW | tombstone |
| Recurring expenses | yes | (user, client_id) | LWW | tombstone |
| Notifications | yes | client_id, then live `event_key` | LWW | tombstone |
| Custom categories, expense presets | yes | (user, client_id) | LWW | tombstone |
| Settings and profile | yes, one object | the user | LWW; period keys merged as a union; streak merged by day | n/a |

### Verified behaviour

The new and existing tests cover the following:

- New account → upload → second device signs in → receives everything, including the
  transfer→goal links (`test_new_user_uploads_and_a_second_device_receives_everything`).
- Restart → resume from the stored `server_time` cursor without losing rows.
- A lost reply followed by retries does not create duplicate rows. Concurrent identical
  pushes do not create duplicates either: the loser is refused, and its retry succeeds.
- One bad row rolls the whole push back (422). An unexpected error half-way through
  rolls back, and the SQL details stay out of the reply.
- An offline delete reaches the other device. Simultaneous edits keep the later edit.
- Rows from an old offline edit that is pushed late still reach devices that synced
  in between, because pulls filter on the server-side `changed_at` with a 2-minute overlap.
- Cross-account isolation: existing tests in `test_row_security.py`,
  `test_api_security.py` and `test_sync_push_pull.py`.

### Is last-write-wins right for financial data?

Mostly yes, if two weaknesses are fixed. Ledger rows are nearly append-only, and
real conflicts are rare: one person editing the same entry on two phones. A CRDT or
version vectors would be heavy for little gain. LWW has two failure modes that matter
for money:

1. Rows the app *generates* on each device (recurring charges, shopping purchases)
   get random client ids but share a `source_id`. LWW never sees them as the same
   row (H-1).
2. LWW trusts the phone's clock. One phone with a wrong clock can win every conflict
   forever (M-1).

I recommend keeping LWW and fixing both on the server. The changes are in the plan.

---

## 3. Findings

Severity is judged for this deployment: Render Free web service with 512 MB RAM,
open sign-up, and a public GitHub repository.

### Critical

**C-1: The production database has no backups and expires.**
- *Where:* `render.yaml`, `databases[0].plan: free`.
- *Why it matters:* Render's docs say Free Postgres has no backups and no
  point-in-time recovery, and is deleted 30 days after it is created unless it is upgraded.
  A failure, an expiry or a mistaken `DELETE` would lose every user's ledger for good.
  Devices keep a local copy, but users who reinstalled or changed phones would have
  nothing.
- *Fix:* Upgrade to a paid instance. PITR is 3 days on Hobby workspaces and 7 days on
  Pro. Also take a nightly logical `pg_dump`, encrypted, to storage you control, and
  rehearse a restore (section 5).
- *Test:* A restore drill into an isolated database, then run the row-count and
  constraint checks.
- *Manual check needed:* The dashboard may differ from `render.yaml`. Confirm the
  real plan and the creation date.

### High

**H-1: Two devices posting the same recurring charge break sync for good and double the charge on the device.**
- *Where:* `routers/sync.py:_apply_transaction` matches rows only by `client_id`.
  The unique index `uq_transactions_user_source` on `(user_id, source_id)` also covers
  deleted rows. The app (`recurring_expense_store.dart`, `shopping_list_store.dart`)
  mints a random client id for every generated charge.
- *Failure:* Phone A and phone B are both offline when a bill falls due. Each posts
  `recurring:<id>:<minute>`. A syncs first. B's push hits the unique index, the whole
  push rolls back, and every later push from B fails the same way, so none of B's other
  changes upload. B also pulls A's copy and keeps its own, so B shows the bill charged twice.
  The same lock-up happens after *undo + confirm again*: the deleted row still holds the `source_id`.
- *Proof:* Two strict-xfail tests in `test_sync_integrity.py`.
- *Fix (needs approval):* Make the index cover live rows only
  (`WHERE source_id IS NOT NULL AND deleted_at IS NULL`). When an incoming row's
  `source_id` already belongs to a different live row, store the incoming row as a
  tombstone instead of inserting it live. The next pull then tells the pushing phone
  to drop its copy, and both phones end with one charge.

**H-2: Anyone can crash the server by exhausting memory with concurrent logins.**
- *Where:* `auth.py`. Argon2 takes 64 MiB per hash. FastAPI runs sync routes on a
  40-thread pool. `LOGIN_IP` allows a burst of 30.
- *Measured:* 16 concurrent password checks raised peak memory by about 961 MB.
  The Free web instance has 512 MB.
- *Impact:* Unknown emails also trigger a dummy hash, so one IP with no account can
  get the service OOM-killed on demand. Every user is cut off while it restarts.
- *Fix:* A process-wide semaphore around hash and verify, sized for the instance (2 on
  Free). This needs no format change. Optionally lower new hashes to OWASP's Argon2id
  minimum (m=19 MiB, t=2, p=1) and rehash on login. Old hashes keep verifying, because
  the parameters are stored inside each hash.
- *Test:* A concurrency test asserting that at most N hashes run at once. Peak
  memory is measured the same way as above.

**H-3: A Google OAuth client secret is in the public git history.**
- *Where:* Added in commit `fe81ee4` and removed in `c774030`, under the paths
  `cleint id google/web/…json` and `cleint id google/android/…json`. The repository is public.
  The value is not repeated here.
- *Impact:* Anyone can read it from the history. The app no longer uses Google sign-in,
  but the OAuth client may still exist in Google Cloud.
- *Fix (you):* Delete that OAuth client in Google Cloud Console, or rotate its
  secret if you still need it. Rewriting git history does not help once a secret
  has been public; rotation is the fix.

### Medium

**M-1: A phone with a wrong clock can freeze rows.**
- *Where:* every `_apply_*` and `_apply_delete` in `routers/sync.py`. Stamps come
  from the device (`syncNow()` in `sync_clock.dart`).
- *Failure:* A row stamped with 2099 beats every later edit and delete (strict-xfail test).
- *Fix (needs approval):* When writing, clamp incoming `updated_at` and `deleted_at`
  to no later than the server's time plus 5 minutes. Rows the app sends with normal
  clocks are unchanged.

**M-2: IP rate limits can be bypassed on Render.**
- *Where:* `client_address.py` trusts the left-most `X-Forwarded-For` entry. Render
  appends to a client-supplied header instead of replacing it.
- *Impact:* The per-IP limits on login, register, forgot and reset, and the
  anonymous global limit, can be dodged by sending a fresh fake address each time.
  The per-email and global limits still hold. Security-log IPs can be forged.
- *Fix:* Read the entry Render's proxy appends (counting from the right), or
  `True-Client-IP` if Render confirms it is always set. *Manual step:* one capture of
  real request headers on a deploy, to pin the right position.

**M-3: Anyone who knows an email can keep that account locked out.**
- *Where:* `main.py:login` (5 failures → 15-minute lock) and `LOGIN_FAILURES_EMAIL`.
- *Impact:* 5 wrong passwords every 15 minutes keep the account locked from anywhere.
  Password reset unlocks it, but needs email to be configured.
- *Fix (needs approval):* Count failures per (email, IP) with the current limit, and
  add a higher per-email ceiling, for example 20 per hour, to stop distributed guessing.

**M-4: Sync cost grows with ledger size, enough to time out or run out of memory.**
- *Where:* `_get_by_client` runs a flush and a SELECT for every row, and inserts happen
  one at a time (414 SQL statements for 200 rows).
- *Measured:* An 18 MB body (50k rows) costs about 134 MB just to parse. Add ORM objects
  and the reply. Two concurrent large syncs can OOM a 512 MB instance, and open sign-up
  lets anyone make an account to do it. A 3,000-row first sync took 3.3 s locally; Render
  Free is many times slower, and the app gives up after 75 s and never saves its cursor.
- *Side effect:* Rows are flushed early in a long transaction. If a sync runs longer
  than the 2-minute `PULL_OVERLAP`, another device can miss its rows.
- *Fix:* Fetch each collection's existing rows in one query by `client_id`, insert in
  bulk, allow one sync at a time per user (a second gets a retryable 409), cap global
  sync concurrency, and size the body cap to real account sizes. The sync rules do not change.

**M-5: The read-only admin script defaults to a known password.**
- *Where:* `backend/sql/admin_readonly.sql` creates `waffr_admin` with `PASSWORD 'CHANGE_ME'`.
  Render Postgres accepts external connections from any IP by default.
- *Impact:* If the script was run unedited, anyone can read emails, addresses and
  amounts through `admin_view`.
- *Fix:* Make the script refuse to run without a supplied password. *Manual check:* Has
  the role been created, and with what password? Also set the database's external access
  allowlist to empty, or to your own IP.

**M-6: No CI runs the backend tests or scanners.** `.github/workflows/build-apk.yml`
covers Flutter only.
- *Fix:* A workflow with a Postgres service that runs pytest, ruff, bandit and pip-audit.

**M-7: Constraints may be missing on older production tables.** `create_all` only
creates *missing tables*. The `(user_id, client_id)` unique constraints and the CHECKs on tables
that existed before those were added are never back-filled by `_ensure_schema_updates`.
Without them, concurrent pushes can create duplicate rows.
- *Manual check (read-only):*
  ```sql
  SELECT conrelid::regclass, conname FROM pg_constraint
  WHERE conname LIKE 'uq_%_user_client' ORDER BY 1;
  ```
  Expect 9 rows. If any are missing, add them in an approved migration after a
  duplicate scan. Longer term, move to Alembic.

### Low

- **L-1: PyJWT 2.14.0.** PYSEC-2026-4141 (a nested payload raises RecursionError, but only
  before signature verification, which this code never does) and PYSEC-2026-4183 (OKP JWK,
  not used). Upgrade to 2.15.0.
- **L-2: Account deletion is slow and memory-heavy for large accounts.** It loads every
  child row through the ORM cascade (no `passive_deletes`). It also does not ask for the
  password again; that is already known.
- **L-3: The health check `/` never touches the database**, so Render cannot see a
  database outage. Add `/healthz` that runs `SELECT 1` and answers only ok or fail.
- **L-4: No `pool_pre_ping` / `pool_recycle` / `statement_timeout`.** Stale
  connections after database maintenance surface as "Sync failed", and runaway queries
  are not cut off.
- **L-5: `/sync` answers 400 for server faults and unique-constraint races.** Use 500 or
  503 for faults and 409 for races, so monitoring can tell client errors from server
  errors. The app retries any non-200 the same way.
- **L-6: Sign-up shows whether an email is registered, and there is no email
  verification.** Both are already known.
- **L-7: Bad values are silently changed.** An unknown currency becomes `SYP`, and a
  negative quantity or interval becomes 1. Amounts with more than 2 decimals are rounded
  by Postgres while the device keeps the unrounded value, so devices can differ by small
  fractions of a unit.
- **L-8: Two charges for one due date across time zones.** The recurring charge source id
  uses the phone's local time, so phones in different time zones each make their own
  charge. This is a client issue.
- **L-9: Some data grows without limit.** Notification `metadata` values have no length
  cap, `processed_period_keys` grows forever, and tombstones are never purged (their text is wiped).
- **L-10: Toolchain versions not pinned.** The Python version is not pinned for Render,
  and GitHub Actions are pinned to tags, not commit SHAs.
- **L-11: Unused REST CRUD routes.** They are protected by auth and row security, but
  they add attack surface, and their soft deletes do not wipe private text the way
  `/sync` does. Remove them, or put them behind a flag.
- **L-12: 7-day tokens with no server-side sign-out.** A stolen token works until it
  expires or the password changes. A "sign out everywhere" route that bumps
  `token_version` would be cheap. Refresh tokens are not worth the complexity here.

### Verified as already sound

Token checks: an unsigned (`alg=none`) token, a wrong key, HS512 with the right key, an edited payload, or a missing `exp` are all refused (new tests in `test_auth.py`),
row security forced on every table, ownership checks on every `{id}` route, client
fields cannot change `user_id`, request bodies are refused before they are read,
the reset flow gives the same reply whether or not the email exists, the token version
is checked on every request, no tokens or passwords appear in logs, and the security
headers are set.

---

## 4. Dependencies

| Package | Pinned | Status |
| --- | --- | --- |
| PyJWT | 2.14.0 | 2 advisories, not reachable → bump to 2.15.0 |
| fastapi 0.141.1, uvicorn 0.53.0, sqlalchemy 2.0.54, psycopg 3.3.6, pydantic 2.13.5, pwdlib 0.3.1, feedparser 6.0.14, email-validator 2.3.0, python-dotenv 1.2.3 | exact | no known advisories (pip-audit, 2026-11-26) |

All dependencies are pinned exactly, but there is no hash pinning or lock file for the
dependencies of those packages. The Python version is not pinned on Render. The tests
pass on 3.13.

## 5. Backup and recovery

- **What exists today:** nothing on the server side, if the database really is on the Free plan (C-1).
- **Plan:**
  1. Upgrade the database instance. PITR then gives a 3-day window on Hobby workspaces
     and 7 days on Pro.
  2. Take a nightly `pg_dump -Fc` with a read-only credential (a separate role, not the
     app role), encrypt it with `age` or `gpg` using a key that is not stored with the
     backup, keep 30 days, and store it off Render.
  3. **Monthly drill:** restore the latest dump into an isolated database. Run the app's
     startup against it, which applies migrations and policies. Then run the read-only
     checks: row counts per table, the 9 unique constraints, and an RLS smoke test as two
     test accounts. Record how long the restore took.
  4. Never restore over production. With PITR, Render restores into a **new** instance;
     check it, then move `DATABASE_URL`.

## 6. Questions requiring your approval

1. **H-1 fix:** a live-rows-only `source_id` index, and storing a duplicate generated
   charge as a tombstone. This changes the sync rules and the schema. The index change
   only loosens a constraint, so it is safe for existing rows.
2. **M-1 fix:** clamp device stamps to the server's time plus 5 minutes.
3. **Auth:** the Argon2 concurrency limit (no visible change), lower Argon2 parameters
   for new hashes with rehash on login (no sign-outs), and the lockout change from M-3.
4. **Performance:** batched sync (no rule change), a per-user sync lock with a 409, and a
   lower body cap. For the cap, tell me the largest real account you know of, or I will
   keep 25 MB.
5. **Low-risk batch:** the PyJWT bump, `/healthz`, pool pre-ping and a statement timeout,
   proper 409/500 codes, backend CI, the admin-script guard, and L-2.
6. **Manual items for you:** the real database plan (C-1), the Google OAuth client
   (H-3), a header capture for M-2, the `waffr_admin` role (M-5), the constraint query
   (M-7), and the database's external access allowlist.

---

## 7. What changed (phase 2)

| Finding | Status | Change | Verified by |
| --- | --- | --- | --- |
| **H-1** duplicate `source_id` | **Fixed** | `routers/sync.py`: after the tombstones, `_dedupe_sources` keeps one live row per source id. That is the row the server already had, or else the first in the push. Other copies are stored as tombstones stamped no earlier than the device's own stamp, so that device drops its copy in the same reply. `transaction_model.py` and `database.py`: the unique index now covers live rows only (`uq_transactions_user_source_live`). It is built before the old one is dropped, and it only loosens the rule, so existing rows already satisfy it. The REST create looks only at live rows. | `test_sync_integrity.py`: two devices, the tombstone reaching the device, repeat pushes, two copies in one push, undo then repost in one push or across pushes, a revival conflict, two accounts, the index definition. Migration checked on a database built by the old code. |
| **M-1** wrong device clock | **Fixed** | Stamps are capped at the server clock plus 5 minutes (`CLOCK_SKEW`), for rows, tombstones and settings. A stamp stored further ahead before this change loses to any change, so frozen rows heal on their next edit. Event times (`occurred_at`) are not touched. | A 2099 edit followed by a later delete; healing a pre-existing 2099 row; capped settings. |
| **H-2** Argon2 memory | **Fixed** | `auth.py`: at most `PASSWORD_HASH_CONCURRENCY` (2) hashes run at once. A request that waits more than 20 s gets `503` with `Retry-After`. New hashes use OWASP's minimum (19 MiB, t=2, p=1). Old hashes still verify and are rewritten at the next sign-in. `token_version` is untouched, so **nobody is signed out**. Login no longer holds a pooled connection while it waits to hash. | Hash parameters; an old hash signing in, upgrading, and the old token still working; a concurrency limit test (12 threads, at most 2 at once); 503 when the queue is full. |
| **M-3** targeted lockout | **Fixed** | `main.py` and `rate_limit.py`: wrong passwords are throttled per **email + IP** (5 per 15 min). A ceiling of 20 per hour applies per email from all addresses. The account lock comes after 20 in a row. A successful sign-in or reset clears the counters. | The owner signing in from another address after a stranger is throttled; a lock after 20 failures spread over many addresses; the ceiling for unknown emails. |
| **M-4** sync cost | **Fixed** | One batched lookup per collection, batched inserts, one flush for parents and one before the reply. One sync per account at a time, using a Postgres advisory lock (`409` with `Retry-After`). At most `SYNC_CONCURRENCY` (2) syncs at once server-wide (`security_middleware.SyncConcurrencyMiddleware`, applied before the body is read, `503` after 20 s). The reply serializes rows as stored (`populate_existing`). The 25 MB cap is kept, as no account size was given. The `changed_at` window now covers only the final flush, which also closes L-13. | A query-count test (300 rows in under 60 statements), the per-account lock, another account not blocked, the global cap, concurrent identical pushes. |
| L-1 PyJWT | Fixed | 2.15.0 | pip-audit clean; token forgery tests |
| L-2 account deletion | Fixed | One `DELETE` per owned table, children first, then the user, in one transaction. It does not rely on `ON DELETE CASCADE` and loads nothing. Startup refuses to run if the list misses an owned table. | Every owned table is emptied for that user and the other account is intact; a failure half-way keeps everything; coverage of the list. |
| L-3 readiness | Fixed | `GET /healthz` runs `SELECT 1` with a 2 s statement timeout and caches the answer for 5 s. It answers only `{"status": "ok"}` or `503 {"status": "unavailable"}`. `GET /` stays Render's liveness check (`render.yaml` unchanged). | ok, down (no details leaked), caching, `/` not touching the database |
| L-4 pool and timeouts | Fixed | `pool_pre_ping`, `pool_recycle=1800`, `connect_timeout=10`, `statement_timeout` 30 s and `idle_in_transaction_session_timeout` 5 min, set at connect time (works through a pooler). Migrations lift the statement timeout. Database errors anywhere become `503` with no details. | Timeout present on connections; a slow query cancelled; an outage returning 503 without host names |
| L-5 status codes | Fixed | `/sync`: 422 bad row, 409 conflict or second sync, 503 database, 500 other. The app treats every non-200 except 401 as "try later" (`sync_service.dart`), and only 401 clears a session (`auth_session.dart`), so the app needs no change. | A parametrized test for each code, with nothing leaked |
| M-5 admin script | Fixed in code | `sql/admin_readonly.sql` stops before changing anything unless the session sets `waffr.confirm_admin` and a `waffr.admin_password` of 20+ characters that is not `CHANGE_ME`. A re-run replaces an old `CHANGE_ME` password. | Run locally: refused with no settings; refused with a weak password; created; rotated; the admin can read `admin_view`; `public.users` refused |
| M-6 CI | Fixed | `.github/workflows/backend.yml`: Postgres 16 service, a non-superuser test role, pytest, the ruff error gate, bandit (medium/medium), and `pip-audit --strict`. Read-only token, no repository secrets, actions pinned to commit SHAs, `persist-credentials: false`. | Every step was run locally with the same commands. The workflow itself has not run on GitHub yet |

Docs updated: `SECURITY.md` (limits, lockout, new settings), `backend/routers/README.md`
(sync rules, error codes) and `backend/sql/README.md`.

### Still open (not approved or not doable from code)

- **C-1, H-3, M-5 (production side), M-7**: these need you; see section 8.
- **M-2** `X-Forwarded-For`: fixed in the pre-merge verification as P-1 (`SECURITY_VERIFICATION.md`): `True-Client-IP` is used first. It still needs one check on Render after the deploy.
- **L-6** email verification at sign-up, **L-7** silent coercion and rounding, **L-8** time-zone dependent source ids (app), **L-9** growth and purging, **L-10** pinning the Python version on Render (a deploy change), **L-11** unused REST routes, **L-12** sign out everywhere.
- **App follow-up for M-1**: a phone with a wrong clock keeps its own future-stamped copy of a row, because the app only takes strictly newer server rows. Other devices and the server stay correct. A fix belongs in the app (`sync_merge.dart`).

## 8. Manual steps for you

1. **Database plan (C-1).** In the Render dashboard, check the database's plan and creation date. If it is Free, upgrade it before it expires, then set up the nightly encrypted `pg_dump` and the restore drill in section 5.
2. **Google OAuth client (H-3).** In Google Cloud Console → APIs & Services → Credentials, delete the OAuth client from commit `fe81ee4`, or rotate its secret.
3. **`waffr_admin` (M-5).** Run `SELECT rolname FROM pg_roles WHERE rolname = 'waffr_admin';`. If the role exists, re-run the new script with a fresh password, which replaces `CHANGE_ME`. Then limit the database's external access to your own IP.
4. **Constraints (M-7).** Run the read-only query in M-7, expect 9 rows, and send me the result.
5. **Header capture (M-2).** After the next deploy, send one request with a made-up `X-Forwarded-For: 1.2.3.4` and note what the security log shows as `ip`. I can then pin the right entry.
6. **Deploy.** Merging this branch deploys it. On first start, the API builds the new source-id index and drops the old one, in one short transaction. Nobody is signed out. Existing password hashes are upgraded as people sign in.
