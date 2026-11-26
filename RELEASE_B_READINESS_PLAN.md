# Release B readiness plan: raising the key-derivation count safely

Date: 2026-11-26. Status: **plan only, waiting for your approval.** No code, iteration
count, production setting, merge or deployment has changed.

Builds on `NATIVE_PBKDF2_PLAN.md` (§9) and `KDF_BENCHMARK.md`. Release A (native PBKDF2 at
210,000) is on the branch and **not yet released to users**. Release B means: new wraps use
600,000 (or the count the benchmarks support), and existing accounts are upgraded in the
background at sign-in.

## 1. What the inspection found

| # | Finding | Where | Consequence for the plan |
| --- | --- | --- | --- |
| F-1 | **The server never learns the app version.** Requests carry only `Content-Type` and `Authorization`. | `auth_session.dart` (6 call sites), `sync_service.dart:302` (1); the anonymous news feed is a separate call | A version guard needs a new header. Apps that do not send it are "unknown", which is the signal for old versions. |
| F-2 | **Release A has not shipped**, so the header can still go into it. | branch state | The cheapest moment to add the signal is **before** Release A is released. After that, apps in the wild without it are indistinguishable from pre-A apps. |
| F-3 | The server has **no device concept**. A token belongs to the account (`sub`, `ver`), not to a device. | `auth.py:create_access_token` | "Which versions does this account use?" needs a small new record per install. |
| F-4 | Tokens last **7 days** and are never refreshed. After that a request gets 401 and the app signs in again **with the password**. | `auth.py:47`, `auth_session.dart:ensureToken` | An upgrade needs the password, so it can only run at a password sign-in. An active user is reached within about a week. |
| F-5 | `GET /auth/me` runs at **every sync start**. | `auth_session.dart:ensureToken` → `_getMe` | It is the natural carrier for "you may upgrade" and for refreshing last-seen data, at no extra request. |
| F-6 | **`POST /auth/key/rewrap` is ungated.** It checks the password and compare-and-swap, never lowers the count, and signs nobody out, but has no flag and no version check. | `backend/main.py:rewrap_data_key` | If the branch's backend is deployed as it is, any user with a custom client could upgrade their own wrap. Nothing in the shipped app calls it, and it only affects their own account. Still, it contradicts "no upgrades until approved". **Gate it (flag, default off) before the next backend deploy** (§9, M-0). |
| F-7 | An **old app reads the stored iteration count**, with no cap, and unwraps any count in pure Dart. | `data_key.dart:fromJson`, `unwrap` | **Correct but slow.** An old app can never be locked out by an upgraded wrap; the worst case is a slow sign-in (S23 Ultra, pure Dart at 600,000: 3.4–13.6 s; low-end phones are probably several times slower, an estimate). |
| F-8 | Under Release A, **new wraps and new backup files are derived by the Dart code**, even where native is available. | `Pbkdf2Engine.deriveForWriting` | At 600,000, sign-up, password change and **backup saving** would take the Dart time (S23: 3.4 s typical, one run 13.6 s). See D-4. |
| F-9 | The backup file format is **independent of the wrap**: own passphrase, own stored iterations (600,000 already for new files), format `waffr-backup` v1. The backup feature does not exist in any released app. | `ledger_backup_codec.dart` | Release B cannot break existing backups. It only touches speed (F-8). |
| F-10 | **How the app is distributed is not visible in the repo.** There is no Play Store or App Store reference, only a CI workflow that builds APKs. | repo | Store dashboards may not exist or may not cover all installs. **Server-side measurement must be the primary adoption source** (§4). Question Q-1. |
| F-11 | Any new account-owned table must have a row-security policy and be added to `ACCOUNT_DELETE_ORDER`, or startup refuses to run. | `row_security.py`, `main.py` | Part of the exact change list (§8). |
| F-12 | Only a 401 signs a device out. A 403, 409 or 503 from the new routes never does. | `auth_session.dart`, `sync_service.dart` | The guard can refuse with a 403 without affecting any session. |

### 1.1 What an upgraded wrap does to each app version

