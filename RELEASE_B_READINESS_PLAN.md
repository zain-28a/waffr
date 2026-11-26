# Release B readiness plan: raising the key-derivation count safely

Date: 2026-11-26. Status: **updated for a public launch planned for early 2027 (§0A).
Nothing is published. Release B has not started.** The only code change in this phase is the
rewrap switch (M-0): off by default, tested, **not merged or deployed**. No iteration count,
production setting, merge, deployment or public release has changed.

Builds on `NATIVE_PBKDF2_PLAN.md` (§9) and `KDF_BENCHMARK.md`. Release A and Release B are defined
exactly in §0A. In short: Release A is the client build with native PBKDF2 at the **existing**
210,000 iterations; Release B raises the count and upgrades existing accounts. **Neither is
published, and Release A is not to be published before the launch-preparation phase.**

## 0. Approved decisions and the conditions that apply

| ID | Decision | Approved as | Conditions added by your answers |
| --- | --- | --- | --- |
| D-1 | Client header and install id in Release A | yes | the header is the **only** signal; no header means legacy |
| D-2 | `client_installs` table and old-app-seen column, deployed dark | yes | plus a `first_client_seen_at` column (§3.2) so the whole 90-day window must be observed |
| D-3 | Thresholds: ≥ 95% of active installs on Release A+, ≥ 85% of accounts passing the guard, held 30 days | yes | with APK distribution this may take long; **it is never lowered without your approval** (§4.3) |
| D-4 | Write path at the target count: option **(c)** | yes | native writes for sign-up, password change and backup files behind a known-answer test at the target count; the rewrap keeps the Dart cross-check with a 90-second budget |
| D-5 | 90-day guard window; pause at 0.5% `legacy_after_upgrade` | yes | the window **stays 90 days** (Q-4) |
| D-6 | Kill switch as an environment variable | yes | every change to it needs your explicit approval (§5.1) |
| D-7 | Self-heal with a repair rewrap | yes | as a **separate route behind its own switch**, with audit logging (§6.4), and the emergency tool in §6.5 |
| Q-1 | Distribution | **APK only** | no store dashboards; the server is the only adoption source (§4); updates are manual (§3.6, §10) |
| Q-2 | Gate the rewrap route behind a switch | **done** | `KEY_UPGRADE_ENABLED`, off unless set, 403 before the password is read, 26 tests (§9) |
| Q-3 | Which versions may start an upgrade | safest rule | never upgrade an account if an older installation may still need access (§3.3) |
| Q-4 | Guard window | **90 days** | kept |
| Q-5 | Soft update notice | **allowed** | non-blocking, dismissible, no server-supplied links (§3.6) |
| Q-6 | Production changes | **your explicit approval, every time** | change protocol in §5.1 |
| Q-7 | Emergency single-account recovery | allowed **only** with strict verification and audit logging | §6.5 |

## 0A. Phases, and exactly what Release A and Release B are

**The public launch is planned for early 2027.** The domain, the production server and the other
launch infrastructure are **not ready yet**. That is not a blocker for development and testing:
everything below that does not need them continues now, without touching production. The Render
service the app points at today is treated as a **development and test environment** until the
launch-preparation phase.

### 0A.1 Phases

| Phase | When | What happens | Production touched? |
| --- | --- | --- | --- |
| **P0. Development and testing** | now → launch preparation | device benchmarks, security testing on isolated local servers with synthetic data, building and testing the Release A addendum and, later, Release B code, test builds for testers (debug-signed, never public) | **No** |
| **P1. Launch preparation** | before launch, in 2026–early 2027 | buy the domain; build the production server; production database with backups and a restore drill; **final release-signing key and its verification (N-3)**; release workflow; final Arabic texts; set `UPDATE_PAGE_URL`; iOS decision | prepared here, each change approved (§5.1) |
| **P2. Public launch** | early 2027 | publish **Release A** as the first public client (or the launch baseline of L-1) | yes, with your explicit approval |
| **P3. After launch** | from launch on | server guard deployed dark; the 90-day observation clock starts; **Release B** rollout in the stages of §5 | yes, each step approved |

**§4 to §6 (adoption, rollout, recovery in production) describe P3.** None of it starts before
launch. The 90-day window cannot start before the production server is recording client
versions, so **no ordinary account can be upgraded earlier than about 90 days after launch**.

### 0A.2 What is blocked, and what is not

| Work | Needs the domain or production? | Phase | Authorised today |
| --- | --- | --- | --- |
| Device benchmarks (older Cortex-A53-class phone, GT 20 Pro run 3) | no | P0 | **yes** |
| Security testing on local, isolated servers with synthetic data | no | P0 | **yes** |
| The rewrap switch (M-0) | no | P0 | **done** |
| Release A addendum: header, install id, dormant notice (text only) | no (the URL constant stays empty) | P0 | approved in principle (D-1, N-2); **starts only when you say so** |
| Release B code: guard, upgrade flow, repair routes, tests | no (local and CI only) | P0 | **not authorised** (Release B has not started) |
| Server migration and guard in **production** | yes | P3 | no |
| `UPDATE_PAGE_URL` and a tappable notice | **yes: domain** | P1 | deferred |
| Support email address in the Arabic drafts | **yes: domain** | P1 | deferred |
| Final release signing key, fingerprint, release workflow, in-place rehearsal (N-3) | needs the final key and release process | P1 | deferred; **mandatory before the first public APK** |
| Production database backup and restore drill (C-1) | yes | P1 | deferred; **a launch blocker, not a present risk** (no real user data is in production) |
| iPhone benchmark and iOS guard configuration (N-5) | needs iOS distribution | when iOS is planned | deferred |
| Publishing any APK to the public | yes | P2 | **no** |

