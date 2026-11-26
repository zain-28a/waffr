# Two client-side security decisions: local backups and key derivation

Date: 2026-11-26. Investigation only: no code, data, keys or settings were
changed. These are open findings P-11 and P-12 from `SECURITY_VERIFICATION.md`.

Files inspected:
- Storage and backup: `lib/core/prefs/app_prefs.dart`, `lib/data/stores/*`,
  `lib/data/services/{backup_service,home_widget_sync,legacy_profile_photo}.dart`,
  `lib/screens/offline/report/expense_history_share.dart`,
  `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`,
  `ios/Runner/Info.plist`, `pubspec.yaml` / `pubspec.lock`.
- Keys and auth: `lib/core/security/data_key.dart`,
  `lib/core/sync/{auth_session,sync_crypto,sync_codec}.dart`.
- Backend: `backend/main.py` (`/auth/key`, `/auth/me`, `/auth/password/*`),
  `backend/schemas.py` (`DataKeyIn`), `backend/password_reset.py`.

---

## 1. Local ledger backups

### 1.1 Where the ledger lives today

Everything the app knows is in **plain JSON in `SharedPreferences`**, through
`AppPrefs`, which uses the legacy `SharedPreferences.getInstance()` API.

- On Android that is `shared_prefs/FlutterSharedPreferences.xml`.
- On iOS it is the app's `NSUserDefaults` plist in `Library/Preferences/`.

| Data | Prefs key(s) | Plaintext on the device? |
| --- | --- | --- |
| Every income, expense and savings move, with amount, currency, date, **category, payment method and note** | `transactions` | yes |
| Savings goals (name, target, plan), balances, periods | `savings_goals`, `balance`, `max_balance`, `savings_balance`, `processed_periods`, income amounts | yes |
| Recurring expenses, shopping items, presets, custom categories | `recurring_expenses`, `shopping_list_items`, `expense_presets`, `custom_expense_categories` | yes |
| In-app notifications (texts quote amounts and names) | `waffer_notifications`, … | yes |
| **Profile PII**: name, gender, birthdate, country, city, street, phone, account email | `user_name`, `user_birthdate`, `user_street`, `user_phone`, `waffer_account_email`, … | yes |
| Sync state: tombstones, last sync, dirty flags | `waffer_sync_*`, `waffer_last_sync_at` | yes (no secrets) |
| Home-screen widget: balance, month totals, the last few entries with their **note or category and amount** | Android `HomeWidgetPreferences.xml`; iOS app-group `UserDefaults` | yes, unless the "hide amounts" option is on |
| JWT and the **raw 32-byte data key** | `flutter_secure_storage` 11.2.0. Android: the plugin's prefs file, encrypted with an Android Keystore key. iOS: Keychain, default accessibility `unlocked` | **no**, encrypted |
| Shared expense PDFs | `cacheDir/shared_pdfs/*.pdf`; never deleted by the app | yes, but cache is not backed up |
| A legacy plaintext password (old app versions) | `waffer_sync_password` | yes, while it exists; see 1.3 |

The encryption you added for sync (AES-256-GCM, `enc1:` values) **only applies
on the wire and on the server**. The device copy is plaintext, and the app lock
(biometrics or PIN) protects the screen, not the files.

### 1.2 What gets backed up today

**Android.** The manifest sets no `android:allowBackup`, `fullBackupContent` or
`dataExtractionRules`, and `targetSdk` is Flutter's default, which is above 31. So
Android's defaults apply:

| Channel | Included | Encryption of the backup |
| --- | --- | --- |
| **Google cloud backup** (Auto Backup, about daily, up to 25 MB) | all of `shared_prefs/` (**the full plaintext ledger, PII and widget data**), `files/`, databases. `cache/` and `no_backup/` are excluded | end-to-end encrypted with the screen lock *only if the device has a PIN, pattern or password* (Android 9+). **Without a screen lock, the backup sits at Google encrypted with keys Google holds.** |
| **Device-to-device transfer** (setting up a new phone) | the same files. On Android 12+ even `allowBackup="false"` would **not** stop this; only `dataExtractionRules` can | encrypted in transit, user-initiated, to the user's own device |
| `adb backup` | excluded for apps targeting 31+ | n/a |