| App on the device | Wrap at 210,000 | Wrap at 600,000 |
| --- | --- | --- |
| Before Release A (pure Dart) | works, as today | **works, slow sign-in** (F-7). No data loss, no forced sign-out |
| Release A (native for reading) | works, faster | works, fast (S23: 275 ms) |
| Release B | works; upgrades it when eligible | works |
| Existing encrypted rows | readable (same data key) | readable (same data key) |
| Backup files | independent (F-9) | independent |

The data key itself never changes. Only the box around it does. So the risk of Release B is
**speed on old apps and a bad write**, not lost access by design. The guard and the
recovery steps below address both.

## 2. Design principles

1. **The server decides eligibility; the app only asks.** An app cannot talk the server into
   an upgrade it should refuse.
2. **Unknown means old.** A request without the version header counts as a legacy app.
3. **Never write a wrap that a Dart-only app cannot open.** Dual-implementation agreement
   stays (see D-4 for the budget).
4. **The old wrap stays until the new one is stored**, and the swap is compare-and-swap.
5. **Everything additive and reversible by a flag**: no schema change that old apps can see,
   no change to `token_version`, no change to token format.
6. **Never block sign-in** because of an upgrade problem.

## 3. Server-side version guard

### 3.1 The client signal (small additive change in Release A, before it ships)

- Header on **every** API request: `X-Waffr-Client: <platform>/<version>+<build>/<install-id>`,
  for example `android/2.16.0+18/3f9c…`.
  - `build` is the pubspec build number (Android `versionCode`, iOS `CFBundleVersion`).
  - `install-id` is a random UUID made on first start, stored in plain prefs (not secure
    storage), **not** a hardware or advertising identifier, deleted on a data reset.
- The app reads its version through the existing native `info` call (Android
  `Pbkdf2Channel.info`, iOS `Pbkdf2Channel.info`, both already return `app_version`), so
  **no new dependency**. If it cannot, it sends no header, which the server reads as legacy.
- One place builds the header: a small `ApiClient` helper replacing the 7 call sites, so
  none can forget it.
- The server parses the header leniently. A malformed or oversized value is treated as
  missing; **a bad header never fails a request**.

### 3.2 What the server records

New table `client_installs` (additive; old apps never see it):

| Column | Meaning |
| --- | --- |
| `user_id` (FK, `ON DELETE CASCADE`) | owner |
| `install_id` (text, 36) | from the header |
| `platform` (`android` / `ios`) | from the header |
| `build` (int) | from the header |
| `first_seen_at`, `last_seen_at` | UTC |
| unique `(user_id, install_id)` | |

Plus one column `users.legacy_seen_at` (nullable timestamp): the last time an
**authenticated request without a valid header** came from this account.

- Written **at most once per 6 hours per (user, install)** from an in-memory throttle, on
  login, register, `/auth/me`, and `/sync`, through a short background session (the pattern
  `password_reset.email_code` already uses). **No extra latency and no write on every sync.**
- Pruned after 120 days. Deleted with the account (cascade, and added to
  `ACCOUNT_DELETE_ORDER` and `row_security.OWNED_TABLES`, F-11).
- No device model, no IP, no name: only what the guard needs.

### 3.3 Eligibility rule (computed on the server only)

An account may be upgraded **only if all of these hold**:

1. `KEY_UPGRADE_ENABLED` is on and the account is in the rollout cohort (§5).
2. The **current request** carries a header with `build ≥ MIN_UPGRADE_BUILD[platform]`
   (Release B's build, or Release A's if you decide the A-only upgrade is allowed; Q-3).
