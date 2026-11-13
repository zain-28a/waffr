# First-launch introduction

| File | Main entry point | What it is |
| --- | --- | --- |
| `onboarding_screen.dart` | `OnboardingScreen` | Three swipeable pages where the wallet character presents tracking, saving and the on-device analysis, with page dots, a "next" / "start" button and a skip link. |

`main.dart` shows it once, on a fresh install, before the sign-in choice
(`_FlowStage.onboarding`). Finishing or skipping stores `onboarding_seen` in
prefs. People who already use the app (`first_launch` is false) never see it.

Tests: `test/screens/offline/onboarding/onboarding_screen_test.dart` and the
boot-flow cases in `test/widget_test.dart`.