### 0A.3 Release A (defined)

**Release A is the first public client build. It does not change any key setting.**

| # | In scope | Status |
| --- | --- | --- |
| A-1 | Native PBKDF2 on Android (`javax.crypto` HMAC) and iOS (CommonCrypto) at the **existing 210,000** iterations; Dart fallback; runtime self-test; new wraps and backup files still written with the Dart key | **built and tested** on the branch; Android verified on 4 real phones; iOS verified on a simulator only |
| A-2 | Encrypted backup file, Android backup rules, deletion of the legacy plaintext password, cleanup of stale shared PDFs | **built**; Dart tests pass; on-device save/open/restore and a `bmgr` check are **still to do** |
| A-3 | Client header `X-Waffr-Client` and install id (D-1) | approved; **not started** |
| A-4 | Dormant soft-update notice, text only while `UPDATE_PAGE_URL` is empty (N-2) | approved; **not started** |
| A-5 | Server compatibility: `KEY_UPGRADE_ENABLED` rewrap switch, off by default (M-0) | **done** on the branch |

**Out of scope for Release A:** any change to an iteration count; any key upgrade; the version
guard and its tables; repair routes; recovery tooling; iOS distribution.

**Dependencies before it is published (all in P1):** the production server running the
branch's backend; C-1 (backups and restore drill); **N-3 signing-key verification**; the
domain, if you want a tappable notice (N-8); your approval of the Arabic texts (N-6); L-1 decided; on-device
backup checks (A-2); the A-3 and A-4 code built and tested.

**Done when:** every row above is built and tested, the §7.1 checklist is complete, and you
approve publishing it.

### 0A.4 Release B (defined)

**Release B raises the key-derivation count and upgrades existing accounts.**

| # | In scope |
| --- | --- |
| B-1 | `DataKeyStore.defaultIterations` raised to the count the device gate supports (**600,000 is supported by every Android run so far**, worst native 682 ms), with native writes behind a known-answer test (D-4 c) |
| B-2 | Server guard: `client_installs`, `users.first_client_seen_at` and `legacy_seen_at`, the eligibility rules of §3.3, shadow mode, cohorts, `KEY_UPGRADE_ENABLED` and the other controls |
| B-3 | Client upgrade flow of §6.1: dual-implementation check, compare-and-swap, never blocking sign-in |
| B-4 | Recovery: `repair-request` and `repair` routes behind `KEY_REPAIR_ENABLED`, self-heal, the audit table, the operator command, the owner emails |
| B-5 | `client_policy` in `/auth/me` for the soft notice |
| B-6 | The rollout controls and the change log of §5.1 |

**Out of scope for Release B:** iOS accounts until iOS is distributed; forced updates; any
change to the backup file format.

**Dependencies:** Release A published (or L-1 option 2); the production server recording client
versions for **90 days** (rule 4); C-1 closed and the restore drill done; the device gate met for the
target count; every test in §8; your written approval for each production change (§5.1).

**Done when:** every stage of §5 has met its exit gate, with zero unwrap failures.

### 0A.5 A decision for the launch-preparation phase: the launch baseline (L-1)

Because nothing is published yet, **there are no real users on old apps or old wraps**. That
opens a simpler option, **not decided and not authorised today** (no iteration count changes):

| Option | What ships at launch | Consequence |
| --- | --- | --- |
| **1. As planned** | Release A at 210,000; Release B later | the whole migration machinery (§3, §5, §6) is needed for the public |
| **2. Raise the count in the launch build** | the launch build creates new wraps at the target count (B-1 only); B-2 to B-5 are built **only when first needed** (for example for test accounts made before launch, or a later increase) | no public account ever needs migrating, no old-app risk, no 90-day wait |

Option 2 needs the device gate fully met at the target count, and sign-up, password change and
backup saving **timed on the oldest phone** (native writes, D-4 c). Test accounts made before
launch can simply be recreated. **My recommendation: decide this in P1, and lean to option 2
if the gate is met**, because it removes a whole class of risk instead of managing it. Release A
and Release B stay defined as above either way.

The open items N-1 to N-8 are decided in §11; the one decision still open is L-1 (§0A.5), for the launch-preparation phase.

## 1. What the inspection found