The secure-storage file is backed up too, but its Keystore key never leaves the
device. After a restore the file cannot be decrypted. `flutter_secure_storage`
10+/11 resets on that error by default, so the token and data key are dropped and
the user has to sign in again. That is safe and no data is lost, but the restore
carries a useless encrypted file and depends on the plugin's error path.

**iOS.**
- `NSUserDefaults` and the app-group container are included in **iCloud Backup**
  and **Finder/iTunes backups**.
- iCloud Backup is encrypted at rest, but Apple holds the keys unless the user has
  turned on Advanced Data Protection.
- A Finder backup made **without** "Encrypt local backup" stores the plist, so the
  whole ledger and the PII are readable on that computer.
- Keychain items (token, data key) with the default `unlocked` accessibility travel
  only in *encrypted* backups and iCloud. They are absent from unencrypted local
  backups and they survive an app uninstall.

**In-app backup.** There is none. Despite its name, `BackupService` only wipes or
keeps local data on account switch and guest mode. There is no export or import of
the ledger.

### 1.3 Risks

| # | Risk | Who is exposed | Likelihood × impact |
| --- | --- | --- | --- |
| B-1 | The full ledger, notes and PII readable from a **Google cloud backup of a phone without a screen lock** (Google-held keys; anyone who takes over the Google account and restores to another device) | Android users without a screen lock | low × high |
| B-2 | The same data readable from an **unencrypted Finder backup** on a shared or stolen computer | iOS users who back up to a computer | low-medium × high |
| B-3 | The legacy plaintext password `waffer_sync_password` can survive in prefs, and therefore in backups. It is only deleted on sign-in, sign-out, or when an old prefs token is migrated. An install that skipped those keeps it | users who upgraded from the oldest builds | low × high (password reuse) |
| B-4 | **Guests have no recovery path except the OS backup.** Turning backups off would make a lost or replaced phone a total loss for them | every guest | high × high if backups are simply disabled |
| B-5 | Widget data in backups and on the lock-screen widget | everyone using widgets | low × low (a summary, and a hide option exists) |
| B-6 | PDFs pile up in `cacheDir` (not backed up, but on disk until the OS clears the cache) | users who share reports | low × low |

**B-4 is the constraint that matters most.** For signed-in users, the server is
the real recovery path. It is already tested (sign in on a new device and
everything comes back), with private text end-to-end encrypted. For guests, the
OS backup is the *only* copy. So the fix must not just switch backups off.

### 1.4 Options

| Option | Security | Recovery | Cost |
| --- | --- | --- | --- |
| A. `allowBackup="false"` | removes cloud backups (B-1). **Does not stop device-to-device transfer on Android 12+.** Does nothing on iOS | **breaks guests' only recovery (B-4)** | trivial. **Not recommended** |
| B. Android backup rules: cloud backup *only when it can be end-to-end encrypted*, exclude the secure-storage file, keep device transfer | fixes B-1. Plaintext never reaches Google under Google-held keys | guests with a screen lock keep cloud recovery; everyone keeps phone-to-phone transfer; signed-in users also have sync | two XML files and two manifest attributes. **No runtime cost** |
| C. An **encrypted export and import** the user starts ("save a backup file") | the file is AES-256-GCM sealed with a key derived from a backup passphrase. It is safe on Drive, in Files or by email | the **only cross-platform** path (Android↔iOS), works offline and for guests, and does not depend on OS backup settings | a new feature and screen, roughly 1–2 days of work with tests |
| D. **Encrypt the ledger at rest** with a device key | stops raw file reads on rooted or forensic devices, and **on iOS fixes B-2** if the key is a Keychain item *without* `ThisDeviceOnly` (it then travels only in encrypted backups) | iOS: restore keeps working. **Android: the Keystore key is never backed up, so restored ledgers would be unreadable.** It needs C as the fallback, or a different key-escrow design | the largest change. Every save re-encrypts the ledger in pure-Dart AES: tens to hundreds of ms for big ledgers, so it would need an isolate. Risk of data loss if the key is lost |

### 1.5 Recommendation

Do **B + C**, plus three small fixes. Leave **D** for later, iOS first.

