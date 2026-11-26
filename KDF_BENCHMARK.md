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

## 7. Results log

Raw reports are in `benchmarks/kdf/`, one file per run, exactly as the app printed them.

| Date | Device | Chip | Android | Run | Self-test | Vectors | Native 210k (median / worst) | Native 600k (median / worst) | Key factory 600k worst | Dart 210k worst | Dart 600k worst |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-26 | Samsung Galaxy S23 Ultra (SM-S918B) | Snapdragon 8 Gen 2 (SM8550) | 17 (SDK 37) | 1 of 3 | passed | 15/15 match | 85 / 86 ms | 275 / 275 ms | 472 ms | 1,261 ms | 13,623 ms (others 3,387 and 3,620) |
| 2026-11-26 | Samsung Galaxy S23 Ultra (SM-S918B), run 2 | Snapdragon 8 Gen 2 (SM8550) | 17 (SDK 37) | 2 of 3 | passed | 15/15 match | 83 / 84 ms | 233 / 235 ms | 414 ms | 1,064 ms | 3,299 ms (others 3,003 and 3,103) |
| 2026-11-26 | Samsung Galaxy S23 Ultra (SM-S918B), run 3 | Snapdragon 8 Gen 2 (SM8550) | 17 (SDK 37) | 3 of 3 | passed | 15/15 match | 96 / 96 ms | 275 / 280 ms | 526 ms | 1,261 ms | 5,671 ms (others 4,283 and 4,267) |
| 2026-11-26 | Samsung Galaxy A56 5G (SM-A566B), reported by Tala | Exynos 1580 (s5e8855) | 16 (SDK 36) | 1 of 3 | passed | 15/15 match | 81 / 82 ms | 325 / 326 ms | 586 ms | 1,577 ms | 4,505 ms (others 4,201 and 4,296) |
| 2026-11-26 | Samsung Galaxy A56 5G (SM-A566B), run 2, reported by Tala | Exynos 1580 (s5e8855) | 16 (SDK 36) | 2 of 3 | passed | 15/15 match | 82 / 85 ms | 279 / 322 ms | 585 ms | 1,535 ms | 4,606 ms (others 4,479 and 3,904) |
| 2026-11-26 | Samsung Galaxy A56 5G (SM-A566B), run 3, reported by Tala | Exynos 1580 (s5e8855) | 16 (SDK 36) | 3 of 3 | passed | 15/15 match | 88 / 92 ms | 250 / 264 ms | 507 ms | 1,369 ms | 4,398 ms (others 4,001 and 4,138) |
| 2026-11-26 | Xiaomi 2404ARN45A (Redmi-class, Helio G99 class), run 1 | MediaTek MT6769 (Helio G85/G95-class, low-end) | 14 (SDK 34) | 1 of 3 | passed | 15/15 match | 234 / 240 ms | 664 / 673 ms | 1,250 ms | 3,261 ms | 9,389 ms (others 9,317 and 9,322) |
| 2026-11-26 | Infinix X6871 (GT 20 Pro), reported by مغناطيسية | MediaTek Dimensity 8350 class (MT6896) | 16 (SDK 36) | 1 of 3 | passed | 15/15 match | 94 / 94 ms | 268 / 280 ms | 481 ms | 1,188 ms | 3,423 ms (others 3,322 and 3,371) |
| 2026-11-26 | Infinix X6871 (GT 20 Pro), run 2, reported by مغناطيسية | MediaTek MT6896 | 16 (SDK 36) | 2 of 3 | passed | 15/15 match | 97 / 106 ms | 279 / 284 ms | 494 ms | 1,163 ms | 3,365 ms (others 3,321 and 3,359) |

### Reading of run 1 (S23 Ultra)

- **Correctness on a real phone: confirmed.**
  - Android's own provider (AndroidOpenSSL/Conscrypt) reproduces all 15 vectors
    byte-for-byte, including Arabic, emoji, long, empty and unnormalised passwords, and
    210,000 and 600,000 iterations.
  - The app's self-test passed. This is the evidence Release A needs on this device.
- **Speed-up: about 15×.** At today's 210,000, a sign-in derivation goes from about 1.26 s
  in Dart to 85 ms. The chosen Mac loop is also 1.7× faster than the platform
  `SecretKeyFactory`, which supports that choice.
- **Native is steady:** 5 runs within 3 ms. Dart was not: one 600,000 run took 13.6 s
  against 3.4–3.6 s for the others (the first run after the native and key-factory
  runs). That looks like scheduling on a slower core or a burst of background work, and
  it shows how variable the pure-Dart path is. In Release A that path is still used for
  new wraps and backup files, so those can take a few seconds on such phones.
- **What it does not show: the low end.** Scaling by rough single-core ratios (an
  estimate only), a Cortex-A53 phone could be 5–7× slower. That puts native 600,000
  around 1.4–2.0 s, right at the 2 s target. **The low-end run is the one that decides
  Release B.**

### Reading of run 1 (Galaxy A56 5G, a mid-range phone)

- **Correctness: confirmed again** on a second chipset (Exynos) and Android version: all 15
  vectors match, self-test passed, provider AndroidOpenSSL.
- **Native at 600,000: 325 ms worst**, about 6× under the 2 s target. At 210,000 (Release A):
  81 ms.
- **Pure Dart at 600,000: 4.2–4.5 s**, steady this time (no 13 s outlier). This is the cost
  of writing a new wrap through Dart (decision D-4), on a **mid-range** phone.