3. **Guard window:** in the last `GUARD_WINDOW_DAYS` (default **90**), the account has
   `legacy_seen_at` null **and** every `client_installs` row seen in that window has
   `build ≥ MIN_GUARD_BUILD[platform]` (Release A's build).
4. The stored wrap is below the target count, and the new wrap's count is at least the
   target and at least the stored count (already enforced).
5. The wrap is not being changed by someone else (compare-and-swap, already enforced).

### 3.4 API changes (all additive; old apps ignore them)

| Route | Change |
| --- | --- |
| `GET /auth/me` | adds `key_upgrade: {"target_iterations": N}` **only when eligible**, otherwise omitted. Old apps ignore unknown fields (they read named keys). |
| `POST /auth/key/rewrap` | re-checks eligibility (the authoritative check) and answers **403 `{"detail":"key_upgrade_not_allowed"}`** otherwise. Everything else unchanged. |
| `POST /auth/login`, `/auth/register`, `/sync` | record the client header (throttled). No behaviour change. |

### 3.5 What the guard cannot know (honest limits)

- A phone with an **old app that has not been opened for 90 days** is invisible. If its
  owner opens it later, they get a slow but working sign-in (F-7). Measured afterwards
  (§4.4), not prevented.
- A phone on a **new app that never talks to the server** is simply not counted.
- The window trades safety against coverage: a longer window protects more dormant phones
  but delays upgrading accounts that once used an old app (Q-4).

## 4. Measuring Release A adoption

### 4.1 Primary source: the server

From §3.2, one read-only view (added to `backend/sql/admin_readonly.sql`, **aggregates
only, no emails or ids**) gives:

- **Active installs by platform and build**, last 30 days (an install is "active" if seen
  in the window).
- **Adoption** = active installs on a build ≥ Release A, divided by all active installs
  (counting header-less activity as legacy, by account).
- **Accounts passing the guard** (§3.3, rule 3) as a count and a percentage: the number
  that decides how many accounts *can* be upgraded.
- **Dormant risk:** accounts whose latest legacy sighting is 60–90 days old.

It works for every channel (store, CI-built APK, TestFlight), and Android and iOS alike.

### 4.2 Cross-checks (only if they exist for you, F-10)

- Google Play Console → *Statistics* → installs by app version.
- App Store Connect → *App Analytics* → sessions or active devices by version.
- Neither is needed for the decision, and neither sees APKs installed from CI.

### 4.3 Adoption thresholds

| Level | Rule | Used for |
| --- | --- | --- |
| Start of any Release B upgrade | **≥ 95% of active installs** on Release A+ **and** **≥ 85% of active accounts passing the guard**, both held for **30 days** | go / no-go |
| Widening the cohort | the per-stage gates in §5 | stage progress |

95% and 30 days are my proposal from the earlier plan; the guard makes the exact figure less
critical, because an account is only upgraded when **its own** devices pass. See D-3.

### 4.4 Measuring the damage the guard cannot prevent

On `rewrap`, record `rewrapped_at` on the install row. If a legacy sighting
(`legacy_seen_at`) appears **after** a rewrap, log `legacy_after_upgrade` (count only).
That number is the real-world rate of "old phone meets upgraded wrap". If it passes **0.5% of
upgraded accounts**, pause the rollout (§5).

## 5. Gradual rollout

Percentages use `hash(user_id) mod 100 < KEY_UPGRADE_PERCENT`, so a user's cohort never
changes between requests.

| Stage | What is on | Entry gate | Bake time | Exit gate |
| --- | --- | --- | --- | --- |
| **0. Release A out** | app header and install id; nothing else | Release A criteria (§7.1) met; header present in the build | until the adoption threshold | §4.3 |
| **1. Server dark** | table, ingestion, view, guard code; `KEY_UPGRADE_ENABLED=false`. **Shadow mode** logs `would_allow` / `would_refuse` per request | Stage 0 deployed; M-0 gate in place | 14 days | `would_allow` share matches §4.1 within 2 points; no write errors; no added latency (p95 change < 5 ms) |
| **2. Release B app out** | app can upgrade when `/auth/me` says so; server still off | Release B criteria (§7.2); device benchmark gate | until ≥ 90% of installs on B | |
| **3. Allowlist** | your own accounts only, then a few volunteers | | 7 days (one token lifetime) | every upgraded account signs in on every device it owns; zero `unwrap_failed` |
| **4. 1%, 5%, 25%, 100%** | `KEY_UPGRADE_PERCENT` | previous stage met | 7 days each | **0** unwrap failures; rewrap success ≥ 99% of attempts (excluding 403 and 409); `legacy_after_upgrade` < 0.5%; no rise in 401 or sync errors beyond ±0.5 points; sign-in p95 not worse than today |

**Controls (each is a production setting, so each needs your approval, Q-6):**

- `KEY_UPGRADE_ENABLED` (kill switch), `KEY_UPGRADE_PERCENT`, `KEY_UPGRADE_ALLOWLIST`,
  `KEY_UPGRADE_TARGET_ITERATIONS`, `GUARD_WINDOW_DAYS`, `MIN_GUARD_BUILD_*`,
  `MIN_UPGRADE_BUILD_*`.
- Changing an environment variable restarts the Render service (seconds to a minute of
  downtime on the Free plan; none on paid plans with a rolling deploy). If you need an instant
  switch, the alternative is one row in a settings table (more code; D-6).

**Pause rule:** any unwrap failure, or crossing a gate limit, stops widening. Setting the
percent back to 0 stops new upgrades the same minute and **does not touch already upgraded
accounts**, which stay valid.

## 6. The upgrade procedure, interruptions, rollback, recovery

### 6.1 Client sequence (Release B), at a password sign-in only

```
sign in → /auth/me says key_upgrade.target_iterations = N          (else stop)
          wrapped = server wrap W_old at N_old < N
          K = unwrap(password, W_old)                                (existing, native + Dart fallback)
          device must be able: native self-test passed, and a native known-answer test at N passed
          derive KEK_native(N, new salt); seal K → W_new
          (1) round trip: open W_new with KEK_native → equals K
          (2) cross-check: KEK_dart(N, same salt) equals KEK_native    (budgeted, D-4)
          POST /auth/key/rewrap {password, expected_wrapped_key = W_old, data_key = W_new}
            200 → verify: fetch /auth/me, open the stored wrap → equals K; done
            409 → re-read /auth/me; nothing to do if already ≥ N
            403/400/429/503/network → stop; retry at the next sign-in
  never blocks or fails the sign-in
```

### 6.2 What happens if it is interrupted

| Interrupted at | State | Recovery |
| --- | --- | --- |
| Before the request | server holds W_old | nothing; retried at the next sign-in |
| Request sent, reply lost | server holds W_new **or** W_old, both open to K | the next sign-in reads the stored count and opens whichever is stored |
| After 200, before the app's verify | server holds W_new (checked on the device before sending) | the next sign-in opens it; a failure there is the bad-write case below |
| Two devices upgrade at once | compare-and-swap: one 200, one 409 | the loser re-reads and stops |
| Password changed meanwhile | the swap fails (password hash is part of the condition) | none needed |
| App killed mid-derivation | nothing sent | retried |

### 6.3 Rollback (the rollout)

- **Stop:** `KEY_UPGRADE_ENABLED=false` (or percent 0). No new upgrades; no account changes.
- **Revert the app default:** if Release B's app is found faulty, ship a build with
  `defaultIterations` back at 210,000. Wraps already at 600,000 keep working on every
  version (F-7), so **no data rollback is needed**.
- **Downgrading an account's wrap is not provided** (the server refuses a weaker wrap on
  purpose). If one account must be brought back to 210,000, it is a one-off operation with
  your approval (Q-7), not a route.