| # | Finding | Where | Consequence for the plan |
| --- | --- | --- | --- |
| F-1 | **The server never learns the app version.** Requests carry only `Content-Type` and `Authorization`. | `auth_session.dart` (6 call sites), `sync_service.dart:302` (1); the anonymous news feed is a separate call | A version guard needs a new header. Apps that do not send it are "unknown", which is the signal for old versions. |
| F-2 | **Release A has not shipped**, so the header can still go into it. | branch state | The cheapest moment to add the signal is **before** Release A is released. After that, apps in the wild without it are indistinguishable from pre-A apps. |
| F-3 | The server has **no device concept**. A token belongs to the account (`sub`, `ver`), not to a device. | `auth.py:create_access_token` | "Which versions does this account use?" needs a small new record per install. |
| F-4 | Tokens last **7 days** and are never refreshed. After that a request gets 401 and the app signs in again **with the password**. | `auth.py:47`, `auth_session.dart:ensureToken` | An upgrade needs the password, so it can only run at a password sign-in. An active user is reached within about a week. |
| F-5 | `GET /auth/me` runs at **every sync start**. | `auth_session.dart:ensureToken` → `_getMe` | It is the natural carrier for "you may upgrade" and for refreshing last-seen data, at no extra request. |
| F-6 | **`POST /auth/key/rewrap` was ungated** on the branch. It checks the password and compare-and-swap, never lowers the count, and signs nobody out, but had no switch and no version check. | `backend/main.py:rewrap_data_key` | **Resolved on the branch (M-0):** `KEY_UPGRADE_ENABLED`, off unless set to `1`/`true`/`yes`, read on every request; while off the route answers 403 before reading the password. `render.yaml` does not set it (a test enforces that). The version guard itself is still to be built (§8.2). |
| F-7 | An **old app reads the stored iteration count**, with no cap, and unwraps any count in pure Dart. | `data_key.dart:fromJson`, `unwrap` | **Correct but slow.** An old app can never be locked out by an upgraded wrap; the worst case is a slow sign-in (S23 Ultra, pure Dart at 600,000: 3.4–13.6 s; low-end phones are probably several times slower, an estimate). |
| F-8 | Under Release A, **new wraps and new backup files are derived by the Dart code**, even where native is available. | `Pbkdf2Engine.deriveForWriting` | At 600,000, sign-up, password change and **backup saving** would take the Dart time (S23: 3.4 s typical, one run 13.6 s). See D-4. |
| F-9 | The backup file format is **independent of the wrap**: own passphrase, own stored iterations (600,000 already for new files), format `waffr-backup` v1. The backup feature does not exist in any released app. | `ledger_backup_codec.dart` | Release B cannot break existing backups. It only touches speed (F-8). |
| F-10 | **Distribution is by APK** (answer to Q-1): no store, no store dashboards, **updates are manual**. iOS is not distributed. | you | The server-side header is the **only** adoption source. Adoption will be slower than with store auto-update. APKs must be signed with the **same release key** or they cannot update an installed copy (§10, R-5). iOS stays out of the guard until you configure it (§3.3 rule 2). |
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

Plus two columns on `users` (nullable timestamps):

- `legacy_seen_at`: the last time an **authenticated request without a valid header** came
  from this account (a legacy app).
- `first_client_seen_at`: the first time a request **with** a valid header came from this
  account. It starts the account's observation window (§3.3 rule 4).

- Written **at most once per 6 hours per (user, install)** from an in-memory throttle, on
  login, register, `/auth/me`, and `/sync`, through a short background session (the pattern
  `password_reset.email_code` already uses). **No extra latency and no write on every sync.**
- Pruned after 120 days. Deleted with the account (cascade, and added to
  `ACCOUNT_DELETE_ORDER` and `row_security.OWNED_TABLES`, F-11).
- No device model, no IP, no name: only what the guard needs.

### 3.3 Eligibility rule (computed on the server only; fails closed)

**Principle (Q-3): never upgrade an account if an older installation may still need
access.** An account is upgraded only when **every** rule holds. Any doubt, missing data or
error means *not eligible*.

1. **Switch and cohort:** `KEY_UPGRADE_ENABLED` is on and the account is in the approved
   rollout cohort (§5).
2. **The platform is configured:** `MIN_UPGRADE_BUILD` and `MIN_GUARD_BUILD` are set for the
   platform of the request **and** of every install on the account. An unconfigured platform
   (iOS today) is never eligible.
3. **The upgrading device is capable:** the request header has
   `build ≥ MIN_UPGRADE_BUILD[platform]` (Release B or later: the build that writes wraps).
4. **The whole 90-day window has been observed:** `first_client_seen_at` is at least
   `GUARD_WINDOW_DAYS` (**90**) ago. An account seen for 10 days is not eligible, because a
   second phone that was merely idle would still be invisible.
5. **No old app in the window:** `legacy_seen_at` is null or older than the window.
6. **Every known install is new enough:** every `client_installs` row last seen in the window
   has `build ≥ MIN_GUARD_BUILD[platform]` (Release A or later), and **there is at least
   one** such row (an account with no recorded install is unknown, so not eligible).
7. The stored wrap is below the target count; the new wrap is at least the target and at
   least the stored count; the swap is compare-and-swap (already enforced).

**Allowlisted test accounts** (your own, named in writing, §5.1) skip **rule 4 only**, so
Release B can be tested before 90 days have passed. They still need rules 1–3 and 5–7.

**Earliest first real upgrade:** 90 days after the recorder starts (Stage 1), by rule 4.
This is deliberate and is the price of the safest approach.

### 3.4 API changes (all additive; old apps ignore them)

