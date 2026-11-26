# Native PBKDF2 on Android and iOS: implementation plan

Date: 2026-11-26. Status: **plan, waiting for approval.** No code has changed.
This follows `CLIENT_SECURITY_DECISIONS.md` §4.2: pure-Dart PBKDF2 at 600,000
iterations took 2.4 s on a server core, so it is too slow for low-end phones.

## 1. What exists today (inspected)

| Flow | Where | PBKDF2 use |
| --- | --- | --- |
| Create the data key (sign-up, or the first sign-in without one) | `DataKeyStore.create` → `wrap` → `_wrapKey` (`lib/core/security/data_key.dart`) | 1 derivation at `defaultIterations` (210,000), in a `compute()` isolate |
| Sign-in | `AuthSession._unlockDataKey` → `DataKeyStore.unwrap` → `_unwrapKey` | 1 derivation at the **stored** iteration count of the wrap |
| Password change | `AuthSession.changePassword`: `unwrap` with the old password, `wrap` with the new one | 2 derivations |
| Password reset | server drops the wrap and the sealed text; the next sign-in creates a new key | as for create |
| Encrypted backup file | `LedgerBackupCodec.seal` / `open` (`ledger_backup_codec.dart`), branch only, never released | 1 derivation at the file's stored count (600,000 for new files) |
| Sync, key storage | AES-256-GCM with the raw data key K (`DataCipher`); K kept in `flutter_secure_storage` | **none** |

**Exact parameters the native code must reproduce:**
- PBKDF2-HMAC-SHA256, 32-byte output.
- Password bytes = `utf8.encode(password)` of the Dart string: no Unicode
  normalisation, and unpaired surrogates become U+FFFD.
- Salt = the stored random bytes (16 for new wraps).
- Iterations = the value stored next to the wrap.

**Verified this session:** the app's Dart PBKDF2 gives byte-identical output to
Python's `hashlib.pbkdf2_hmac`, an independent C implementation, for an Arabic
password, an emoji password with skin tone, a 100-byte password (longer than the
HMAC block, so the key is hashed first), an empty password, an unnormalised
`e + ◌́` versus `é`, and the RFC 7914 vector.

**Server:** each wrap stores its own `key_salt` and `key_iterations`, and the server
accepts 100,000–10,000,000. `POST /auth/key/rewrap` already exists on this branch: it
checks the password, replaces the wrap only if it is still the one the device opened
(compare-and-swap), never lowers the count, and leaves `token_version` alone. It has
13 tests. **No server change is planned.**

## 2. Design

### 2.1 One derivation entry point with a safe fallback

A new file, `lib/core/security/pbkdf2.dart`:

```
Pbkdf2Engine.derive(passwordBytes, salt, iterations) → 32 bytes
  1. native (platform channel "waffr/pbkdf2")   if available and its self-test passed
  2. pure Dart (package:cryptography, today's code) in a compute() isolate otherwise
```

- **Bytes in, bytes out.** Dart does the UTF-8 encoding *once* and passes the raw bytes
  to native code. The native side never sees a string, so it cannot encode a password
  differently from Dart. (Java's `PBEKeySpec(char[])` converts characters itself, and
  that conversion has differed between providers and Android versions. It is a
  real risk for Arabic passwords, so it is **not used** in the app path.)
- **Known-answer self-test before first use.** Native is used only after it reproduces
  a fixed set of vectors: ASCII, Arabic, emoji, 100 bytes, empty, at low iteration
  counts, plus one at 210,000.
  - It runs once per app version and OS version; the result is cached in prefs.
  - It costs about 0.1–0.3 s native, in the background at start-up.
  - Any mismatch, exception or wrong output length disables native for that app and
    OS version and falls back to Dart. Only `native_pbkdf2_disabled` and a reason code
    are logged, never inputs or outputs.
- **Per-call failure:** a native exception, an output that is not 32 bytes, or a timeout
  (30 s) retries the same call in Dart. A failed native call can make that sign-in
  slower, never wrong.
