# Settings

The settings page and the pages it pushes. `SettingsScreen` is pushed from
the app shell with the theme notifier, the theme toggle, and the root
`AppFlowController` state (typed `dynamic`, may be null), which pages use to
refresh the app lock and to return to login after signing out.

| File | Main entry point | What it is |
| --- | --- | --- |
| `settings_screen.dart` | `SettingsScreen` | Hub: account card, income, currencies, obligations, dark mode, card motion and touch haptics switches, language, app lock, smart analysis, privacy, help, guest reset. |
| `account_screen.dart` | `AccountScreen` | Signed-in account: display name, email, change password, sign out, delete account. |
| `change_password_screen.dart` | `ChangePasswordScreen` | Current / new / confirm password form (`AuthSession.changePassword`). |
| `ai_permissions_screen.dart` | `AIPermissionsScreen` | Smart analysis shortcut and the `SmartSettings` switches. |
| `privacy_security_screen.dart` | `PrivacySecurityScreen` | Controls only: the app-lock switch and the local data reset. No explanatory copy (by request). |
| `about_screen.dart` | `AboutScreen` | "عن وفّر". Empty for now (by request). |
| `help_screen.dart` | `HelpScreen` | Help center: a card that restarts the interactive tutorial, a search box (`searchHelp`, Arabic letter variants folded by `foldArabic`), and the questions by topic, each opening in place. |
| `help_content.dart` | `helpSections` | The help copy: fourteen topics from getting started to troubleshooting. It does not repeat the privacy explanations removed from the Privacy page (what syncs, encryption on the server). Describes only what the app does; update it with the feature. |
| `sheets/` | | Currencies and income sheets; see `sheets/README.md`. |

How it connects:

- Signed-in users open `AccountScreen`; guests are sent to `LoginScreen`
  and synced afterwards. Settings reloads its summary whenever a pushed page
  returns.
- Income is edited with `showMonthlyIncomeSheet` and saved through
  `TransactionStore.setPreferredIncomeAmount` / `clearPreferredIncomeAmount`.
- App lock: settings uses `local_auth` directly and the prefs key
  `app_lock`; the privacy page's switch goes through `AppLock.setEnabled`.
- Guest reset (settings) clears prefs, the session and every store cache;
  the privacy page's reset calls `LocalDataReset.resetCurrentDevice`.

Conventions: settings rows are `AppListTile`s inside `AppListGroup`s
(`widgets/containers/app_list_tile.dart`), drawn on the dashboard's card
surface. Settings pages have no entrance animation. The weekly income tile is
hidden by `_weeklyIncomeChoiceEnabled`.