1. **Android backup rules (B).** Proposed files, for review; nothing is written yet:
   ```xml
   <!-- res/xml/data_extraction_rules.xml (Android 12+) -->
   <data-extraction-rules>
     <cloud-backup disableIfNoEncryptionCapabilities="true">
       <include domain="sharedpref" path="FlutterSharedPreferences.xml"/>
       <exclude domain="sharedpref" path="FlutterSecureStorage.xml"/>
       <exclude domain="sharedpref" path="HomeWidgetPreferences.xml"/>
       <exclude domain="file" path="."/>
     </cloud-backup>
     <device-transfer>
       <include domain="sharedpref" path="FlutterSharedPreferences.xml"/>
       <exclude domain="sharedpref" path="FlutterSecureStorage.xml"/>
       <exclude domain="sharedpref" path="HomeWidgetPreferences.xml"/>
     </device-transfer>
   </data-extraction-rules>

   <!-- res/xml/backup_rules.xml (Android 11 and below) -->
   <full-backup-content>
     <include domain="sharedpref" path="FlutterSharedPreferences.xml"
              requireFlags="clientSideEncryption"/>
   </full-backup-content>
   ```
   with `android:dataExtractionRules="@xml/data_extraction_rules"` and
   `android:fullBackupContent="@xml/backup_rules"` on `<application>`.

   The exact secure-storage file name for v11 and the widget prefs name must be
   confirmed on a device before shipping. Then test with `adb shell bmgr` (backup,
   restore, a device with and without a screen lock) and a D2D transfer.

   The widget prefs are excluded because they are rebuilt from the ledger on start.
   Stray `files/` are excluded because the legacy photo is already deleted.
2. **Encrypted export and import (C).**
   - **Format:** `waffr-backup` v1 = a JSON header
     (`format`, `version`, `kdf: pbkdf2-sha256`, `iterations: 600000`, `salt`,
     `created_at`, `app_version`) plus an AES-256-GCM sealed body of the same store
     snapshot sync builds. The MAC also authenticates the header.
   - **Passphrase:** set by the user, separate from the account password (so guests
     can use it). At least 10 characters, with a strength hint.
   - **Import:** opens the body, then merges it through the stores' existing merge
     functions (last write wins, tombstones respected), or replaces local data after
     an explicit confirmation. It never touches the server directly; a signed-in
     device then syncs as usual.
   - **Tests:** round-trip, a wrong passphrase, a tampered file, a newer format
     version (refused), importing into an empty app and into a non-empty one.
3. **Small fixes:**
   - Delete `waffer_sync_password` unconditionally at startup (B-3).
   - Delete `shared_pdfs/` files once the share sheet closes, or at the next start (B-6).
   - Show a one-line notice in Settings for guests: "your data lives only on this
     phone; save a backup file".
4. **Later (D), iOS:** move the ledger from `NSUserDefaults` to a file in
   Application Support, sealed with a key kept in the Keychain as
   `afterFirstUnlock` (not `ThisDeviceOnly`). Unencrypted Finder backups then hold
   only ciphertext, while encrypted and iCloud restores still work. Do it only
   after C exists as the safety net.

**What stays the same.** Offline-first is untouched. The stores keep reading and
writing locally, and B is backup metadata only. Sync, the server and existing users'
data are not affected.

**Migration needs.** None for B. Rules apply to the *next* backup, and older backups
at Google are replaced over time. For C, none: it is a new feature.

**Compatibility risk.** On Android 12+ phones without a screen lock, cloud backup
stops. For guests on those phones, C is then their safety net, so ship B and C in
the same release.

---

## 2. Encryption key derivation

### 2.1 How it works today

```
register / first sign-in        data key K = 32 random bytes (Random.secure)
                                salt S = 16 random bytes
                                KEK = PBKDF2-HMAC-SHA256(password, S, 210000, 256 bits)
                                W = AES-256-GCM(KEK, K)            (fresh nonce)
                                PUT /auth/key {salt S, iterations 210000, wrapped_key W}

sync                            private text → AES-256-GCM(K) → "enc1:…"   (never the KEK)

sign-in on a device             GET /auth/me → {salt, iterations, wrapped_key}
                                K = AES-GCM-open(PBKDF2(password, salt, iterations), W)
                                K stored in flutter_secure_storage; no PBKDF2 after that

password change                 K = unwrap(old pw); W' = wrap(K, new pw, 210000)
                                POST /auth/password/change {…, data_key: W'}

password reset                  server drops W and blanks every enc1: value (K is lost)
```

