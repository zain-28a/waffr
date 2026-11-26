# Waffr: consolidated security status report

Date: 2026-11-26. Branch `claude/affectionate-wozniak-9zle5o` at `74d22a3`.
Scope: backend (FastAPI, Postgres), Flutter client security code, backup/restore,
key management, CI. **No code, configuration, iteration count or production setting was
changed for this report.** Production was not contacted.

## How this was verified

Each claim below has one of these evidence levels:

- **Live** — re-run in this report against a local server (`127.0.0.1:8766`, production-like
  settings: `RENDER=true`, no `TRUSTED_PROXY_HOPS`, no `KEY_UPGRADE_ENABLED`) with synthetic data.
- **Suite** — the automated test suite, re-run in this report: **481 passed, 0 failed**.
- **Code** — read in the source, no test run.
- **Not verified** — stated as such; not assumed.

Static checks re-run now: `ruff` (error gate) clean; `bandit` at medium/medium: 0 findings
(5 low-confidence items, all reviewed earlier as false positives); `pip-audit --strict` on
runtime and dev requirements: no known vulnerabilities.

The Flutter suite was not re-run here; its last full run was 1,298 passed on the Release A
commit, and no Flutter code has changed since.

---

## 1. Summary

| Status | Count | Notes |
| --- | --- | --- |
| Fixed and re-verified in this report (live or suite) | 14 | see §2 |
| Fixed, tested in the suite only | 9 | see §2 |
| **Partially fixed, depends on deployment** | 1 | **P-1 (X-Forwarded-For)** |
| Open | 11 | see §5 |
| Open, needs production access or a manual check | 4 | C-1, M-5, M-7, H-3 history |

**The application is not ready for a public launch.** Blockers are C-1 (no production database
backups), the signing-key verification (N-3), and the client-address question in P-1. Those are
planned for the launch-preparation phase.

---

## 2. Vulnerabilities found, and their status

Each row lists how it was checked in this report.

