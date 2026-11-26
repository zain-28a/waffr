# Waffr security verification (pre-merge)

Date: 2026-11-26. Branch: `claude/affectionate-wozniak-9zle5o`, before merge.
This builds on `BACKEND_AUDIT.md`; IDs C-, H-, M- and L- refer to that report.
The ones that start with P- are new here.

## Scope, method and safety

- **What was tested:** the FastAPI backend, the Postgres schema and row
  security, auth and sessions, `/sync`, the deployment files (`render.yaml`,
  both GitHub workflows), git history, and a code review of the Flutter
  client's auth, crypto, storage and transport.
- **Where:** a local uvicorn server against a throwaway local Postgres 16.
  The app connected as an owner role that is neither superuser nor BYPASSRLS,
  the same as on Render, with `RENDER=true` so the proxy-header logic ran as it
  does there. All accounts and data were synthetic.
- **What was not touched:** the live server, the production database, Render
  settings and credentials. Nothing was deployed, merged or migrated in
  production. No secret values are reproduced in this report or in the
  repository.
- **How:** scripted HTTP attacks against the local server, automated
  regression tests (each was written to fail first and passes after its fix),
  static analysis, and dependency audits.

## Results at a glance

| Check | Result |
| --- | --- |
| Backend test suite | **443 passed, 0 failed** (25 tests added in this pass) |
| New regression tests (`tests/test_pentest_regressions.py`, `test_online.py`) | 25 added. They failed before the fixes and pass after |
| Live re-test against the patched local server | every confirmed issue reproduced before its fix and no longer reproduces after (see each finding) |
| `pip-audit` (runtime and dev requirements) | no known vulnerabilities |
| `bandit` (medium severity, medium confidence) | 0 findings. At all levels: 3× B105 (`"bearer"`) and 2× B608 (constant identifiers), all reviewed and all false positives |
| `ruff` error gate, plus the `S` security rules | gate clean. `S608`/`S310` reviewed and false positives (constant SQL identifiers; fixed HTTPS feed URLs) |
| Secret sweep of the git history (199 commits) | one real secret (H-3). The signing passwords in CI come from GitHub secrets |
| Dart dependency audit | **not performed.** `api.osv.dev` is blocked from this environment (see the manual steps) |

## Findings

Status key: **Fixed** means fixed and covered by a regression test. **Open** means not
fixed, with the reason given. **Verify** means fixed in code, but it depends on Render
behaviour that only a deploy can confirm.

### Critical

| ID | Finding | Status |
| --- | --- | --- |
| C-1 | `render.yaml` puts the production database on the Free plan, which Render documents as having no backups or PITR and as expiring after 30 days. All cloud data could be lost. | **Open.** You need to check and upgrade the database plan. This cannot be fixed in code. |

### High

**P-1: A forged `X-Forwarded-For` bypassed every per-address limit, and could lock anyone out from a single machine.** *Fixed / Verify.*
- *Cause:* `client_address.py` trusted the left-most `X-Forwarded-For` entry. Render
  keeps a value the client sends and appends the real address after it.
- *Evidence (before the fix):* 35 logins with a rotating forged address returned 35 × 401
  and 0 × 429; a fixed address got 429 after 30. Register: 15 of 15 accepted (limit 10).
  25 guesses at one victim, each with a new forged address, gave 20 × 401, which
  **locked the victim's account** (the owner got 429). That defeats the M-3 lockout
  fix from phase 2.
- *Fix:* behind Render, use `True-Client-IP`, which Cloudflare overwrites with the
  connecting address. Without it, use the entry `TRUSTED_PROXY_HOPS` places from the
  right. The forgeable left-most entry is used only as a last resort.
- *After:* the same 25 guesses gave 5 × 401 and 20 × 429, and the owner still signed in
  from another address. The register flood stopped at 10.
- *Tests:* `test_a_forged_forwarded_for_does_not_dodge_the_per_address_limit`, plus
  three tests for header parsing.