Facts that matter:

- The iteration count is **stored with each wrapped copy**
  (`users.key_iterations`), and `unwrap` uses the stored value, not the constant
  (`DataKeyStore.unwrap` passes `wrapped.iterations`).
- The server accepts 100,000–10,000,000 (`DataKeyIn`).
- PBKDF2 and AES come from the pure-Dart `cryptography` 2.9.0 package, run in a
  background isolate with `compute()`.
- PBKDF2 runs **only** at register (one wrap), each sign-in (one unwrap) and a
  password change (one unwrap and one wrap). Never during sync.
- **The data itself is encrypted with K, not with the password.** The iteration
  count only protects the wrapped copy W of K.

### 2.2 What 210,000 vs 600,000 actually protects

An attacker who has W, S and the iteration count can guess passwords offline. Each
guess costs one PBKDF2, and a hit yields K, which decrypts every `enc1:` value.
W reaches an attacker in two ways:

1. **A database breach.** The attacker also gets the Argon2id login hash of the same
   password. Since phase 2 that hash uses OWASP's minimum (19 MiB, t=2, p=1), which
   OWASP rates as about equivalent to PBKDF2-SHA256 at 600,000. So today **W at
   210,000 is the cheaper of the two password oracles, by about 2.9×**. Raising it to
   600,000 brings the two into line.
2. **A stolen token.** Any valid bearer token can call `GET /auth/me`, which returns
   W, S and the iteration count. There is no Argon2 hash in that case, so **PBKDF2 is
   the only barrier** and the iteration count is the whole defence.

**Order-of-magnitude cost, offline.** This uses public hashcat-class figures for
PBKDF2-HMAC-SHA256 on one high-end GPU, about 9×10⁹ HMAC iterations per second.
Treat it as an estimate, not a measurement.

| Password | 210,000 iterations | 600,000 iterations |
| --- | --- | --- |
| A common or leaked password | seconds | seconds |
| 8 random lowercase letters and digits (36⁸) | about 2 GPU-years | about 6 GPU-years |
| 10 random characters from all printable (95¹⁰) | far beyond reach | far beyond reach |

The upgrade makes offline guessing about 2.9× slower: a real but linear gain. **The
bigger lever is password quality.** Today the minimum is 8 characters at sign-up, no
check against breached passwords, and no minimum at all for older accounts at sign-in.

### 2.3 Costs

**Device time.** One derivation at 600,000 costs about 2.9× today's. The repo has no
measurement and no Flutter SDK is available here. Pure-Dart HMAC-SHA256 on a
low-end Android phone (AOT) is commonly about 0.5–1.5 µs per iteration. That would
put today's unwrap at roughly 0.1–0.3 s and **600,000 at roughly 0.3–0.9 s**, about
twice that on very old devices. It runs in an isolate, so the UI stays responsive;
sign-in just waits a little longer.

*This estimate must be measured before release.* Plan: a profile-mode benchmark of
one PBKDF2 at 600,000 on a low-end and a mid-range Android phone and an older
iPhone. Accept if the low-end phone takes at most about 2 s per derivation.

**Where users feel it.**
- Sign-up and sign-in pay it once.
- A password change pays it twice.
- The one-time migration (2.5) adds **one** derivation in the background after a
  sign-in.
- **Sync never pays it.**

**Native speed-up (optional, later).** `cryptography_flutter` offers a native PBKDF2
on Android only (iOS falls back to the same Dart code in an isolate). Its maintainers
have flagged device-specific issues in the past, and the package has a maintenance
fork. It would need cross-checking against the Dart output with fixed test vectors.
I do not recommend adding it unless the benchmark fails.

**Server cost.** None: the server never runs PBKDF2. It stores 600,000 like any
other value, inside the accepted range.

### 2.4 Does existing encrypted data stay readable?

**Yes, all of it, by construction.**

- Rows are sealed with K. Re-wrapping changes only W, the box around K. K itself and
  every `enc1:` value stay exactly the same.
- Wraps carry their own iteration count, so existing 210,000 wraps keep unwrapping on
  every app version, and new 600,000 wraps unwrap on **old app versions too**.
- Signed-in devices already hold K in secure storage and never touch W again until
  their next password sign-in or password change. A re-wrap on another device does
  not affect them.

