# Waffr: pre-launch checklist (living document)

Branch: `claude/affectionate-wozniak-9zle5o`. **Public launch planned for early 2027.**
Read this file first in any new session. The detailed plans are `RELEASE_B_READINESS_PLAN.md`,
`SECURITY_STATUS_REPORT.md`, `KDF_BENCHMARK.md` and `NATIVE_PBKDF2_PLAN.md`.

## Standing rules (approved by the owner)

- No production change, deployment, merge or public release without the owner's explicit, written approval for that exact change.
- Nothing is published before launch preparation (P1). Test builds are debug-signed and never public.
- Release B is **not authorised**. Release A's addendum (A-3, A-4) starts only when the owner says so.
- Iteration counts stay at 210,000 until the owner decides (see L-1).
- Emergency single-account recovery: the owner is the only approver (N-7), with strict verification and audit logging.

## Blockers for launch (must be done in P1)

| # | Item | Status | Owner |
| --- | --- | --- | --- |
| C-1 | Production database backups and a tested restore drill | open | owner (Render) |
| N-3 | Create the release signing key once; back it up offline in two places; record the signer SHA-256 in `release/ANDROID_SIGNING_CERT.sha256`; mandatory verification before the first public APK | open | owner (key) + Claude (verification steps) |
| N-1 | Buy the domain; set `UPDATE_PAGE_URL` for the launch build; use a redirect so hosting can move | open (domain not bought) | owner |
| N-8 | Release A is not published before the domain exists | decided | — |
| P-1 | Confirm the production service sets `True-Client-IP`; send one request with a made-up `X-Forwarded-For` and check the logged `ip`; set `TRUSTED_PROXY_HOPS` if needed | open | owner (production access) |
| H-3 | Rotate the Google OAuth client that is in git history (commit `fe81ee4`) | open | owner (Google Cloud) |

## Decisions still needed from the owner

| # | Decision | Notes |
| --- | --- | --- |
| L-1 | Launch baseline: (1) launch Release A at 210,000 and migrate later, or (2) raise the count for new accounts in the launch build | lean to (2) if the device gate is fully met; no iteration change until decided |
| N-6 | Approve the Arabic drafts (update notice, owner emails in `RELEASE_B_READINESS_PLAN.md` Appendix A) and choose the support email address | drafts exist, not approved |
| P-9 | Lockout design: accept the trade-off, or add progressive delay / email-code verification after N failures | open |
| N-5 | iOS: confirm no iOS users; iPhone benchmark and iOS guard configuration are required before any iOS build is published | deferred |
| L-6 / L-12 | Email verification at sign-up; "sign out everywhere"; password before account deletion | open, optional for launch |

## Production read-only checks (need owner access; nothing changed yet)

- M-5: whether a `waffr_admin` role exists with the old `CHANGE_ME` password; restrict database external access to the owner's IP.
- M-7: unique constraints present on all 9 tables:
  ```sql
  SELECT conrelid::regclass, conname FROM pg_constraint WHERE conname LIKE 'uq_%_user_client' ORDER BY 1;
  ```

## Testing still to do (no production needed)

- **Devices:**
  - an older Cortex-A53-class Android phone, 3 runs (`KDF_BENCHMARK.md`);
  - Infinix GT 20 Pro, run 3;
  - the 64-bit ARM benchmark APK (CI run `50ca1ed`, in progress when this was written): install on a phone and send the JSON report.
- **On-device backup checks (P-11):** save, open and restore an encrypted backup file; `adb shell bmgr` backup with and without a screen lock; phone-to-phone transfer.
- **Dart dependency audit:** `flutter pub outdated` and an OSV scan, on a machine with internet access (blocked from the build environment).
- **Independent review** of `backend/client_address.py`, the login path in `backend/main.py`, `backend/routers/sync.py`, and the Kotlin/Swift PBKDF2 code.

## Release status

| Release | Scope | Status |
| --- | --- | --- |
| Release A | Native PBKDF2 at 210,000; encrypted backup; rewrap switch (off); header and dormant notice (A-3, A-4) | built and tested except A-3/A-4; **not published** |
| Release B | Raise the count; server guard (90-day window); upgrade flow; recovery routes | **not started, not authorised** |

Built on the branch: `KEY_UPGRADE_ENABLED` switch (off by default, 26 tests); backend suite 481 passed.
Benchmarks so far: Samsung S23 Ultra (3 runs), Galaxy A56 (4), Xiaomi 2404ARN45A (3), Infinix GT 20 Pro (2). All 15 vectors match on every run; native 600,000 worst case 682 ms against a 2 s target.

## Security status (latest)

See `SECURITY_STATUS_REPORT.md`. Summary: P-1 (X-Forwarded-For) is fixed only if the production edge sets `True-Client-IP`; P-2 (concurrent logins) is fixed and retested; P-9 is an open design trade-off; C-1 and N-3 are launch blockers.