| Route | Change |
| --- | --- |
| `GET /auth/me` | adds `key_upgrade: {"target_iterations": N}` **only when eligible**, otherwise omitted. Old apps ignore unknown fields (they read named keys). |
| `POST /auth/key/rewrap` | re-checks eligibility (the authoritative check) and answers **403 `{"detail":"key_upgrade_not_allowed"}`** otherwise. Everything else unchanged. |
| `POST /auth/login`, `/auth/register`, `/sync` | record the client header (throttled). No behaviour change. |

### 3.5 What the guard cannot know (honest limits)

- A phone with an **old app that has not been opened for 90 days** is invisible. If its owner
  opens it later, they get a slow but working sign-in (F-7), never a lockout. It is measured
  afterwards (§4.4), not prevented. This is the residual risk of the approved 90-day window.
- **Apps older than Release A cannot show the update notice** (they lack the code) and send
  no header. Reaching those users needs a message from you outside the app.
- A phone on a new app that never talks to the server is not counted.

### 3.6 Soft update notice (Q-5, N-1, N-2)

- **Server:** `GET /auth/me` adds `client_policy: {"recommended_build": N}`, from
  `RECOMMENDED_BUILD_ANDROID` (unset = no notice). A number only: **the server never sends
  text or links**, so a compromised server cannot point users at a malicious download.
- **App (Release A onward, approved in N-2):** if its own build is below `recommended_build`,
  it shows a **dismissible** notice, at most **once every 7 days**, with Arabic text you
  approve (Appendix A). It **never blocks** sign-in, sync or any screen. The code is dormant
  until the server sends a number.
- **The download link (N-1: deferred until you buy your domain).** **No temporary URL is
  written into the code.** Instead:
  - the app has one build-time constant `UPDATE_PAGE_URL` (`--dart-define`), **empty in every
    build until you give me the domain**;
  - **while it is empty the notice is text only: no button, no link**;
  - when it is set, the app accepts only an `https` URL, and the **only host it will ever
    open is the host of that constant**;
  - the constant is fixed at build time: **test builds stay text only; the launch build (P1) sets
    it** once the domain exists (N-8, resolved by the timeline in §0A).
- **Use a redirect on the domain** (for example `your-domain/download` pointing to wherever the
  APKs are hosted), so hosting can move later **without an app update**.
- Changing `RECOMMENDED_BUILD_ANDROID` is a production setting (§5.1).

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

### 4.2 No store cross-checks (Q-1)

APK distribution means there is no Play Console or App Store Connect. The server view is
the **only** measurement. Two sanity checks that need no new data:

- the number of APK downloads you can see on the page where you host them, against the
  active installs on the newest build;
- the count of **distinct install ids** against the count of accounts (more installs than
  accounts means accounts with several phones).

### 4.3 Adoption thresholds

| Level | Rule | Used for |
| --- | --- | --- |
| Start of any Release B upgrade | **≥ 95% of active installs** on Release A+ **and** **≥ 85% of active accounts passing the guard**, both held for **30 days** | go / no-go |
| Widening the cohort | the per-stage gates in §5 | stage progress |

You approved these figures (D-3). **With manual APK updates they may take a long time to
reach, or never.** Two points keep that safe:

- The per-account guard (§3.3) protects each account on its own, so a slow fleet cannot
  cause harm; it only delays upgrades.
- **The thresholds are never lowered, shortened or waived without your explicit approval.**
  If adoption stalls, the tools are the soft notice (§3.6) and your own outreach.

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

**Timing consequence of the strict window (§3.3 rule 4).** The first real upgrade of an
ordinary account can happen no earlier than **90 days after the recorder starts** (Stage 1),
however fast adoption is. Stages 2–3 can run earlier **only on allowlisted test accounts**,
which skip that one rule. Stage 4 widens only as accounts complete their 90 days.

**Controls (each is a production setting, so each needs your explicit approval, §5.1):**

- `KEY_UPGRADE_ENABLED` (kill switch), `KEY_UPGRADE_PERCENT`, `KEY_UPGRADE_ALLOWLIST`,
  `KEY_UPGRADE_TARGET_ITERATIONS`, `GUARD_WINDOW_DAYS` (stays 90), `MIN_GUARD_BUILD_*`,
  `MIN_UPGRADE_BUILD_*`, `KEY_REPAIR_ENABLED`, `RECOMMENDED_BUILD_*`.
- Changing an environment variable restarts the Render service (seconds to a minute of
  downtime on the Free plan; none on paid plans with a rolling deploy). If you need an instant
  switch, the alternative is one row in a settings table (more code; D-6).

**Pause rule:** any unwrap failure, or crossing a gate limit, stops widening. Setting the
percent back to 0 stops new upgrades the same minute and **does not touch already upgraded
accounts**, which stay valid.

### 5.1 Production change protocol (Q-6)

Every production change below needs **your explicit written approval for that exact change,
before it is made**: a backend deploy, a database migration, any environment variable
(`KEY_UPGRADE_ENABLED`, `KEY_REPAIR_ENABLED`, `KEY_UPGRADE_PERCENT`, `KEY_UPGRADE_ALLOWLIST`,
`GUARD_WINDOW_DAYS`, `MIN_*_BUILD_*`, `RECOMMENDED_BUILD_*`), publishing an APK, and an
emergency window (§6.5). Approval for one change is not approval for the next.