- **Bounds checked on both sides:** iterations 1–10,000,000, salt 8–64 bytes,
  password at most 1,024 bytes, output exactly 32 bytes.

### 2.2 Android (Kotlin, no new dependency)

`android/app/src/main/kotlin/com/waffr/app/Pbkdf2.kt`, registered in `MainActivity.kt`.

- **Algorithm:** PBKDF2 per RFC 8018 written over `javax.crypto.Mac.getInstance("HmacSHA256")`,
  which Android serves from Conscrypt/BoringSSL (native code). The Mac is initialised
  once with the password bytes and reused for every iteration.
- **Runs off the main thread:** on a single background thread. The result is posted
  back on the main looper, so there is no ANR risk.
- **Cleanup:** password and intermediate buffers are zeroed after use.
- **Honest caveat:** Android does not expose BoringSSL's own PBKDF2 to apps. The loop
  above makes one JNI call per iteration, so the speed-up is **unknown until measured
  on a device**. For comparison only, the benchmark also times
  `SecretKeyFactory("PBKDF2WithHmacSHA256")` with an ASCII password, the output checked
  against the vectors.
- **If neither Android path meets the target,** the fallback option is a small NDK
  C++ routine of our own (SHA-256 + HMAC + PBKDF2, still no third-party code). It is
  verified against the same vectors. **I will ask before going that way**: it adds
  native crypto code that we maintain.

### 2.3 iOS (Swift, CommonCrypto, no new dependency)

`ios/Runner/Pbkdf2.swift`, registered in `AppDelegate.didInitializeImplicitFlutterEngine`
through `engineBridge.pluginRegistry.registrar(forPlugin:)`.

- `CCKeyDerivationPBKDF(kCCPBKDF2, bytes, len, salt, saltLen, kCCPRFHmacAlgSHA256, rounds, out, 32)`,
  called on the raw bytes from Dart.
- Runs on `DispatchQueue.global(qos: .userInitiated)`, with the result returned on main.
- The return status is checked and buffers are zeroed.
- The deployment target is 15.0; CommonCrypto has this API on every supported version.

### 2.4 Call sites

- `data_key.dart`: `_wrapKey` and `_unwrapKey` split into *derive* (engine, called from
  the main isolate, since platform channels live there) and *seal/open* (AES on 32
  bytes, cheap).
  - Public API unchanged: `create`, `wrap`, `unwrap`, `WrappedDataKey`.
  - Stored format unchanged.
- `ledger_backup_codec.dart`: derive through the engine; gzip and AES of the body stay
  in the background isolate. The file format is unchanged.
- `tool/kdf_benchmark.dart` becomes a small Flutter benchmark app (section 4). It is not
  part of the shipped app.

## 3. Rollout and migration (gradual, recoverable)

**Release A: native engine, nothing else changes.**
- Iterations stay at 210,000; the wraps, backup files and server are untouched.
- Sign-in and password change just get faster, and native correctness is proven in the
  field by the self-test, with Dart as the fallback.
- No user-visible change, no migration.

**Release B: only after the benchmark gate in section 4 passes.**
1. `DataKeyStore.defaultIterations` = the approved count (600,000 if it passes) for new
   wraps: sign-up, password change, the key after a reset.
2. **Upgrade at sign-in, in the background, never blocking it.** After `_unlockDataKey`
   has opened K with the password, and if the stored wrap is below the target:
   1. derive the KEK natively at the target count with a new salt, seal K, and open it
      again with the same KEK to compare with K (a round-trip check);
   2. **re-derive the same KEK with the other implementation (the Dart isolate)** and
      require identical bytes. Two independent implementations must agree before the
      account's only wrap is replaced. This takes some seconds in the background on slow
      phones; the user is already in the app;
   3. upload with `POST /auth/key/rewrap`, `expected_wrapped_key` = the old wrap.
      - `200`: done.
      - `409` (changed meanwhile): re-read `/auth/me` and stop.
      - `400`, `429`, `503` or a network error: stop, and try again at the next sign-in.