- *Verify:* a third-party demo of Render's behaviour is the evidence that Render overwrites
  `True-Client-IP`. It is not Render documentation. Confirm it after the deploy (manual step 3).

**P-2: Simultaneous wrong passwords got past the throttle.** *Fixed.*
- *Cause:* `login` checked the counters before verifying the password and counted only
  after a failure, so a burst of requests all passed the check.
- *Evidence (before the fix):* 40 simultaneous guesses at one account gave 40 × 401
  against a limit of 5 per address and 20 per email. The database failure counter
  could also lose updates (a Python-side `+= 1`).
- *Fix:* each attempt is counted as it arrives, and a right password gives the attempts
  back. The failure counter is one atomic `UPDATE … RETURNING`.
- *After:* 40 simultaneous guesses from 40 addresses gave 20 × 401 and 20 × 429, which is
  exactly the per-email ceiling.
- *Tests:* `test_concurrent_wrong_passwords_cannot_exceed_the_limit`,
  `test_the_failure_count_is_not_lost_under_concurrency`, and
  `test_a_right_password_still_works_after_a_few_wrong_ones`.

| ID | Finding | Status |
| --- | --- | --- |
| H-3 | A Google OAuth web client secret is in the public git history (commit `fe81ee4`). | **Open.** You need to delete or rotate that OAuth client in Google Cloud Console. |

### Medium

**P-3: Two devices setting the data key at the same moment could both get 200.** *Fixed.*
- *Impact:* one device kept encrypting with a key that the server had replaced, so its
  synced private text became unreadable on every other device and after a reinstall.
- *Evidence:* 8 simultaneous `PUT /auth/key` returned 200, 200 and 6 × 409.
- *Fix:* a conditional `UPDATE … WHERE wrapped_key IS NULL`.
- *After:* 200 and 7 × 409, and the stored key is the winner's.
- *Test:* `test_only_one_data_key_wins_a_race`.

**P-5: Logs could contain financial data.**
- *Cause:* SQLAlchemy errors carried the bound parameters (amounts, sealed text).
  Postgres error text quotes refused values. `logger.exception` and uvicorn's
  unhandled-error log printed both.
- *Fix:*
  - `hide_parameters=True` on the engine.
  - A new `safe_errors.py` logs the exception type and stack, never the message.
  - The outermost `SafeErrorMiddleware` turns any escaped error into a plain
    `500 {"detail":"Internal server error"}`.
- *Tests:* `test_database_errors_do_not_carry_their_parameters`,
  `test_a_failed_sync_logs_no_error_text` and
  `test_an_unexpected_error_anywhere_is_a_plain_500_and_a_clean_log`.
- *Status:* **Fixed.**

**P-8: Anonymous news reads could make the server refetch the feeds on every request.**
- *Cause:* while the news table is empty (a fresh database, or feeds that never
  succeeded), each unauthenticated `GET /online/news` started a fetch. Other readers
  waited on it, holding worker threads, and the next read started another fetch to
  the third-party sites.
- *Fix:* one fill attempt per 10 minutes. Reads in between, and reads while a fetch
  is running, get an immediate 503.
- *Test:* `test_an_empty_table_is_not_refetched_on_every_anonymous_read`.
- *Status:* **Fixed.**

| ID | Finding | Status |
| --- | --- | --- |
| P-9 | **Residual lockout by a distributed attacker.** 20 wrong passwords from at least 4 real addresses still lock an account for 15 minutes. This is the deliberate trade-off between brute force and lockout. | **Open.** It is a design choice; the options are under recommended actions. |
| M-5 | `waffr_admin` may still have the old `CHANGE_ME` password in production, and Render databases accept outside connections by default. | **Open.** The script is fixed; you need to check the production role. |
| M-7 | Older production tables may be missing the `(user_id, client_id)` unique constraints. | **Open.** You need to run the read-only check query. |
| L-6 | Sign-up shows whether an email is registered, and there is no email verification. | **Open.** It needs an app flow and email to be working. |