Each change is recorded in `RELEASE_B_CHANGE_LOG.md` (created at the first change):

| Field | Content |
| --- | --- |
| Date, time (UTC) | when it was made |
| Change | the exact setting, old value and new value |
| Approved by | you, with the message or reference |
| Evidence | the gate metrics and test run that justified it |
| Verification | what was checked afterwards |
| Rollback | the exact reverse change, and who does it |
| Result | outcome, with any anomaly |

I have no access to Render or to production, so **you make the change**; I prepare the exact
value, the pre-checks and the verification queries. A change is never batched with another.

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

- **Stop:** `KEY_UPGRADE_ENABLED` off (or percent 0), with your approval (§5.1). No new
  upgrades; no account changes.
- **Revert the app default:** if Release B's app is found faulty, ship a build with
  `defaultIterations` back at 210,000. Wraps already at 600,000 keep working on every version
  (F-7), so **no data rollback is needed**.
- **No route lowers a wrap.** The server refuses a weaker wrap on purpose. Bringing one
  account back to 210,000 is the emergency procedure in §6.5, not a rollout step.

### 6.4 Recovery (a bad or unreadable wrap)

The only way an account loses access is a wrap that does not open to the real data key.
Layered defences:

1. **Prevention:** the round trip and Dart cross-check before the upload, and the
   compare-and-swap keeping W_old until the swap (§6.1).
2. **Detection:** the post-upload verify, and a counter `unwrap_failed` at every sign-in
   (counts only).
3. **Self-heal (D-7), as its own route and switch.** If a password sign-in succeeds but the
   stored wrap does not open, and **this device still holds the account's data key** in
   secure storage:
   1. the app proves the local key is the account's by opening one sealed `enc1:` value from
      the sync reply;
   2. it calls `POST /auth/key/repair-request` (password required). The server records an
      audit event and opens a **15-minute** repair slot for this account, at most **3 a day**;
   3. within the slot it calls `POST /auth/key/repair` with a wrap of that key made with the
      password, using the broken wrap as `expected_wrapped_key` (compare-and-swap);
   4. a self-heal repair may **keep or raise** the count, never lower it.
   Both routes sit behind `KEY_REPAIR_ENABLED` (**off by default**; turning it on is a
   production change, §5.1). Neither route is the upgrade route, so the upgrade kill switch
   does not disable recovery.
   *Security note:* this adds no capability an attacker with the password does not already
   have: `POST /auth/password/change` already replaces the wrap from a password. What it adds
   is the audit trail.
4. **Backup file:** the user's encrypted export (`waffr-backup`) restores the ledger if
   every device has lost the key.
5. **Last resort:** the existing password-reset path (the server drops the wrap and blanks
   the sealed text; the next sign-in makes a new key and the device's local data repopulates
   it).
6. **Database restore:** if a bad write ever reached many rows, only a database backup can
   undo it, and **the production database has no backup today (C-1).** This must be fixed
   before Release B (§7.1).

### 6.5 Emergency single-account recovery (Q-7)

**What it can and cannot do.** The server never holds the data key or the password, so no
operator action can create a wrap or open anyone's data. What an operator can do is open a
**time-limited repair window for one account**, so the owner's own device (which holds the key)
can write a replacement wrap, **including one at a lower count** (the emergency downgrade).
If no device holds the key, the options are the backup file or a password reset (§6.4).

**It is used only when all of these hold:**

1. **The owner asked, or `unwrap_failed` was detected,** and the case is written down
   (ticket id, reason).
2. **The owner is verified by two independent proofs:** (a) a one-time code sent to the
   account's registered email (the existing reset-code mechanism, but **not** a reset);
   (b) the account password, checked by the repair route at the moment of the write.
3. **You approve this account and this window in writing** (§5.1) before it is opened.
4. **Nothing is edited directly in the database.** Wraps are never changed by hand; any
   direct database access for this purpose is itself recorded in the audit log.

**Mechanism (to be built after approval; nothing exists yet):**

- An operator command `python -m tools.open_repair_window --user-id N --ticket T
  --approved-by NAME --hours H` refuses to run unless every argument is given, caps `H` at
  **24**, allows **one open window per account**, and at most **3 per account per 90 days**.
- The window allows exactly one `POST /auth/key/repair` for that account, which needs the
  password and compare-and-swap, accepts any count ≥ 100,000, and **closes the window on
  success or expiry**.
- The command and the route never see or print a password, wrap or key.
- **The account owner is emailed** when a window is opened and when a repair succeeds, so no
  operator can act silently.

**Audit log (append-only):** table `key_recovery_audit`, kept even if the account is later
deleted (no cascade):

| Column | Content |
| --- | --- |
| `id`, `created_at` | |
| `user_id` | the account |
| `action` | `window_opened`, `repair_requested`, `repair_succeeded`, `repair_failed`, `window_expired`, `window_closed` |
| `actor` | operator name, or `owner` for self-heal |
| `ticket`, `approved_by`, `reason` | from the command |
| `verification` | which proofs passed (`email_code`, `password`), never their values |
| `request_ip` | for routes; `null` for the command |
| `outcome` | `ok` or a short error code |

