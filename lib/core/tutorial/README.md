# lib/core/tutorial

The first-run interactive tutorial's logic. No widgets of its own besides
the target keys; the overlay is `widgets/tutorial/tutorial_layer.dart`.

| File | Contents |
| --- | --- |
| `tutorial_controller.dart` | `tutorialSteps` (16 steps in 8 topics), `TutorialTarget` + `TutorialTargets.of()` (the keys put on the real controls), `TutorialDemo`, and `TutorialController.instance`: `maybeStart`, `restart`, `next`, `emit`, `finish`, `requestSkip`, `isDemo`. |

How it connects:

- `AppShell` registers `selectTab`, reports `tab:N`, and calls
  `maybeStart()` once the home screen has settled (and after a streak or
  goal celebration). Every user sees it once; finishing or skipping saves
  `interactive_tutorial_v1 = done`. An unfinished tutorial resumes at the
  start of its topic. Help restarts it.
- Screens report what happened with `emit`: `sheet-open:*` /
  `sheet-closed:*` from the show-sheet functions, `smart-opened` /
  `smart-closed` from `openSmartAnalysis`, `settings-opened`,
  `help-opened`, and `demo-saved:*` from the sheets.
- Demo mode: while `isDemo(...)` is true the income, expense and goal
  sheets skip their store calls entirely, so the tutorial never adds a
  transaction or a goal.
- A step whose control is not on screen for 1.5 s (for example no
  "create goal" button because goals exist) turns into a "next" step and
  skips the demo that would follow.