### Low

| ID | Finding | Status |
| --- | --- | --- |
| P-4 | Path ids outside the Postgres integer range (e.g. `/transactions/99999999999`) raised an unhandled `DataError`: a 500 and a reset connection, with the value in the log. | **Fixed.** Ids are `1 … 2147483647` (422 otherwise), and a `DataError` handler is the backstop. `test_out_of_range_ids_are_refused_cleanly` covers 8 routes. |
| P-6 | 422 errors echoed the rejected input, including an over-long password and a sync row's private text. | **Fixed.** Validation errors return only `type`, `loc` and `msg`. The app reads only `detail[0].msg`, so it still works. Two tests. |
| P-7 | An account could be deleted while one of its syncs was still writing. | **Fixed.** Deletion takes the same per-account advisory lock as sync. `test_account_deletion_waits_for_a_running_sync`. |
| P-10 | The APK workflow holds the release signing key but had default token permissions and actions pinned only to tags. | **Fixed.** `permissions: contents: read`, actions pinned to the commits their tags point to today, `persist-credentials: false`. The workflow has not run on GitHub yet. |
| P-11 | **Client:** Android `allowBackup` is unset (default on), so the unencrypted ledger in SharedPreferences goes into the user's device backups. | **Fixed in code** (`CLIENT_SECURITY_DECISIONS.md` §4.1): backup rules plus an encrypted backup file. It still needs an APK build and on-device checks. |
| P-12 | **Client:** the data key is wrapped with PBKDF2-SHA256 at 210,000 iterations (OWASP recommends 600,000). `/auth/me` hands the wrapped key to anyone holding a valid token, which allows an offline guess at the password. | **Open.** The server route is ready; the app change is held because the benchmark showed pure-Dart 600,000 too slow on low-end phones (`CLIENT_SECURITY_DECISIONS.md` §4.2). |
| L-12 | 7-day bearer tokens with no server-side sign-out. Account deletion needs no password. | **Open.** |
| L-10 | The Python version is not pinned for Render. | **Open.** It is a deploy-configuration change. |

### Tested and holding

- **BOLA (API1).**
  - Bob's ids sent with Alice's token to 13 REST operations (GET, PATCH, DELETE,
    creating an item in his list, a transfer into his goal) all returned 404, and
    Bob's rows were unchanged.
  - Pushing Bob's `client_id`s through `/sync` touched only Alice's namespace.
    Links to Bob's goal resolved to none.
  - Row security sits behind this as a second lock (existing tests).
- **Function-level auth (API5).** A new inventory test walks every route.
  - Every route needs a valid token except exactly 7 public ones: `/`, `/healthz`,
    `/online/news`, and register, login, forgot and reset.
  - Adding a public route by mistake fails the test.
- **Mass assignment (API3).**
  - At register: `id`, `token_version`, `wrapped_key`, `failed_login_count` and
    `is_admin` are all ignored.
  - In sync rows: `user_id`, `id` and `changed_at` are ignored.
  - In PATCH: `user_id`, `id` and `client_id` are ignored.
- **SQL injection.**
  - 6 payloads were sent in 10 string fields of a sync push, plus a query parameter
    and a login email. Every push returned 200 or 422, with no timing change (no
    `pg_sleep` effect).
  - The payloads were stored literally and the tables survived.
  - All raw SQL in the code uses constant identifiers and bound values.
- **JWT.** These were all refused with 401: `alg=none`, a wrong key, HS512 with the
  right key, an edited payload, no `exp`, an expired token, deeply nested header and
  payload JSON, a 7 KB token, and the `Basic` scheme.
- **Existing sessions.** Tokens issued before these changes still work: there is no
  token-format change. The Argon2 rehash keeps `token_version`.