| ID | Severity (as recorded) | Issue | Status | Evidence in this report |
| --- | --- | --- | --- | --- |
| H-1 | High | Two devices posting the same generated charge locked sync | **Fixed** | Suite: `test_sync_integrity` (11 tests incl. duplicate source id, undo and repost) |
| H-2 | High | Concurrent logins exhausted server memory (Argon2) | **Fixed** | Suite: concurrency limit test (12 threads, max 2 at once) and 503 when queue full |
| H-3 | High | Google OAuth secret in public git history | **Open** | Current tree: no tracked file matches (checked). History still contains it (commit `fe81ee4`). Needs rotation by you |
| **P-1** | High | Forged `X-Forwarded-For` defeats the per-address limit | **Partially fixed** | Live, see §3 |
| P-2 | High | Simultaneous wrong passwords passed the check | **Fixed** | Live: 20 simultaneous from one address → 5×401, 15×429; 40 simultaneous from 40 addresses → 20×401, 20×429 (exact per-email cap) |
| P-3 | Medium | Two devices setting the data key both got 200 | **Fixed** | Live: 8 racing `PUT /auth/key` → 1×200, 7×409 |
| P-4 | Low | Out-of-range ids crashed with 500 | **Fixed** | Live: `/transactions/99999999999` → 422 |
| P-5 | Medium | SQL parameters and error text in logs | **Fixed** | Live: log grep for test values → 0 matches. Suite: `test_database_errors_do_not_carry_their_parameters` |
| P-6 | Low | 422 responses echoed input (passwords, private text) | **Fixed** | Live: 300-char password → 422 without the value in the body |
| P-7 | Low | Account deletable during a running sync | **Fixed** | Suite: `test_account_deletion_waits_for_a_running_sync` |
| P-8 | Medium | Anonymous news reads refetched third-party feeds on every request | **Fixed** | Suite: `test_an_empty_table_is_not_refetched_on_every_anonymous_read` |
| P-9 | Medium | Distributed attacker can lock an account (and its owner) | **Open (design trade-off)** | Live, §3 |
| P-10 | Medium | APK workflow token permissions, unpinned actions | **Fixed** | Native-crypto workflow ran green on GitHub with pinned actions (run 45852020847) |
| P-11 | Medium | Plaintext ledger in Android backups | **Mitigated, not verified on device** | Backup rules exist and are tested as text (`android_backup_rules_test`); on-device `bmgr` check not done |
| P-12 | Medium | Wrapped data key returned to any valid token; 210,000 rounds | **Open** | Code: `_user_payload` includes `data_key`; the 600,000 upgrade is not released (deferred) |
| C-1 | Critical | Production database has no backups; Free plan expiry | **Open** | Not verifiable from here. Deferred to launch preparation (a blocker for launch) |
| M-1 | Medium | Device clock set in the future freezes rows | **Fixed (server)** | Suite: 3 tests (clamp, stored-future heal, settings cap). The app-side follow-up is still open |
| M-3 | Medium | Targeted lockout by the owner's own address | **Fixed** | Live: owner's guesses from one address are throttled; the other address signs in |
| M-4 | Medium | Sync cost per row, OOM risk | **Fixed** | Suite: query count test (300 rows < 60 statements); earlier measurement 414 → 17 for 200 rows |
| M-5 | Medium | Admin script default password | **Fixed in code, production role not checked** | Script refuses without confirmation and a 20+ character password (checked on a local database) |
| M-6 | Medium | No CI for backend | **Fixed** | Backend workflow green on GitHub |
| M-7 | Medium | Older production tables may lack unique constraints | **Open** | Needs a read-only production query (not run) |
| L-1 | Low | PyJWT advisories | **Fixed** | `pip-audit --strict`: no known vulnerabilities |
| L-2 | Low | Account deletion heavy and not transactional | **Fixed** | Suite: deletion removes all owned tables; failure keeps everything |
| L-3 | Low | No readiness check | **Fixed** | Live: `/healthz` → 200 `{"status":"ok"}`, no internal detail |
| L-4 | Low | No pool/timeouts | **Fixed** | Suite: statement timeout set on connections; slow query cancelled |
| L-5 | Low | Ambiguous status codes | **Fixed** | Suite: 409 / 503 / 500 mapping with no leaked details |
| L-6 | Low | No email verification; sign-up reveals registration | **Open** | Code |
| L-7 | Low | Silent coercion of currency and quantity; rounding | **Open** | App-side; not re-verified |
| L-8 | Low | Recurring source id uses local time | **Open** | App-side design |
| L-9 | Low | Unbounded growth (notification metadata, period keys, tombstones) | **Open** | Code |
| L-10 | Low | Python version not pinned on Render | **Open** | `render.yaml` |
| L-11 | Low | Unused REST routes still mounted | **Open** | Code: `main.py` includes all routers |
| L-12 | Low | 7-day tokens, no "sign out everywhere", deletion without password | **Open** | Live: account delete with a valid token → 204, old token → 401 (works); no re-authentication |

---

## 3. The two bypasses you asked me to recheck

### 3.1 X-Forwarded-For rate-limit bypass (P-1)

Re-run live with production-like settings. Limit: 5 wrong passwords per address per 15 min;
20 per email per hour.

| Case | Headers sent | Result |
| --- | --- | --- |
| **A. No `True-Client-IP`** (the default when the edge does not set it) | rotating forged `X-Forwarded-For` | **12 × 401, 0 × 429. Bypass confirmed.** |
| **B. `True-Client-IP` present** (simulates the Cloudflare edge overwriting it) | rotating forged `X-Forwarded-For` | **5 × 401, 7 × 429.** Per-address limit holds |