### 6.4 Recovery (a bad or unreadable wrap)

The only way an account loses access is a wrap that does not open to the real data key.
Layered defences:

1. **Prevention:** the round trip and Dart cross-check before the upload, and the
   compare-and-swap keeping W_old until the swap (§6.1).
2. **Detection:** the post-upload verify, and a counter `unwrap_failed` at every sign-in
   (counts only).
3. **Self-heal (new, Release B):** if a password sign-in succeeds on the server but the
   stored wrap does not open, and **this device still holds the account's data key** in secure
   storage, the app proves the key is right by opening one sealed `enc1:` value from the
   sync reply, then **re-wraps it with the password and replaces the server wrap** through the
   same route, using the broken wrap as `expected_wrapped_key`. This fixes the bad-wrap
   case on any device that still has the key. It needs one server allowance: the route
   accepts a rewrap **without raising the count** when the request carries
   `repair: true` and the password check passes.
4. **Backup file:** the user's encrypted export (`waffr-backup`) restores the ledger if
   every device has lost the key.
5. **Last resort:** the existing password-reset path (server drops the wrap and blanks the
   sealed text; the next sign-in makes a new key and the device's local data repopulates it).
6. **Database restore:** if a bad write ever reached many rows, only a database backup can
   undo it, and **the production database has no backup today (C-1).** This must be fixed
   before Release B (§7.1).

## 7. Release criteria and security checks

### 7.1 Before Release A is released

- [ ] Header and install id added, built on the existing `info` call, with tests (§8).
- [ ] The benchmark gate for Release A: `self_test_passed` and `vectors_all_match` on at least
      **three Android phones** (S23 Ultra done) **and one iPhone**, with no mismatch.
- [ ] C-1 closed: **the production database has a backup and a tested restore.**
- [ ] M-0 done: the rewrap route is flag-gated, default off (§9).
- [ ] Release A's build number is recorded as `MIN_GUARD_BUILD` for each platform.

### 7.2 Before Release B's app is released

- [ ] **Device gate** (unchanged): at least 3 Android phones including a low-end one, plus an
      older iPhone; three runs each; native worst run ≤ 2.0 s at the proposed count.
      If 600,000 fails anywhere, propose the highest count that passes everywhere.
- [ ] All tests in §8 pass, including interruption and mixed-version cases.
- [ ] The server guard has run in shadow mode for 14 days (Stage 1) with the §5 exit gate met.
- [ ] Self-heal (§6.4) works against a deliberately broken wrap on a test account.
- [ ] A restore drill from the database backup has been done.

### 7.3 Security checks before enabling the server flag

- [ ] A cross-account test: an account cannot learn another account's eligibility or
      version data; row-security policy on `client_installs`; deleted with the account.
- [ ] The header cannot be used to **gain** an upgrade: a forged "new" build only affects the
      caller's own account (the upgrade also needs the password and a wrap the caller can
      open), and rule 3 still demands no legacy sightings.