- A database trigger refuses `UPDATE` and `DELETE` on this table, and the application role
  has `INSERT` and `SELECT` only.
- Every row is also written as a structured log line (`waffr.audit`) with no key material.
- Rows are kept at least **2 years** (N-4). You review the log after every use and record the
  result in `RELEASE_B_CHANGE_LOG.md`.

## 7. Release criteria and security checks

### 7.1 Before Release A is published (launch preparation, P1)

Release A is **not published before P1**. Test builds for you and your testers may be
debug-signed and are never public.

- [ ] Header, install id and the dormant soft-update notice are in the build, with tests (§8.1).
      `UPDATE_PAGE_URL` is set by the launch build once the domain exists (N-1, N-8).
- [ ] **Signing-key verification, mandatory (N-3), deferred to P1 and required before the first
      public APK. A release is not published if any step fails, and nothing overrides this
      without your written approval.** Because **no real users have installed a public build**,
      there is no installed base to match; the job is to set the key up correctly **once**.
  - **Step 0 (P1):** create the release keystore, **back it up offline in two separate places**
    (losing the key means nobody can ever update in place), and record its signer
    **certificate SHA-256** in `release/ANDROID_SIGNING_CERT.sha256` (a public fingerprint, not a
    secret). The `ANDROID_KEYSTORE_*` secrets are set in the release workflow.
  - **Step 1, every release:** the APK's signer SHA-256 equals the recorded one
    (`apksigner verify --print-certs`), it is signed with the v2 or v3 scheme, and it is not a
    debug certificate.
  - **Step 2, every release after the first:** an **in-place update rehearsal**: install the
    previous release APK, add data, install the new APK over it (`adb install -r`). The install
    must succeed (`INSTALL_FAILED_UPDATE_INCOMPATIBLE` means a key mismatch) and the data stay.
  - **Step 3:** the release workflow fails if the fingerprint differs or the certificate is a
    debug one.
  - **Before P1:** testers who installed **debug-signed** builds must uninstall them to move to
    the release-signed build; their data is test data, so this is accepted. Testers are told so.
- [ ] Benchmark gate for Release A: `self_test_passed` and `vectors_all_match` on at least three
      Android phones (**met**: S23 Ultra, Galaxy A56, Xiaomi 2404ARN45A, Infinix GT 20 Pro, all
      15 of 15). **iOS is not distributed (N-5), so an iPhone is not required**; it is required
      before any iOS build is published.
- [ ] A-2 on-device checks: save, open and restore a backup file; `adb shell bmgr` with and
      without a screen lock; a phone-to-phone transfer.
- [ ] C-1 closed: **the production database has a backup and a tested restore** (P1).
- [ ] M-0 done and its tests green (**done on the branch**); the switch is not set in
      production.
- [ ] Release A's build number is recorded as `MIN_GUARD_BUILD[android]` (only needed if the
      Release B guard is built, see L-1).

### 7.2 Before Release B's app is released

- [ ] **Device gate:** at least 3 Android phones **including a low-end one** (Cortex-A53 class),
      three runs each; native worst run ≤ 2.0 s at the proposed count. If 600,000 fails
      anywhere, propose the highest count that passes everywhere. *Status (`KDF_BENCHMARK.md` §7): S23 Ultra 3 of 3 runs; Galaxy A56 4 runs; Xiaomi 2404ARN45A
      (MediaTek MT6769, a budget chip, 2× Cortex-A75 + 6× A55 by my reading of the chip
      family, not reported by the app) 3 of 3 runs, native 600,000 worst 682 ms; Infinix GT 20 Pro
      2 of 3 (extra). By the gate's wording the device count is met if you accept the Xiaomi
      as the low-end phone. It is one step above the Cortex-A53 class the gate named, so I
      recommend also testing the **older, A53-class phone** you are getting (3 runs): it costs
      little and closes the question.*
- [ ] **iOS (N-5):** no iOS users are assumed, so the iPhone benchmark is deferred. An iPhone
      result, the iOS guard configuration and your approval are required **before any iOS build is
      published**; until then the guard never upgrades an iOS account (§3.3 rule 2).
- [ ] All tests in §8 pass, including interruption and mixed-version cases.
- [ ] The server guard has run in shadow mode for 14 days (Stage 1) with the §5 exit gate met.
- [ ] Self-heal and the emergency window work end to end against a deliberately broken wrap
      on a **test account**, and the audit log shows every step.
- [ ] A restore drill from the database backup has been done.

### 7.3 Security checks before enabling the server flag

- [ ] A cross-account test: an account cannot learn another account's eligibility or
      version data; row-security policy on `client_installs`; deleted with the account.
- [ ] The header cannot be used to **gain** an upgrade: a forged "new" build only affects the
      caller's own account (the upgrade also needs the password and a wrap the caller can
      open), and rule 3 still demands no legacy sightings.
- [ ] The guard fails **closed**: any error computing eligibility means "not eligible"; an
      unconfigured platform, an account with no install record, and an account observed for
      less than 90 days are each tested as not eligible.