- **Configuration and exposure.**
  - The security headers (HSTS, CSP, nosniff, DENY, no-store) are on every response,
    and there is no `Server` header.
  - `/docs`, `/redoc` and `/openapi.json` return 404.
  - OPTIONS and TRACE return 405.
  - A deeply nested JSON body returns 400.
  - CORS is off unless `CORS_ORIGINS` is set, with `allow_credentials=False`. It was
    not exercised with an origin configured.
- **Account deletion and isolation.** Every owned table is emptied for that user and
  the other account is intact. A failure part-way through keeps everything, and old
  tokens then return 401.
- **Sync integrity.** The phase-2 tests pass: duplicates, clock cap, per-account lock,
  concurrent pushes, rollback.
- **Client.**
  - The token and data key are in `flutter_secure_storage`.
  - Release Android builds refuse cleartext.
  - iOS ATS allows only local networking.
  - The API base-URL override is not settable from the UI.
  - Text is sealed with AES-256-GCM using a fresh random nonce per seal.
  - The legacy stored password is only ever deleted.

## Changes in this pass

`backend/client_address.py`, `main.py` (login counting, data key, delete lock, error
handlers), `database.py` (`hide_parameters`), `safe_errors.py` (new),
`security_middleware.py`, `routers/sync.py` (safe 422 detail and log),
`routers/*.py` and `crud_utils.py` (`RecordId`), `news_service.py`,
`password_reset.py`, `tests/conftest.py` (loopback lookups allowed for concurrency
tests), new and extended tests, `.github/workflows/build-apk.yml`, and `SECURITY.md`.

No schema change, no token or session change, and no API shape change. The only
visible differences: 422 bodies no longer include `input`; out-of-range ids get 422
instead of 500; a second simultaneous data-key setter gets 409; and an empty news
table answers 503 during the 10-minute pause.

## Remaining risks and recommended actions

1. **Back up the database before anything else (C-1).** Until that is done, a database
   failure or expiry loses everyone's cloud copy.
2. **Rotate the leaked Google OAuth client (H-3).**
3. **After deploying, confirm the client address.** Send one request with a made-up
   `X-Forwarded-For: 192.0.2.1` and check that the security log's `ip` is your real
   address. If it shows `192.0.2.1`, `True-Client-IP` is missing: set
   `TRUSTED_PROXY_HOPS` (the third-party demo suggests 2) and check again.
4. Check `waffr_admin` and restrict the database's external access (M-5). Run the
   constraint query (M-7).
5. **Audit the Dart dependencies** where the internet is reachable:
   `flutter pub outdated`, and `osv-scanner --lockfile=pubspec.lock`. Or enable
   Dependabot for pub and pip.
6. **App follow-ups:** set `allowBackup="false"` or backup exclusion rules (P-11), and
   raise PBKDF2 to 600,000 iterations (P-12).
7. **Optional hardening:**
   - For P-9, replace the hard lock with a progressively longer delay, or require the
     emailed code after N failures.
   - Add email verification at sign-up.
   - Add a "sign out everywhere" route.
   - Ask for the password again before deleting an account.
   - Pin the Python version on Render.

## Is it ready for production?

**Not yet, but the blockers are operational, not in the code.**

- **The branch.** This branch fixes every code-level vulnerability that this assessment
  confirmed. Deploying it lowers risk compared with what is running now, and the
  verification found no regressions in auth, existing sessions or sync. The app's
  offline-first behaviour was not run here; this pass changed no client code.
- **The data.** Production holds users' financial records on a database that, per
  `render.yaml`, has no backups (C-1). A public secret also still needs rotating (H-3).
  I would not call the service production-ready until both are done.
- **The rate limits.** The main rate-limit fix (P-1) needs one check after the deploy
  to confirm that Render sets `True-Client-IP` as expected.

The tests and probes above reduce risk; they do not prove the absence of vulnerabilities.
Security needs regular dependency audits, log review and repeat testing as the code changes.
