# lib/core

Shared code that is not a screen and not a ledger type.

| Folder | What it holds |
| --- | --- |
| `theme/` | `AppColors` tokens, `AppTheme` (fonts and `ThemeData`), `AppPalette` (the light or dark token for the current brightness). |
| `prefs/` | `AppPrefs`, the one cached `SharedPreferences` handle. Warm it from `main`. |
| `utils/` | `money.dart` (formatting and the active symbol) and `app_feedback.dart` (snack bars). |
| `security/` | `AppLock`, the biometric flag. |
| `sync/` | FastAPI session, push/pull, dirty flags, tombstones, profile sync. |
| `config/` | Google sign-in client ids. Leave this file alone while OAuth is pending. |

Color values are not duplicated here on purpose. If a widget needs "the
current accent", use `AppPalette.of(context)`.