**The only way to lose data** is to replace W with a wrap of a *different* key (or a
corrupted one). Other devices would then fail to unwrap at sign-in, and with no copy
of K left, the sealed text would be lost. The migration below is built so that this
cannot happen.

### 2.5 Backward-compatible migration

**Server, additive.** Old apps are unaffected.

```
POST /auth/key/rewrap            (signed in)
  body: { current_password,            # same bar as a password change
          expected_wrapped_key,        # the W the client unwrapped
          data_key: {salt, iterations, wrapped_key} }
  rules:
    - verify current_password (Argon2, hashing queue, per-account limit as for
      password change). Wrong → 400, nothing changes
    - iterations(new) ≥ iterations(stored) and ≥ 600000 → no downgrades
    - UPDATE users SET key_salt, key_iterations, wrapped_key
        WHERE id = me AND wrapped_key = expected_wrapped_key      # compare-and-swap
      0 rows → 409 (changed meanwhile: a password change, a reset, another device)
    - token_version is NOT changed → no device is signed out
    - log event "data_key_rewrapped" (no values)
```

Why not reuse an existing route:
- `PUT /auth/key` is set-once (409 by design, which was fixed in P-3).
- `/auth/password/change` bumps `token_version`, which signs out every other device.
  It also requires `new_password` to be at least 8 characters, which older accounts
  may not meet.

**Client.**
1. `DataKeyStore.defaultIterations = 600000`. This covers new keys, password changes
   and keys created after a reset. Existing wraps keep their own count.
2. After a **successful sign-in** (`_unlockDataKey` already has the password and has
   just unwrapped K), if `wrapped.iterations < 600000`, start a background task:
   - derive the KEK once at 600,000 with a new salt and seal K;
   - **check** by opening the new box with the same KEK and comparing it byte for
     byte with K. No second PBKDF2 is needed;
   - call `/auth/key/rewrap` with `expected_wrapped_key` = the old W.
   - `200` → done.
   - `409` → re-fetch `/auth/me`; there is nothing to do if the stored copy is already
     at 600,000 or newer.
   - Network errors or `503` → retry at the next sign-in.
   - The task never blocks or fails the sign-in itself.
3. Old app versions keep working with both formats, so there is no forced update.

**Coverage.** Tokens last 7 days, so every active user signs in with their password
within about a week of updating the app, and their wrap is upgraded then. Inactive
accounts keep the 210,000 wrap until they return. That is no worse than today.

**Monitoring.** Run a read-only `SELECT key_iterations, count(*) FROM users GROUP BY 1`
(through `admin_view`, once it has that column) to watch progress.

**Later, optional.** Once old app versions are retired, raise the server minimum for
*new* keys (`DataKeyIn.iterations ≥ 600000`). It is not needed for safety, and doing
it early would make old apps fail to create keys.

**Rollback.** Revert the client constant. 600,000 wraps stay valid for every version,
so nothing needs undoing.

**Tests to write with the implementation.**
- *Backend:*
  - a correct rewrap is accepted;
  - a wrong password, a stale `expected_wrapped_key`, a downgrade, or no token are
    refused;
  - `token_version` is unchanged;
  - concurrent rewraps (exactly one wins) and a rewrap racing a password change;
  - the per-account rate limit applies.
- *Client unit tests:*
  - wrap/unwrap at 210,000 and 600,000;
  - opening a 210,000 wrap after the constant changes;
  - the round-trip check refuses a mismatched key;
  - a 409 leads to no further upload;
  - sign-in still succeeds when the rewrap call fails.

### 2.6 Alternatives considered

- **Argon2id on the device instead of PBKDF2.** It is stronger per unit of cost, but
  the `cryptography` package's Argon2 is pure Dart, slow and memory-heavy on low-end
  phones. It would also need a new `kdf` field and a format migration. Not worth it now.
- **Stop sending W to any token holder.** `/auth/me` could leave out `data_key`, and a
  password-verified route could return it instead. This closes path 2 entirely, but
  the current app reads W from `/auth/me` at sign-in, so it needs an app release
  first. It is a good follow-up after the rewrap work.
- **Stronger passwords.** Raise the sign-up minimum and check new passwords against a
  breached-password list (an offline top-N list, so nothing is sent out). This helps
  both oracles more than any iteration count.

### 2.7 Recommendation

