# lib/widgets/brand

Waffr's identity pieces: the logo, the top bars, the avatar and the streak
celebration.

| File | Contents |
| --- | --- |
| `waffr_logo.dart` | `WaffrLogo` (the official wallet mark asset) and `WaffrSplash` (shown by `main.dart` while theme and gate flags resolve; matches the app background). |
| `waffr_mood_logo.dart` | `WaffrMoodLogo`: the logo as a character (mouthless `assets/brand/waffr_logo_mouthless.png` plus the current `SmileForm` from `WalletMood`, morphing between faces; optional idle breathing). `MascotReactions.instance.play(...)` makes every mascot hop (`happy`) or gulp (`gulp`). |
| `waffr_mouth.dart` | `MouthShape` (one vector pose per `SmileForm`, in shares of the logo square), `MouthTween` and `MouthPainter`. Shared by `WaffrMoodLogo` and the profile backdrop. |
| `waffr_page_header.dart` | `WaffrPageHeader` (fixed-height liquid-glass top bar hanging from the screen edge, with an optional `center` widget pinned to the middle; `elevated` thickens the glass) and `WaffrBackHeader` (back arrow + centered title for every pushed screen). |
| `profile_avatar.dart` | `ProfileAvatar`: person icon on an accent circle, crossed out for guests (`signedIn: false`). There are no profile photos. |
| `goal_celebration.dart` | `GoalCelebrationOverlay`: the moment shown once when a savings goal completes (the wallet hops inside a bursting ring, with the goal's name; tap skips; calls `onFinished`). |
| `streak_celebration.dart` | `StreakCelebrationOverlay` (blur, logo rise, rolling day count, fade; tap skips; calls `onFinished`) and `RollingNumber` (odometer digits driven by a 0..1 progress). |

Who uses them:

- `WaffrMoodLogo`: `AppShell` header, onboarding, login and the lock screen.
  Reactions are played by the add-income, add-expense and manual-save sheets.
- `WaffrLogo` / `WaffrSplash`: `main.dart`, login, theme select, streak card,
  and the celebration overlay.
- `WaffrPageHeader` / `WaffrBackHeader`: `AppShell` and nearly every
  pushed screen (settings, notifications, smart analysis, login flows).
- `ProfileAvatar`: profile, settings and account screens.
- `GoalCelebrationOverlay`: `AppShell`, when a goal completes while the app
  is open (goals already complete at launch are not replayed).
- `StreakCelebrationOverlay`: `AppShell`, when `UsageStreakService.takeIncrease()`
  reports a streak that grew on this open.

Conventions:

- Pushed screens use `WaffrBackHeader` rather than building a header by
  hand, so every screen's top bar matches.
- Colors come from `AppPalette`, timings from `AppMotion`; the celebration
  settles immediately with reduced motion and removes itself when done, so
  it never stays over the home screen.