3. **Interruption at any point is harmless.**
   - Before the upload, the old wrap is untouched.
   - After the server swap but before the app hears back, the server holds a wrap of the
     **same** K. The next sign-in unwraps it at its stored count.
   - The local K and every encrypted row are never touched.
4. **Old app versions keep working.** They read the stored count and unwrap 600,000 wraps
   with pure Dart. That is correct, but slow on low-end phones (an estimated 8–15 s per
   sign-in).
   - Mitigation: start Release B only once most active users have Release A.
   - I would like your rule for that: for example, a share of installs on the Play
     Console, or a waiting period.
   - Worst case is a slow sign-in on an outdated app, never lost access.
5. **Rollback:** revert the constant. Wraps already at 600,000 stay valid for every
   version.

No forced sign-out, no password reset, no change to the encrypted data or to existing
backups at any step.

## 4. Device benchmarks (requirement: real devices, low-end included)

**I cannot run on real devices from this environment.** There is no Android SDK, no
Xcode, and no phone is attached.

The benchmark app (`tool/kdf_benchmark.dart`, run with
`flutter run --release -t tool/kdf_benchmark.dart`):
- shows and prints JSON with the device model, OS and CPU ABI;
- reports the self-test result;
- times, at 210,000 and 600,000 (5 runs each, median and worst), the Dart engine, the
  native engine, and on Android the `SecretKeyFactory` variant;
- checks every output against the vectors.

**Proposed gate:** at least 3 Android devices, including one low-end phone (Cortex-A53
class, for example a Galaxy A0x/A1x or Redmi 9A), plus an iPhone at the low end of
iOS 15+ support (iPhone 8 or SE 2). On every device, the native engine's **worst of 5
runs at the target count must be ≤ 2.0 s**.
- If 600,000 fails on any device, I report the numbers and propose the highest count
  that passes everywhere, if that is above 210,000. **Nothing is changed without your
  approval.**

**How to get the device numbers (your choice):**
1. Connect your computer through Remote Control, with the phones on USB and Xcode for
   the iPhone. I can then build, install and run the benchmark myself and collect the
   output.
2. Firebase Test Lab with your Google Cloud project (`gcloud` is available here). It
   runs on real low-end physical devices. It needs a project and credentials from you,
   and has a cost; iOS needs a signed test build.
3. You install the benchmark build (APK from CI) and send me the printed JSON.

## 5. Tests

