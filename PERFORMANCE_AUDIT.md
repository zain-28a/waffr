# Motion and performance continuation

Scope: finish the animation/speed work from the interrupted Claude session and
verify the wallet expression. The larger ten-part project refactor remains
deferred, as requested in the final instructions of that session.

## Corrected paths

| Path | Problem and correction |
| --- | --- |
| Shell and tab summaries | Kept-alive pages kept listening to stores. Each cached tab now has a visibility `TickerMode`; top-level summary builders disconnect while hidden and catch up on return. |
| Profile health | Every notification started another fact load. Refreshes now coalesce, run serially, and wait until the profile is visible. |
| Money animation | Glyph layout ran on each frame; separators ignored text scaling. Measurements are cached by style/scale, and rapid updates choose the number using the displayed animation curve. |
| Intro/streak effects | Delayed entrances survived disposal or accessibility changes. Owned timers/curves are canceled/disposed and reduced motion shows final values. |
| Smart effects | Idle/invisible glow kept ticking; stopping a spark could restart on rebuild or reset a newer spin. Explicit settling state and visible-page checks remove those paths. |
| Insight generation | Obsolete loads could still analyze; an uncancellable pause outlived navigation. Run guards and a cancellable pause stop obsolete work, and typing layouts are limited to about 30 updates/second. |
| Amount/currency menus | Curves were recreated in builds or not disposed. Curves now live with their controllers and honor reduced motion. |
| Wallet score | New savings history was always divided by three months. It now uses the existing observed-history average and the 20%-of-income target, without comparing savings to spending. |

## Validation

Run from the repository with Flutter 3.47.7:

```sh
flutter analyze --no-pub
flutter test --no-pub --concurrency=2
flutter build web --no-pub --no-web-resources-cdn
TEST_DATABASE_URL=postgresql://waffr@127.0.0.1:55432/waffr_test \
  /workspace/waffr-venv/bin/python -m pytest backend/tests -q
```

The database URL above is only for the disposable local test database: that
suite truncates its tables. Never point it at a user's production database.

Focused widget tests assert that hidden tabs skip data-triggered builds and
read the newest value on return, and that hidden/transparent/reduced-motion
effects schedule no animation callbacks once settled. They cover interruption,
disposal, rapid retargeting, text scaling and generation cancellation.

Verified in this cloud environment on 2026-10-11:

- Flutter static analysis: no issues; all 112 Flutter tests passed.
- Backend: all 40 PostgreSQL-backed security/API tests passed.
- Web release build succeeded. Chromium guest onboarding and two rounds of
  navigation through all five tabs completed with no page errors.
- The actual profile widget shows a smiling band for income 1,000, spending
  600 and savings 200, then updates its expression after withdrawing savings.
  This complements the isolated score tests and catches refresh regressions.

For the browser check, serve `build/web`, enable Flutter's accessibility
semantics, continue as a guest, complete theme selection, then select Reports,
Savings, Internet, Profile and Home twice. Confirm the profile renders and the
browser reports no unhandled exceptions.

These checks establish lifecycle correctness and removal of avoidable work.
They do not establish an FPS or battery improvement on a phone. Physical-device
profiling, native notification/home-widget behavior and Android/iOS packaging
remain separate checks. No APK build is part of this continuation.