What this means:
- The client address is taken from `True-Client-IP` first, and then from the left-most
  `X-Forwarded-For` entry. The left-most entry is client-controlled. With `TRUSTED_PROXY_HOPS`
  at its default of 0, case A applies whenever the request arrives without `True-Client-IP`.
- **P-1 is therefore fixed only if Render's edge always sets `True-Client-IP` on this service.**
  That is the basis of the third-party demo I cited earlier. Render's own documentation was
  not confirmed, and the production behaviour is **not verified**. I did not test Render itself.
- The per-email limit still holds in case A (20 per hour per email), so a forged address
  bounds guessing to that ceiling. It does not stop it.

**Required before launch:** a single request to the production service with a made-up
`X-Forwarded-For`, then check the logged `ip`; set `TRUSTED_PROXY_HOPS` if needed. This needs
production access and your approval (§5.1 of the readiness plan).

### 3.2 Concurrent login-attempt bypass (P-2)

| Case | Result |
| --- | --- |
| 20 simultaneous guesses, one address, one email | 5 × 401, 15 × 429 |
| 40 simultaneous guesses, 40 addresses, one email | 20 × 401, 20 × 429 (the per-email ceiling, exact) |

**Fixed and retested live.** The count happens before the password is checked, and the
account's failure counter is one atomic database update.

### 3.3 Residual: a stranger can block the owner (P-9)

Live: after 25 forged-address guesses on one email, the owner's correct password from a fresh
address returned **429**. Two mechanisms are involved: the account lock after 20 consecutive
failures (15 minutes by configuration), and the per-email ceiling (20 per hour). I did not
measure how long the owner stayed blocked; the configured windows are the expected upper bound.

This is the documented trade-off. It is **open**, and a decision is needed: accept it, or use
a progressive delay or email-code verification after N failures (readiness plan §7.3).

---

## 4. Verified protections, and what is implemented but not verified

### 4.1 Verified (live or suite, this report)

| Area | Evidence |
| --- | --- |
| Token forgery | Live: wrong key → 401, `alg: none` → 401. Suite: edited payload, HS512, missing `exp`, expired, wrong version |
| Account isolation (BOLA) | Live: another user's id with my token → 404 on GET, PATCH and DELETE, and their row unchanged. Suite: row security and API tests |
| Function-level auth | Suite: every route except the 7 public ones refuses requests without a token |
| Mass assignment | Suite: `id`, `user_id`, `token_version`, `wrapped_key` and similar are ignored |
| SQL injection | Earlier live test: 6 payloads in 10 fields, stored literally, no timing effect. Suite: parameters bound throughout |
| Security headers | Live: HSTS, `nosniff`, `DENY`, `no-store`, CSP present; no `Server` header |
| Docs and CORS | Live: `/docs` and `/openapi.json` → 404; CORS not enabled without `CORS_ORIGINS` (an evil origin gets no `Access-Control-Allow-Origin`) |
| Key upgrade switch | Live: rewrap with the switch unset → 403 `key_upgrade_not_allowed`. Suite: 26 tests, including that the password is not read |
| Data-key race | Live (see §2, P-3) |
| Account deletion | Live: 204, old token 401. Suite: owned rows removed, failure keeps everything |
| Encrypted sync contents | Suite and earlier: private text sealed by the client; server stores `enc1:` values; deleted rows lose private text |
| Backup file format | Suite: round-trip, wrong passphrase, tampered ciphertext and header, lowered iterations, unknown format and version, size limit |
| Compatibility fixtures | Suite: wraps and a backup file made by an independent Python implementation open through Dart and native paths |
| Native PBKDF2 | Real devices: Samsung S23 Ultra (3 runs), Galaxy A56 (4 runs), Xiaomi 2404ARN45A (3 runs), Infinix GT 20 Pro (2 runs). All 15 shared vectors match on every run; self-test passed. Simulator: Xcode 26 XCTest passed |
| Rate limits (non-login) | Suite: sign-up, reset, forgot, sync and rewrap limits |