Raise the iteration count to **600,000** for new wraps, and upgrade existing wraps
**opportunistically at the next sign-in** using the compare-and-swap rewrap route.
No data is touched, no keys change, no one is signed out, and old app versions keep
working. Gate the release on the device benchmark. As follow-ups, keep W out of
`/auth/me` and tighten the password rules.

---

## 3. Decisions requested

1. Backups: approve **B** (backup rules) **+ C** (encrypted export and import) and the
   small fixes, shipped together. D is deferred.
2. Key derivation: approve **600,000 for new wraps + upgrade at sign-in**, with the new
   `POST /auth/key/rewrap` route, gated on the benchmark.
3. Optional follow-ups: remove `data_key` from `/auth/me` (after an app release), and
   tighten the password rules.

Nothing in either plan changes existing users' data, encryption keys or production
settings when it ships. Both are additive and can be reverted.

---

## 4. Implementation status (after approval)

### 4.1 Backups: implemented (B + C + small fixes)

| Piece | Files | Tests |
| --- | --- | --- |
| Android backup rules. Only `FlutterSharedPreferences.xml` may leave the phone; Android 12+ cloud backup only when it can be end-to-end encrypted; phone-to-phone transfer kept; Android ≤11 only with `clientSideEncryption`. The secure-storage files (`FlutterSecureStorage.xml`, `FlutterSecureKeyStorage.xml`, file names checked in the plugin source) and `HomeWidgetPreferences.xml` are never included | `android/app/src/main/res/xml/data_extraction_rules.xml`, `backup_rules.xml`, `AndroidManifest.xml` | `test/core/security/android_backup_rules_test.dart` |
| Encrypted backup file `waffr-backup` v1 | `lib/core/security/ledger_backup_codec.dart` | `test/core/security/ledger_backup_codec_test.dart` |
| Export (the same snapshot a full sync push carries) and restore (merged like a first sync, add and update only, **never deletes**, marked for upload) | `lib/data/services/ledger_backup_service.dart` | `test/data/services/ledger_backup_service_test.dart` |
| Screen: Settings → Privacy and security → **النسخة الاحتياطية المشفّرة**. Save asks for a passphrase twice (10+ characters); restore asks to pick a file, enter the passphrase, then confirm. Guests see a one-line notice | `lib/screens/offline/settings/backup_screen.dart`, `privacy_security_screen.dart` | `settings_screens_test.dart` (renders in light, dark and reduced motion; the guest notice; refusals) |
| The legacy plaintext password is deleted at every start | `AuthSession.forgetLegacyPassword`, `main.dart` | `test/core/sync/auth_session_legacy_test.dart` |
| Shared PDFs older than a day are deleted at start | `cleanUpSharedPdfs`, `main.dart` | `test/screens/offline/report/shared_pdf_cleanup_test.dart` |

**File format.**
- The header holds only `format`, `version`, `created_at`, the KDF name, iterations and
  salt, and the cipher. The header is the AES-GCM associated data, so editing it (for
  example lowering the iterations) breaks the MAC.
- The body is gzip(JSON) sealed with AES-256-GCM. The account email travels inside the
  sealed body and is shown before restoring.
- Files are refused if they are over 50 MB, of a newer version, or ask for fewer than
  100,000 or more than 10,000,000 iterations (a crafted file cannot freeze the app).

**Restore semantics.**
- A local row newer than its copy in the backup stays.
- Deletes recorded in the backup are **not** applied. A restore can only add or update,
  never lose a row.
- On a signed-in phone the restored rows are uploaded at the next sync.

**New dependency.** `file_picker` 13.3.3, pinned. It provides the system document picker
for saving and opening the file, needs no storage permissions or plist keys, and the
app's `MainActivity` does not override `onActivityResult`, which the plugin needs.

**Not verified here: native builds.** No Android SDK or Xcode in this environment, so
no APK or IPA was built. The Dart side is analysed and tested. Before release:
- run the Build APK workflow on this branch;
- on a device, test save, open and restore;
- check that `adb shell bmgr backupnow com.waffr.app` produces a backup on a phone
  with a screen lock and none without one;
- do a phone-to-phone transfer.

### 4.2 Key derivation: benchmark gate failed, so the app is NOT changed