- **Ratios hold across both phones:** native 600,000 is about 1.2× slower on the A56 than on
  the S23 Ultra, Dart about 1.2×, and Dart is consistently about 13× slower than native.
- **Still not the low end.** To miss the 2 s target, native would have to run about 6×
  slower than on this mid-range phone. That is possible on the weakest hardware (an
  estimate, not a measurement), so **the low-end Android run remains the deciding one**.
- **Gate status for Release B** (needs 3 Android phones incl. one low-end, 3 runs each):
  2 phones reported (S23 Ultra, A56), **1 run each**, no low-end phone yet. iOS is not
  distributed (see `RELEASE_B_READINESS_PLAN.md`), so the iPhone gate applies only when iOS is.

### Reading of run 1 (Infinix GT 20 Pro, a mid-range MediaTek phone)

- **Correctness: confirmed on a third chipset family** (MediaTek MT6896): all 15 vectors match,
  self-test passed.
- **Native 600,000: 268–280 ms (worst 280)**, about 7× under the 2 s target; at 210,000 (Release A): 94 ms.
- **Pure Dart 600,000: 3.3–3.4 s**, steady (no outlier this time).
- **Gate status for Release B:** three phones now reported (S23 Ultra, A56, GT 20 Pro), one run each.
  The gate still needs **a low-end Android phone** and **two more runs per device**.

### Reading of run 2 (Infinix GT 20 Pro, second run)

- **Repeats run 1:** all 15 vectors match and the self-test passed again.
- **Native 600,000: 274–284 ms (worst 284)**, consistent with run 1 (worst 280). Still about 7× under the 2 s target.
- **Pure Dart 600,000: 3.3–3.4 s**, consistent with run 1.
- **Gate status:** this device now has 2 of 3 runs. Still missing: one more run on this device, and
  a low-end Android phone with 3 runs.

### Reading of run 2 (Galaxy A56 5G, second run)

- **Repeats run 1:** all 15 vectors match and the self-test passed.
- **Native 600,000: 269–322 ms (worst 322).** Median unchanged (279 ms). The 322 ms outlier is still far under the 2 s target.
- **Pure Dart 600,000: 3.9–4.6 s**, slightly wider spread than run 1 (4.2–4.5 s). Still the slowest path by about 14×.
- **Gate status:** this device now has 2 of 3 runs. Still missing: one more run on this device, and
  a low-end Android phone with 3 runs.

### Reading of run 1 (Xiaomi 2404ARN45A, MediaTek MT6769, low-end)

- **This is the low-end device the gate asked for.** Correctness holds: all 15 vectors match,
  self-test passed, on Android 14 with AndroidOpenSSL.
- **Native 600,000: 661–673 ms (worst 673)**, about 3× under the 2 s target. At 210,000
  (Release A): 234 ms.
- **Pure Dart 600,000: 9.3–9.4 s.** Steady, but about 14× slower than native, and well over the
  target. That is the write path D-4 keeps for rewrap (90-second budget) and the reason Release A
  stays on native writes for sign-up, password change and backup files.
- **Platform comparison:** Android's SecretKeyFactory at 600,000 takes 1.25 s here, so the
  chosen HMAC loop is still about 1.9× faster on this device.
- **Gate status:** the low-end device now has 1 of 3 runs; the target 2 s is met with room to spare
  on this phone. Still missing: two more runs on this device, and a third Android phone at the
  low end for the gate's "at least 3 devices" rule, plus two more runs on each other device.

### Reading of run 3 (Galaxy A56 5G, third run: the A56 is complete)

- **All 15 vectors match and the self-test passed again.**
- **Native 600,000: 250–264 ms (worst 264)**: the fastest A56 run so far, and the A56 now has
  **3 of 3 runs**. Still about 7× under the 2 s target.
- **Pure Dart 600,000: 4.0–4.4 s**, within the range of runs 1 and 2.
- **Gate status:** Galaxy A56 and S23 Ultra have 3 runs each on record for the A56, and the S23 Ultra
  still has 1 run. Infinix GT 20 Pro has 2 of 3 runs, and the Xiaomi low-end device has 1 of 3.
  The gate still needs: the S23 Ultra runs 2 and 3, the GT 20 Pro run 3, two more Xiaomi runs, and a
  third Android phone at the low end.

### Reading of run 2 (Galaxy S23 Ultra, second run)

- **All 15 vectors match and the self-test passed again.**
- **Native 600,000: 232–235 ms (worst 235)**, consistent with run 1 (median 275 ms, worst 275 ms).
  Still about 8× under the 2 s target.
- **Pure Dart 600,000: 3.0–3.3 s**, a little faster than run 1 (3.4–3.6 s, with one outlier earlier).
- **Gate status for the S23 Ultra:** 2 of 3 runs. Still missing: run 3.

### Reading of run 3 (Galaxy S23 Ultra, third run: the S23 Ultra is complete)

- **All 15 vectors match and the self-test passed.** The S23 Ultra now has **3 of 3 runs**.
- **Native 600,000: 272–280 ms (worst 280)**, the same range as run 1 (worst 275).
- **Pure Dart 600,000: 4.3–5.7 s.** The 5.7 s run is the slowest pure-Dart run recorded for this phone
  (the 3.0–3.6 s runs of runs 1 and 2 are the typical value). Another reason to keep native writes for
  new data (D-4).
- **Gate status:** Galaxy A56 and S23 Ultra both have 3 of 3 runs. Infinix GT 20 Pro still has 2 of 3,
  Xiaomi (low-end) has 1 of 3. The gate still needs: one more GT 20 Pro run, two more Xiaomi runs, and a
  third Android phone at the low end.