- [ ] The repair routes are off by default, rate-limited, audited, and cannot lower a count
      outside an operator window; the audit table refuses `UPDATE` and `DELETE`.
- [ ] No new secret, token change, or log of the header contents beyond counts.
- [ ] Rate limits cover the new paths (rewrap: 5 an hour already; ingestion is throttled).
- [ ] `bandit`, `pip-audit`, the backend suite, and the Flutter suite are green; a regression
      test proves old clients (no header) still log in, sync, change passwords and delete
      accounts unchanged.
- [ ] A staged dry run: on a **copy** of the schema (never production), run the migration
      twice and confirm it is idempotent and that the table and policy exist.

## 8. Exact changes required (only M-0 is built; everything else is a plan)

### 8.1 Addendum to Release A (before it ships)

| File | Change |
| --- | --- |
| `lib/core/net/api_client.dart` (new) | one helper that adds `Content-Type`, `Authorization` and `X-Waffr-Client`; replaces the raw `http` calls |
| `lib/core/net/client_identity.dart` (new) | version and build via the native `info` call; install id in prefs |
| `lib/core/net/update_notice.dart`, a small notice widget (new, approved in N-2) | the §3.6 notice: reads `client_policy`, 7-day throttle, dismissible, text only while `UPDATE_PAGE_URL` is empty, then one `https` host from that constant; dormant until the server sends a number |
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

**Additional server changes from your answers:**

| File | Change |
| --- | --- |
| `backend/key_upgrade.py` | **exists (flag only)**; add eligibility, cohort and allowlist later |
| `backend/models.py`, `database.py` | also `users.first_client_seen_at`; `KeyRecoveryAudit` model and trigger |
| `backend/main.py` | `client_policy` in `/auth/me` (soft notice); `POST /auth/key/repair-request` and `POST /auth/key/repair` behind `KEY_REPAIR_ENABLED` (off by default) |
| `backend/tools/open_repair_window.py` (new) | the §6.5 operator command |
| `backend/tests/test_key_repair.py` (new) | switch off by default; slot expiry and daily cap; no lowering outside a window; compare-and-swap; email notices; audit rows and the append-only trigger |
| `backend/tests/test_client_policy.py` (new) | notice number only, no text or links; absent when unset |

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

Nothing is merged or deployed in P0. This table lists what must be true **at the time** of
a merge or a deployment, which belongs to P1 or later.

| ID | Item | Status |
| --- | --- | --- |
| **M-0** | Gate `POST /auth/key/rewrap` behind `KEY_UPGRADE_ENABLED` (off by default; 403 before the password is read) | **Done on the branch, not merged or deployed.** `backend/key_upgrade.py`, `main.py`, `SECURITY.md`; 26 tests in `test_key_upgrade_flag.py`. Backend suite: 481 passed |
| M-1 | Header, install id and the dormant notice in Release A (§8.1) | approved; **not started; starts when you say so** |
| M-2 | C-1: production database backup and restore drill | **deferred to P1**; a launch blocker, not a present risk |
| M-3 | Signing-key verification (§7.1, mandatory) | **deferred to P1**; required before the first public APK |

Deploying the current backend would **not** enable upgrades: the switch is off unless
`KEY_UPGRADE_ENABLED` is set in production, and `render.yaml` does not set it.

## 10. Risks

| # | Risk | Impact | Likelihood | Mitigation |
| --- | --- | --- | --- | --- |
| R-1 | Old app meets an upgraded wrap | slow sign-in, never lockout | low with the strict guard; the dormant (> 90 days) phone remains | rules 4–6; `legacy_after_upgrade` metric; pause at 0.5% |
| R-2 | Bad wrap written | possible loss of access on that account | very low | round trip, Dart cross-check, compare-and-swap, self-heal, §6.5, backup file, database backup |
| R-3 | Dart cross-check never completes on the slowest phones | those phones do not upgrade | medium on very low-end | another device of the same account can upgrade it; accepted (D-4) |
| R-4 | Native write path has an input-dependent bug | wrong key written | very low | known-answer test at the target count; 15 vectors; Dart cross-check on rewrap |
| R-5 | **APK updates fail** because a public APK is debug-signed, or signed with a different key, or the release key is lost | a user must uninstall; a **guest could lose local data**; with a lost key nobody can ever update in place | medium without a check | the mandatory verification in §7.1 (N-3, P1): one correctly created key backed up in two places, a fingerprint match and an in-place rehearsal before every release; guests are told to save a backup file first |
| R-6 | Adoption stalls (manual updates) | Release B delayed; thresholds never met | high | soft notice, outreach, thresholds never lowered without approval |
| R-7 | Users on apps older than Release A cannot be nudged in-app (once Release A exists) | they stay on the old path | certain **only for builds that exist before Release A**; today those are test builds | outreach outside the app; no public build exists before Release A |
| R-8 | An operator abuses the emergency window | an account's wrap replaced | very low | two proofs, your written approval, owner email notices, append-only audit log, 1 window at a time, daily caps |
| R-9 | New table or throttle adds load | latency | low | throttled background writes; shadow-mode measurement |
| R-10 | Env var change restarts Render | brief downtime | certain, small | schedule it with your approval (§5.1) |
| R-11 | Backup saving slow at 600,000 via Dart | slow save on low-end | medium | D-4 (c) |