Measured with `tool/kdf_benchmark.dart`, the same pure-Dart PBKDF2 the app uses,
AOT-compiled, on one core of this environment's 2.3 GHz Xeon:

| Iterations | Time per derivation |
| --- | --- |
| 210,000 (today) | **0.84 s** |
| 600,000 | **2.40 s** |

The estimate in section 2.3 (0.3–0.9 s at 600,000) was **wrong by a wide margin**.
Phones run this AOT code at roughly their single-core speed relative to that Xeon.
That is an estimate, not a measurement:

- flagships about 1–2 s;
- mid-range phones about 3–5 s;
- low-end Cortex-A53 phones, common in the app's market, about 8–15 s **per sign-in**,
  and twice that for a password change.

That fails the "about 2 s on a low-end phone" gate. Today's 210,000 is probably
already 3–5 s on such phones.

What **is** done, since it is additive and harmless:
- the server route `POST /auth/key/rewrap`, with 13 tests (see 2.5);
- the benchmark tool.

`DataKeyStore.defaultIterations` stays at 210,000, and the app does not call the
route yet.

Options:

| Option | Low-end sign-in | Effort and risk |
| --- | --- | --- |
| **K-1. Native PBKDF2 in the app**: Android `SecretKeyFactory("PBKDF2WithHmacSHA256")`, iOS CommonCrypto `CCKeyDerivationPBKDF`, over the existing method channel, with the Dart code as fallback, cross-checked against the Dart output with fixed test vectors | expected well under 1 s at 600,000 (native code is typically 10× or more faster than pure Dart); to be measured | small Kotlin and Swift additions; can only be built and tested on your machines or CI |
| K-2. `cryptography_flutter`, native PBKDF2 on Android only | Android improves; iOS stays at pure-Dart speed | a new plugin with past device issues and a maintenance fork |
| K-3. Stay at 210,000 and rely on the follow-ups below | unchanged | none |

**Recommendation: K-1**, with 600,000 enabled only after the device benchmark on the
native path. *Update: K-1 was approved and Release A (native at 210,000) is
implemented; see `NATIVE_PBKDF2_PLAN.md` §9 and `KDF_BENCHMARK.md`.* Measure on a device with:
```bash
flutter run --release -t tool/kdf_benchmark.dart
```
Until then the follow-ups below shrink the exposure without making sign-in slower.

### 4.3 Planned follow-ups (approved for planning; not implemented)

**F-1. Keep the wrapped key away from token holders.**
- *Server, additive:* `POST /auth/key/unlock {password}` returns `data_key` after an
  Argon2 check, with a per-account limit.
- *App:* read the key from that route at sign-in, and keep `/auth/me` as a fallback for
  one release.
- *Next release:* `/auth/me` stops returning `wrapped_key` (it keeps `salt` and
  `iterations` so old apps still know a key exists).
- *Effect:* a stolen token no longer yields an offline password oracle.
- *Compatibility:* app versions before the change cannot unlock the key on a *new*
  sign-in until updated. Ship the server route two releases ahead and watch the version
  mix before removing the field.

**F-2. Stronger passwords.**
- Raise the sign-up minimum from 8 to 10 characters, applied to new passwords only;
  existing passwords keep signing in.
- Check new passwords against an offline list of the most common or breached passwords,
  bundled with the server (about 100,000 entries, hashed, a few MB), so nothing is sent
  to a third party.
- Show a strength hint in the app.
- Touches `RegisterRequest`, `ResetPasswordRequest` and `ChangePasswordRequest`, and
  the app's password fields and messages. Tests for each refusal.

**F-3. iOS: encrypt the ledger on the device.**
- Move the stores from `NSUserDefaults` to one file in Application Support.
- Seal that file with AES-256-GCM under a 32-byte key kept in the Keychain as
  `afterFirstUnlock`, not `ThisDeviceOnly`, so it travels only in encrypted backups and
  iCloud restores.
- Unencrypted Finder backups then hold only ciphertext.
- Needs:
  - a one-time migration (read the old prefs, write the sealed file, then remove the old
    keys only after a verified read-back);
  - writes moved off the UI isolate;
  - a crash-safe write (temp file and rename);
  - the backup file from 4.1 as the safety net if the Keychain key is ever lost.
- Android keeps the prefs file. Keystore keys never back up, so the same scheme there
  would make restores unreadable.
