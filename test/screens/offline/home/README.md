# test/screens/offline/home

Widget tests for `lib/screens/offline/home`.

Most tests are smoke tests built with `smokeTestScreen` / `smokeTestWidget`
from `test/helpers/widget_harness.dart`: each pumps the screen or widget
with the app theme, Arabic locale and RTL direction on a 390x844 phone
view, in light and dark (and with sample data where a screen reads the
stores), plus once with reduced motion, and fails on any exception or
layout overflow. Sheets and dialogs are opened through their public
`show…` function from a `SheetLauncher` page.

| File | Covers |
| --- | --- |
| `dashboard_test.dart` | Smoke tests for the home tab (HomeScreen) and its add-expense / add-income sheets: light and dark, empty and populated, RTL on a phone-sized view. |
| `hero_flip_test.dart` | The home flip cards: the balance card leans with a drag, turns over in the direction of the swipe, lies flat after a short drag and switches without a flip under reduced motion; with one currency it offers to add one. The goal card turns to the next and previous goal, and with one goal offers a new one. |

Subfolders:

- [sheets/](sheets/README.md)

Run them with:

```
flutter test test/screens/offline/home
```