| Area | Tests |
| --- | --- |
| **Vectors (identical output)** | One `test/fixtures/pbkdf2_vectors.json`, generated by `tool/gen_pbkdf2_vectors.py` with Python `hashlib` (an independent implementation). Cases: RFC 7914, ASCII, Arabic, emoji, 100 bytes, empty, unnormalised text, iterations 1 / 2 / 4,096 / 210,000 / 600,000, salts of 16 and 32 bytes. Checked by **Dart** (`flutter test`), **Kotlin** (JUnit on the JVM; a device test also runs on Android's own Conscrypt), and **Swift** (XCTest in `RunnerTests`). A Dart test checks that the copies in the Android and iOS test folders are byte-identical to the source file. |
| **Engine** | A mocked channel returning the right output, a wrong output (self-test fails, Dart used), a missing plugin, a `PlatformException`, a timeout, a wrong output length; the self-test result is cached per app and OS version; bound checks. |
| **Compatibility** | A 210,000 wrap made by Dart opens through native and vice versa; existing fixture wraps open unchanged; backup files sealed through either path open through the other; `WrappedDataKey` JSON is unchanged. |
| **Migration** | The upgrade at sign-in: success; `409`; `400`; network failure; a native/Dart mismatch means no upload; a round-trip mismatch means no upload; interrupted after the server swap (the next sign-in opens the new wrap); repeated sign-ins do nothing once at the target; sign-in succeeds even when every upgrade step fails; an old (Dart-only) app opens a 600,000 wrap. |
| **Backup restore** | Restore from files at 210,000, 600,000 and an odd count; wrong passphrase; native unavailable during restore. |
| **Backend** | Already covered (13 rewrap tests). Add one for the edge "stored count equals target" if needed. |

**Build checks:**
- I can run the Dart tests and the JVM Kotlin unit tests here (Java is installed).
- Android Gradle builds, Android device tests and all iOS builds need the Android SDK
  and Xcode, so they run on your machine or CI.

## 6. Files

**New**
- `lib/core/security/pbkdf2.dart`
- `android/app/src/main/kotlin/com/waffr/app/Pbkdf2.kt`
- `android/app/src/test/kotlin/com/waffr/app/Pbkdf2Test.kt` and the copied vectors
- `ios/Runner/Pbkdf2.swift` (added to the Runner target in `project.pbxproj`)
- `ios/RunnerTests/Pbkdf2Tests.swift` and the copied vectors (added to the RunnerTests
  target)
- `test/fixtures/pbkdf2_vectors.json`, `tool/gen_pbkdf2_vectors.py`
- `test/core/security/pbkdf2_engine_test.dart`, `pbkdf2_vectors_test.dart`
- `test/core/sync/key_upgrade_test.dart` (Release B)

**Changed**
- `lib/core/security/data_key.dart` (split derive from seal; in Release B, the new
  default)
- `lib/core/security/ledger_backup_codec.dart`
- `lib/core/sync/auth_session.dart` (Release B: the background upgrade)
- `android/app/src/main/kotlin/com/waffr/app/MainActivity.kt`
- `ios/Runner/AppDelegate.swift`
- `android/app/build.gradle.kts` (test dependency: JUnit, `testImplementation` only;
  it is not shipped)
- `tool/kdf_benchmark.dart`
- READMEs and `CLIENT_SECURITY_DECISIONS.md`

**Third-party dependencies:** none added to the app. JUnit for JVM tests only.

## 7. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Native output differs from Dart for some input (encoding, long password, a device crypto bug) | A wrap that other devices cannot open would mean lost sealed text | Raw bytes only; the shared vectors in all three languages; the self-test before use; Dart fallback; **dual-implementation agreement before any rewrap** |
| The Android Mac-loop speed-up is too small | 600,000 is not reachable | Measure first; NDK contingency only with your approval; otherwise stay at the highest count that passes |
| A platform-channel call blocks the UI or triggers an ANR | A frozen sign-in | A background thread or queue on both platforms; a Dart-side timeout falls back |
| Older app versions are slow at 600,000 | A slow but working sign-in for outdated apps | Two-phase rollout; you choose the cut-over rule |
| Builds I cannot run here (Gradle, Xcode) | A compile error found late | Kotlin and Swift kept small and standard; JVM tests run here; you or CI build before any release |
| The self-test adds start-up work | About 0.1–0.3 s once per app version | Runs in the background after the first frame, and the result is cached |

## 8. Approval requested

1. The design above: bytes-only channel, self-test plus Dart fallback, the Mac-loop on
   Android, CommonCrypto on iOS, two releases, and the dual-implementation check before
   a rewrap.
2. The benchmark gate (≤ 2.0 s worst-of-5 on the device matrix) and how I get the device
   numbers (option 1, 2 or 3 in section 4).
3. The rule for starting Release B (when old app versions are rare enough).

---

## 9. Status: Release A implemented (Release B not started)

Approved scope: native PBKDF2 at the existing 210,000 iterations, with no change to the
formats, the counts, the server, or background upgrades.

### What changed

| Area | Files |
| --- | --- |
| Engine: native first, Dart fallback, self-test | `lib/core/security/pbkdf2.dart` (new) |
| Callers | `lib/core/security/data_key.dart`, `lib/core/security/ledger_backup_codec.dart` |
| Android | `android/app/src/main/kotlin/com/waffr/app/Pbkdf2.kt` (algorithm, plain JVM), `Pbkdf2Channel.kt` (channel on a background thread), `MainActivity.kt` (registration), `android/app/build.gradle.kts` (JUnit for tests only; `-P waffrBenchmark=true` gives the benchmark build its own package), `AndroidManifest.xml` (label placeholder) |
| iOS | `ios/Runner/AppDelegate.swift` (CommonCrypto and the channel; in the existing file, so the Xcode project is untouched) |
| Vectors | `tool/gen_pbkdf2_vectors.py` writes `test/fixtures/pbkdf2_vectors.json`, its Android copy, the Swift block in `ios/RunnerTests/RunnerTests.swift`, the runtime self-test block in `pbkdf2.dart`, and `tool/kdf_benchmark_vectors.dart`. `--check` fails if any copy is stale |
| Compatibility fixture | `tool/gen_crypto_compat_fixture.py` writes `test/fixtures/crypto_compat.json`: wrapped keys and a backup file made by Python, independent of the app |
| Benchmark | `tool/kdf_benchmark.dart`, `KDF_BENCHMARK.md` |
| CI | `.github/workflows/native-crypto.yml`: Dart tests; vector sync; the benchmark APK as an artifact; Kotlin JUnit through Gradle; Swift XCTest on an iOS simulator |

### Two refinements to the plan, both stricter

1. **Native is used for reading only.**
   - Unwrapping the data key and opening a backup file use native, then Dart if the key
     fails the AES-GCM check.
   - Keys that protect **new** data (a new wrap or a new backup file) are always
     derived by the Dart code earlier app versions used. Native runs alongside only as
     a check, and a disagreement switches it off for the process
     (`Pbkdf2Engine.deriveForWriting`).
   - So a native fault can never be written into anything, even one the self-test
     misses. A test with a native side that is wrong only above 4,096 iterations proves
     this.
   - The cost: new wraps (sign-up, password change) and new backup files keep today's
     timing. The frequent operation, sign-in, gets the speed-up.
2. **The self-test runs in every process, with the 12 cheap vectors** (a few
   milliseconds natively), instead of a cached run that includes 210,000. That makes the
   cache unnecessary. The expensive vectors are checked by the unit tests and on every
   device by the benchmark app.

### Results here

| Check | Result |
| --- | --- |
| Flutter tests | **1,298 passed** (65 new): vectors, engine faults and fallbacks, compatibility, benchmark report, plus all earlier tests |
| `flutter analyze` | no issues |
| Vector copies in sync (`gen_pbkdf2_vectors.py --check`) | yes |
| Kotlin `Pbkdf2.kt` on the JVM (Kotlin 2.2.20, JUnit) | 4 tests passed, all 15 vectors including 600,000 |
| Backend tests | 455 passed; the backend is unchanged in this step |
| Android Gradle build, Swift build and XCTest | **not run here** (no Android SDK or Xcode). They run in the *Native crypto* workflow |
| Device benchmarks | **none yet.** The first device is the Galaxy S23 Ultra; see `KDF_BENCHMARK.md` |

### Before Release B (needs your approval; not built)

**Proposed adoption threshold.** At least **95% of active installs** on Release A or
later, on both the Play Console and App Store Connect, held for **30 days**. Until then,
an account upgraded to the higher count would make any remaining old app slow to sign
in (pure Dart).

**Proposed guard so old app versions cannot be hurt.**
- From Release A on, the app would send its build number (`X-Waffr-App-Version`) with
  `/auth/login` and `/sync`.
- The server would remember, per account, the lowest version seen in the last 60 days.
- The background upgrade would run only when every device on that account reported a
  native-capable version.
- This is a server change in the key-upgrade path, so it is **not implemented**. It
  needs your approval together with Release B.
- If you want the header added in Release A already, so the data exists when Release B
  is decided, that is a small additive app change. Say so.

**Device gate (unchanged):** at least 3 Android phones including a low-end one, plus an
older iPhone, three runs each, with the worst native run ≤ 2,000 ms at the proposed
count.
