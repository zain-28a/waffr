# PBKDF2 device benchmark: how to install and run it

This is for the Release B decision in `NATIVE_PBKDF2_PLAN.md`. It measures how long one
key derivation takes on a real phone, and checks that the phone's native
implementation gives exactly the expected bytes.

**It is a separate app.**
- Package `com.waffr.app.kdfbench`, named **"Waffr KDF benchmark"**.
- It installs next to Waffr and cannot see or change Waffr's data.
- It never contacts a server, and no account is involved.
- It is signed with a debug key and is not for the store.

## 1. Get the APK

**The current build:**
- Run: https://github.com/zain-28a/waffr/actions/runs/45852020847
- Artifact: `waffr-kdf-benchmark-android`, available until 2026-12-26. GitHub asks you to
  sign in to download artifacts, even for a public repository.
- File: `waffr-kdf-benchmark-3ff52a0.apk` (50.9 MB)
- SHA-256: `ab202c93647cbb04547a8d28ad7f85c6722799cb5ad50ac0c1a443662a0d34ab`

The **Native crypto** GitHub Actions workflow builds it on every push to the branch
that touches the native code.

1. Open the repository on GitHub → **Actions** → **Native crypto**. Pick the latest
   green run for the branch `claude/affectionate-wozniak-9zle5o`.
2. Under **Artifacts**, download `waffr-kdf-benchmark-android` (a zip) and unzip it.
3. It holds `waffr-kdf-benchmark-<commit>.apk` and `SHA256SUMS.txt`. Optionally, check
   the download:
   ```bash
   sha256sum -c SHA256SUMS.txt
   ```
4. Note the 7-character `<commit>` in the file name. The report repeats it, so results
   can be tied to the exact code.

## 2. Install on the Samsung Galaxy S23 Ultra

**Option A, on the phone:**
1. Copy the APK to the phone (USB, Google Drive, or Quick Share).
2. Open it from **My Files**. When asked, allow **My Files** to install unknown apps
   (Settings → Apps → My Files → Install unknown apps).
3. Play Protect may warn that the app is unknown, because it is debug-signed. Choose
   **More details → Install anyway**.

**Option B, from a computer with adb** (USB debugging on):
```bash
adb install -r waffr-kdf-benchmark-<commit>.apk
```

## 3. Run it (the same way every time)

Conditions, so runs are comparable:
- Battery above 50% or charging.
- **Battery → Power saving off**.
- On Samsung, **Battery → Performance profile: Standard**, not *Light*. Note in your
  message if it was something else.
- Close other apps. Leave the phone at room temperature, not straight after gaming or
  charging hot.
- Keep the screen on and stay in the app while it runs.

Steps:
1. Open **Waffr KDF benchmark** and tap **Run benchmark**. It takes about 1–3 minutes;
   the pure-Dart runs are the slow part.
2. When it says **Done**, tap **Copy results** (or **Share results**) and send me the
   text.
3. **Repeat three times**, waiting about 2 minutes between runs, and send all three
   reports. Thermal throttling and background work vary from run to run, so one run is
   not enough.

With adb, the report is also printed on one line in the log:
```bash
adb logcat -d | grep KDF_REPORT
```

## 4. What the report contains

| Field | Meaning |
| --- | --- |
| `commit`, `build_mode` | Which code ran (it must say `release`) |
| `device` | Manufacturer, model, chipset (`soc`), Android version and SDK level, CPU count, and the HMAC provider (Conscrypt is expected) |
| `self_test_passed` | The app's runtime check of the native code; it must be `true` |
| `vectors_all_match`, `vectors` | All 15 shared vectors through the native code, including the Arabic, emoji, long, empty, unnormalised, 210,000 and 600,000 ones; it must be `true` |
| `timings` | One derivation, in ms, at 210,000 and 600,000 iterations: `native` (5 runs), `android_secret_key_factory` (5 runs, for comparison only; the app does not use it) and `dart` (3 runs). One warm-up run is not counted. Each has `median_ms` and `worst_ms` |
| `native_worst_ms_within_target` | Whether the worst native run is ≤ 2,000 ms at each count |

## 5. How the results will be used

- **Release A** (the native engine at today's 210,000) only needs `self_test_passed` and
  `vectors_all_match` to be `true` on real phones. It does not change any stored data.
- **Release B** (raising the count) is **not** decided by this device. The gate in
  `NATIVE_PBKDF2_PLAN.md` §4 needs at least three Android phones, **including a low-end
  one**, plus an older iPhone. Each needs three reports in which the worst native run
  is ≤ 2,000 ms at the proposed count. A flagship like the S23 Ultra shows the best
  case, not the floor.
- iOS: the same app runs on an iPhone, but needs a signed build from Xcode
  (`flutter run --release -t tool/kdf_benchmark.dart`). I will prepare those steps when
  we get to the iPhone.

## 6. Remove it afterwards

Long-press the app → Uninstall, or:
```bash
adb uninstall com.waffr.app.kdfbench
```
Waffr itself is not affected.