## 11. Final decisions on the open items

| # | Item | Your decision | What it means now |
| --- | --- | --- | --- |
| **N-1** | Official download page for the soft notice | **Deferred until you buy your domain. No temporary URL is hardcoded.** | domain-dependent, deferred to P1; the notice is text only in test builds |
| **N-2** | Soft-update notice code in Release A | **Approved** (dormant) | part of Release A (A-4); starts when you say so |
| **N-3** | Signing-key verification | **Mandatory before release** | deferred to P1 and required **before the first public APK** (§7.1) |
| **N-4** | Recovery audit log retention | **At least 2 years** | §6.5, Release B |
| **N-5** | iOS | **No iOS users assumed; iPhone benchmark deferred until iOS distribution** | §0A.2, §7.2 |
| **N-6** | Arabic texts | **Claude drafts, you approve** | Appendix A; drafts, not approved; final texts and the support address in P1 |
| **N-7** | Emergency recovery approvals | **You are the sole approval authority** | §6.5, Release B |
| **N-8** | Should Release A wait for the domain? | **Resolved by the timeline:** Release A is not published before P1, when the domain will exist | no temporary URL; the launch build sets `UPDATE_PAGE_URL` |

**One decision is deferred to P1:** the launch baseline **L-1** (§0A.5): launch with Release A as
planned, or raise the count for new accounts in the launch build. No iteration count changes
before you decide.

## 12. What happens next

**Now (P0), without touching production:**

1. Device testing continues: the older, Cortex-A53-class phone (3 runs) and the third GT 20 Pro run.
2. Security testing continues on isolated local servers with synthetic data.
3. The Release A addendum (A-3, A-4) and, later, Release B's code can be built and tested
   locally. **Neither is authorised yet.** Tell me when to start the addendum.

**P1 (launch preparation), later:** domain; production server; database backups and the restore
drill; the release signing key and its verification (N-3); the release workflow; final Arabic
texts and support address; `UPDATE_PAGE_URL`; L-1; the iOS decision.

**P2:** publish Release A, with your explicit approval. **P3:** server guard dark, the 90-day
clock, then Release B in the stages of §5, each step approved (§5.1).

Nothing in this plan starts without your explicit approval.

## Appendix A. Arabic drafts (N-6): DRAFT, NOT APPROVED

Nothing below is in the code. Placeholders in `[brackets]` are filled when you approve. Rules
for every text: no keys, wraps, passwords or codes in it; **emails contain no links** (they tell
the user to open the app, so they cannot be mistaken for phishing).

### A.1 In-app update notice (dismissible, at most once every 7 days)

Title: **يتوفر إصدار أحدث من وفّر**

Body, while `UPDATE_PAGE_URL` is empty (text only):

> يتوفر إصدار جديد من التطبيق فيه تحسينات للأمان والأداء. يمكنك متابعة استخدام وفّر كالمعتاد،
> ويُنصح بالتحديث من صفحة التنزيل الرسمية عند أول فرصة.

Body, once a link exists (adds a button):

> يتوفر إصدار جديد من التطبيق فيه تحسينات للأمان والأداء. يمكنك متابعة استخدام وفّر كالمعتاد،
> ويُنصح بالتحديث عند أول فرصة.

Buttons: **فتح صفحة التنزيل** (only when a link exists) · **لاحقاً**

Extra line shown **only to guests** (no account), because a failed update can cost local data:

> قبل التحديث، احفظ نسخة احتياطية مشفّرة من بياناتك: الإعدادات ← الخصوصية والأمان ← النسخة
> الاحتياطية المشفّرة.

### A.2 Emails to the account owner (§6.5)

**Window opened.** Subject: **وفّر: فُتحت نافذة إصلاح لمفتاح التشفير في حسابك**

> مرحباً،
>
> بناءً على طلبك، فُتحت نافذة إصلاح مؤقتة لمفتاح تشفير بياناتك في حسابك. تنتهي النافذة بعد
> [عدد الساعات] ساعة، ولا يتغير شيء في حسابك قبل أن تُجري الإصلاح بنفسك من التطبيق بكلمة مرورك.
>
> إذا لم تطلب ذلك، غيّر كلمة مرورك فوراً من التطبيق، ثم راسلنا على [بريد الدعم].

**Repair done.** Subject: **وفّر: تم تحديث مفتاح التشفير في حسابك**

> مرحباً،
>
> تم بتاريخ [التاريخ والوقت] تحديث مفتاح تشفير بياناتك في حسابك بنجاح، وأُغلقت نافذة الإصلاح.
>
> إذا لم تقم بذلك أنت، غيّر كلمة مرورك فوراً من التطبيق، ثم راسلنا على [بريد الدعم].

**Window expired unused.** Subject: **وفّر: انتهت نافذة الإصلاح دون استخدام**

> مرحباً،
>
> انتهت نافذة الإصلاح المؤقتة لحسابك دون أن تُستخدم، ولم يتغير شيء في حسابك. إن ما زلت تحتاج
> مساعدة، راسلنا على [بريد الدعم].

**To decide when you approve:** the support address `[بريد الدعم]` (a domain address once you have
one; until then, an address you choose).
