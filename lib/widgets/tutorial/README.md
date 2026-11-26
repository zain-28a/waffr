# lib/widgets/tutorial

| File | Main entry point | What it is |
| --- | --- | --- |
| `tutorial_layer.dart` | `TutorialLayer`, `TutorialSheetHint` | The overlay above the navigator (`MaterialApp.builder` in `main.dart`): a dimmed screen with a clear window over the current target (touches inside reach the real control, outside are held back), the step card, and the "leave the tutorial?" question. `TutorialSheetHint` shows a step's hint inside the sheet being filled in. |

The dim is a translucent even-odd path, not a blur, so following a moving
target every frame stays cheap.