- [ ] The guard fails **closed**: any error computing eligibility means "not eligible".
- [ ] No new secret, token change, or log of the header contents beyond counts.
- [ ] Rate limits cover the new paths (rewrap: 5 an hour already; ingestion is throttled).
- [ ] `bandit`, `pip-audit`, the backend suite, and the Flutter suite are green; a regression
      test proves old clients (no header) still log in, sync, change passwords and delete
      accounts unchanged.
- [ ] A staged dry run: on a **copy** of the schema (never production), run the migration
      twice and confirm it is idempotent and that the table and policy exist.

## 8. Exact changes required (no code written yet)

### 8.1 Addendum to Release A (before it ships)

| File | Change |
| --- | --- |
| `lib/core/net/api_client.dart` (new) | one helper that adds `Content-Type`, `Authorization` and `X-Waffr-Client`; replaces the raw `http` calls |
| `lib/core/net/client_identity.dart` (new) | version and build via the native `info` call; install id in prefs |
| `lib/core/sync/auth_session.dart`, `sync_service.dart` | use the helper (7 call sites) |
| `lib/data/services/local_data_reset.dart` | clear the install id on reset |
| `test/core/net/*` (new) | header format; missing `info`; no header on the news feed; reset clears the id |
| docs | `lib/core/sync/README.md`, `SECURITY.md` |

### 8.2 Release B: server

