# lib/core

Shared code that is not a screen and not a ledger type.

| Folder | What it holds |
| --- | --- |
| `theme/` | `AppColors` tokens, `AppTheme` (fonts and `ThemeData`), `AppPalette` (the light or dark token for the current brightness). |
| `prefs/` | `AppPrefs`, the one cached `SharedPreferences` handle. Warm it from `main`. |
| `utils/` | `money.dart` (formatting and the active symbol), `app_feedback.dart` (snack bars and dialogs), `date_input.dart` (typed DD/MM/YYYY dates). |
| `l10n/` | `WaffrMaterialLocalizations`: Arabic Material strings with 0-9 digits in pickers. |
| `security/` | `AppLock`, the biometric flag. |
| `sync/` | FastAPI session, push/pull, dirty flags, tombstones, profile sync. |

Color values are not duplicated here on purpose. If a widget needs "the
current accent", use `AppPalette.of(context)`.