### 4.2 Implemented but not verified in its real environment

| Item | What is missing |
| --- | --- |
| Client-address handling on Render | Whether the edge sets `True-Client-IP` for this service (P-1) |
| Android backup exclusion | On-device `bmgr` backup check; a phone-to-phone transfer. The rules are only checked as text |
| Encrypted backup save and restore on a phone | Only the Dart logic is tested; the file picker and share flow are not run on a phone |
| iOS native PBKDF2 | Simulator only; no iPhone |
| Native key derivation at launch scale | Four phones; the low-end Android is 3 runs; the older A53-class phone is not yet tested |
| Migration of `key_upgrade` (Release B) | Not built; only the switch exists |
| The release APK's signature | Not checked (no release key verification yet, deferred) |
| CORS with an allowed origin | Only the off-by-default case was tested |
| Render restarts, rolling deploys, several instances | The rate limits and the sync lock are in memory; only one instance is assumed |

---

## 5. Remaining vulnerabilities, risks and deferred work

### 5.1 Remaining vulnerabilities (open)

| Priority | ID | Item | Phase |
| --- | --- | --- | --- |
| Critical | C-1 | Production database backups and a restore drill | P1 (launch blocker) |
| High | P-1 | Confirm `True-Client-IP` on the production service; set `TRUSTED_PROXY_HOPS` if not | P1 |
| High | H-3 | Rotate the Google OAuth client (history) | Now, by you |
| High | N-3 | Release signing key and verification before the first public APK | P1 |
| Medium | P-9 | Owner lockout by a stranger; decide on delay or email-code design | Decision needed |
| Medium | P-12 | Wrapped data key returned to any valid token | Release B (the key is not released) |
| Medium | M-5 | Production `waffr_admin` password and external access | P1 (manual check) |
| Medium | M-7 | Production unique constraints | P1 (read-only query) |
| Medium | P-11 | Device-level backup exclusion not verified | Before Release A |
| Low | L-6, L-7, L-8, L-9, L-10, L-11, L-12 | As listed in §2 | Later |

### 5.2 Risks not captured above

- **Dependencies in Dart are not audited.** The vulnerability database was blocked from this
  environment. Run `flutter pub outdated` and an OSV scan on a connected machine before launch.
- **Single instance assumptions.** Rate limits, the sync lock and the native key self-test
  are per process. A second instance weakens the limits (documented in the code).
- **No independent review.** Every "fixed" item was written and tested by the same process
  that wrote the fix. Before launch, a second reviewer should look at the auth routes,
  `client_address.py`, the sync merge and the Kotlin/Swift PBKDF2 code.
- **Public APK distribution has no update path yet** until N-3 is done (a debug or different
  key blocks in-place updates).

### 5.3 Deferred security work (by phase)

- **Now (P0, no production):**
  - Confirm the single-process assumption in the test environment.
  - Finish device tests: the older Cortex-A53-class phone (3 runs), GT 20 Pro run 3, and the
    on-device backup checks.
  - Optional: an independent code review of the items in §5.2.
- **P1 (launch preparation):** C-1, the release key and its verification, the domain and the
  update link, the production read-only checks (M-5, M-7, H-3 rotation, P-1 header check), and
  the decision on P-9.
- **P2–P3:** Release A publication with approval; Release B with the 90-day guard, the rollout
  stages, and the recovery procedures described in the readiness plan.

---

## 6. Bottom line

- **Verified and holding:** authentication, account isolation, injection and mass-assignment
  resistance, error handling, the sync races, the login counters, and the key-upgrade switch,
  all re-checked on a running server, along with the 481-test suite.
- **Not yet proven:** that the production service sets the client-address header the limits
  depend on (P-1); on-device backup behaviour; iOS.
- **Not safe to publish today:** the production database has no backups (C-1), the signing key
  is not yet set up for updates (N-3), and the client-address question in P-1 is open.