| File | Change |
| --- | --- |
| `backend/main.py` | gate `rewrap_data_key` with the flag and eligibility; add `key_upgrade` to `/auth/me`; add the `repair` allowance |
| `backend/key_upgrade.py` (new) | config from the environment, cohort hash, eligibility, fail-closed |
| `backend/client_versions.py` (new) | header parser, throttled background recorder, retention |
| `backend/models.py` | `ClientInstall` model; `User.legacy_seen_at` |
| `backend/database.py` | additive migration: table, unique index, column (idempotent, `IF NOT EXISTS`) |
| `backend/row_security.py` | add `client_installs` to `OWNED_TABLES` |
| `backend/main.py` | add it to `ACCOUNT_DELETE_ORDER` |
| `backend/auth.py` | `get_current_user` calls the throttled recorder |
| `backend/sql/admin_readonly.sql` | aggregate-only adoption view |
| `backend/tests/test_key_upgrade_guard.py` (new) | every §3.3 rule, shadow mode, kill switch, cohort stability, fail-closed |
| `backend/tests/test_client_versions.py` (new) | parsing, throttling, retention, cascade, row security, no-header legacy path |
| `backend/tests/test_data_key_rewrap.py` | flag off by default; 403 when ineligible |
| `.github/workflows/backend.yml` | unchanged |
| `SECURITY.md`, `backend/README.md`, `backend/routers/README.md` | settings table, guard, runbook |

### 8.3 Release B: app

| File | Change |
| --- | --- |
| `lib/core/security/data_key.dart` | `defaultIterations` to the approved count; read-side unchanged |
| `lib/core/security/pbkdf2.dart` | a native known-answer check at the target count; the write path decided in D-4 |
| `lib/core/sync/key_upgrade.dart` (new) | the §6.1 sequence, retry rules, never blocking sign-in |
| `lib/core/sync/auth_session.dart` | call it after `_unlockDataKey`; self-heal on unwrap failure (§6.4) |
| `lib/core/security/ledger_backup_codec.dart` | follow the D-4 decision for writes |
| `test/core/sync/key_upgrade_test.dart` (new) | success, 403, 409, 400, 429, 503, network loss; native/Dart mismatch; round-trip mismatch; interrupted after the server swap; repeated sign-ins; old (Dart-only) app opens a 600,000 wrap; sign-in succeeds when every step fails |
| `test/core/security/self_heal_test.dart` (new) | broken wrap with and without a local key; a wrong local key is refused |
| `tool/kdf_benchmark.dart` | report adds the Dart cross-check time at the target count |
| `KDF_BENCHMARK.md`, `NATIVE_PBKDF2_PLAN.md`, `CLIENT_SECURITY_DECISIONS.md` | status |

### 8.4 Tests that cover the mixed fleet

- Old client (no header) × Release-B server: login, sync, password change, delete account,
  key fetch: **unchanged behaviour**.
- Old client with an account already at 600,000: unwrap succeeds (Dart); a test with an
  intentionally slow engine confirms there is **no timeout on unwrap**.
- A header with a forged high build and a legacy sighting in the window: **refused**.
- Shadow mode: no wrap ever changes.
- Flag off after upgrades: already-upgraded accounts still sign in.

## 9. Before any merge or deployment of the current branch

| ID | Item | Why |
| --- | --- | --- |
| **M-0** | Gate `POST /auth/key/rewrap` behind `KEY_UPGRADE_ENABLED` (default **off**) and return 403 when off. This is a few lines and a test. | F-6: otherwise deploying the branch enables self-upgrades before the guard exists |
| M-1 | Add the header and install id to Release A (§8.1) | F-1, F-2 |
| M-2 | Close C-1 (database backup) | recovery layer 6 |

M-0 changes the key-upgrade behaviour on the server, so it is one of the changes you asked
me to hold. It is the **only** thing I would change before merging, and I need your word to
do it (Q-2).

## 10. Risks

