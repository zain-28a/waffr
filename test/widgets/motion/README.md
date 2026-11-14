# test/widgets/motion

Widget tests for `lib/widgets/motion`.

Most tests are smoke tests built with `smokeTestScreen` / `smokeTestWidget`
from `test/helpers/widget_harness.dart`: each pumps the screen or widget
with the app theme, Arabic locale and RTL direction on a 390x844 phone
view, in light and dark (and with sample data where a screen reads the
stores), plus once with reduced motion, and fails on any exception or
layout overflow. Sheets and dialogs are opened through their public
`show…` function from a `SheetLauncher` page.

| File | Covers |
| --- | --- |
| `active_listenable_builder_test.dart` | ActiveListenableBuilder: hidden tabs skip rebuilds and catch up when shown. |
| `motion_lifecycle_test.dart` | Motion widget lifecycles: reveals, rolling money and text, glows and the streak number cancel timers and honor reduced motion and text scaling. |
| `motion_test.dart` | Motion basics: reduced-motion page transitions and reveals that keep their child alive after the entrance. |
| `motion_widgets_test.dart` | Smoke tests for the shared motion widgets at rest and mid-animation. |
| `origin_route_test.dart` | OriginPageRoute: the page grows out of the tapped widget, shrinks back into it on pop and on the back gesture, leaves the page below in place, and jumps with reduced motion. |
| `slide_route_test.dart` | The page transition: a page slides in from the right, leaves the same way and follows the predictive back gesture. |
| `tap_haptics_test.dart` | TapHaptics and AppHaptics: one light cue per tap on something tappable, silence elsewhere, and the on/off setting. |

Run them with:

```
flutter test test/widgets/motion
```