| Risk | Impact | Likelihood | Mitigation |
| --- | --- | --- | --- |
| Old app meets an upgraded wrap | slow sign-in (never lockout) | low with the guard; the dormant-phone tail remains | guard window; `legacy_after_upgrade` metric; pause threshold; support note |
| Bad wrap written | possible loss of access on that account | very low | round trip, Dart cross-check, compare-and-swap, self-heal, backup file, database backup |
| Dart cross-check never completes on the slowest phones | those phones do not upgrade | medium on very low-end | a different device of the same account can upgrade it; accepted (D-4) |
| Native write path (if allowed) has an input-dependent bug | wrong key written | very low | known-answer test at the target count; the 15 vectors; dual check on rewrap |
| Header spoofing | none that grants anything | n/a | server decides; the guard fails closed |
| New table or throttle adds load | latency | low | throttled background writes; shadow-mode measurement |
| Release A adoption stalls | Release B delayed | medium (distribution unknown) | the server measures it; forced-update message is a separate decision (Q-5) |
| Env var change restarts Render | brief downtime | certain, small | schedule it; D-6 alternative |
| Backup saving slow at 600,000 via Dart | slow save on low-end | medium | D-4 |

## 11. Decisions requiring your approval

| # | Decision | Recommendation |
| --- | --- | --- |
| **D-1** | Add the client header and install id to **Release A** before it ships (§3.1, §8.1) | **Yes.** It is the only way to tell Release A apps from older ones. Without it, the guard cannot work and adoption cannot be measured server-side |
| **D-2** | Add the `client_installs` table, `users.legacy_seen_at` and the throttled recorder (§3.2). Additive schema change | **Yes**, deployed dark (Stage 1) with the flag off |
| **D-3** | Adoption threshold: **≥ 95% of active installs on Release A+ and ≥ 85% of accounts passing the guard, held 30 days**, before any upgrade | **Yes** as written. It can be made stricter, not looser, without losing the guard's protection |
| **D-4** | The write path at 600,000 and the cross-check budget. **(a)** keep Dart writes, verified against native (slow on low-end: seconds to ~15 s for sign-up, password change and backup saving). **(b)** native writes behind a known-answer test at the target count. **(c)** (b) for sign-up, password change and backup files, but the **rewrap** keeps the Dart cross-check, with a 90-second budget | **(c).** Keeps the strictest check where an existing good wrap is replaced, and avoids long waits elsewhere |
| **D-5** | Guard window **90 days** and the 0.5% `legacy_after_upgrade` pause threshold | **90 days** (3× the 30-day activity window and about 13 token lifetimes) |
| **D-6** | The kill switch as an **environment variable** (restart on change) or a **settings row** (instant, more code) | **Environment variable** at first; revisit if you want instant control |
| **D-7** | Self-heal with a `repair` rewrap (§6.4) | **Yes.** It is the best recovery for the one failure that can lose access |

### Questions I need answered

- **Q-1.** How is the app distributed: Google Play, the App Store or TestFlight, APKs from CI,
  or a mix? That decides whether store dashboards can cross-check §4.
- **Q-2.** May I do **M-0** (flag-gate the rewrap route, default off) before the branch is
  merged or deployed? It is the one server key-upgrade change needed to make a deploy safe.
- **Q-3.** Which app versions must a device be on before it may **start** an upgrade, and which
  versions may the account's **other** devices be on? I recommend: the upgrading device must run
  **Release B or later** (it is the one that writes the wrap), and every other device seen in the
  guard window must run **Release A or later** (Release A can already read any count, it just
  never writes one). That is the rule in §3.3.
- **Q-4.** Is a 90-day guard window acceptable, given it delays accounts that used an old app
  within that time?
- **Q-5.** If Release A adoption stalls, may a later release show a soft "please update" notice?
  (Separate decision; nothing here forces updates.)
- **Q-6.** Who changes production settings and when? Each stage in §5 needs a setting changed
  and your explicit go-ahead.
- **Q-7.** Is a one-off downgrade of a single account's wrap (with your approval each time) an
  acceptable emergency tool, instead of a route?

## 12. What happens next

1. You answer the questions and approve D-1 to D-7 (or change them).
2. I make the **Release A addendum** (§8.1) and, with Q-2, **M-0** — still not merging or deploying.
3. Release A is built and checked on devices (more S23 runs, a low-end Android, an older iPhone).
4. Only after Release A is out and adoption is measured (§4) do I write the server part
   (§8.2) and deploy it dark; Release B's app (§8.3) comes after the Stage 1 exit gate.

Nothing in this plan starts without your explicit approval.
