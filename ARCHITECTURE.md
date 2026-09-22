# Waffer architecture

Waffer is an offline-first personal and family finance app. The ledger
(income, expenses, savings goals, shopping list, recurring bills) lives on
the device. A FastAPI sync path can push and merge that data when the user
is signed in. Google Drive backup exists in the tree but is switched off
until OAuth verification finishes; do not delete that code.

The UI is Arabic, right-to-left, with a light and a dark theme. Color values
live only in `lib/core/theme/app_color.dart`.

## Folder map

```
lib/
  main.dart                 startup, theme, and which gate to show
  core/                     theme, prefs cache, sync, security, small utils
  data/
    models/                 plain types and catalogs (no I/O)
    stores/                 in-memory ledger backed by SharedPreferences
    services/               notifications, photos, online feed, Drive backup
  screens/                  one folder per feature; routes stay here
  widgets/                  shared controls used by more than one screen
```

`lib/screens` is organized by feature, not by layer. A screen may own its
sheets. Shared sheet pieces (glass body, amount field, save button) live in
`lib/widgets`.

## Where do I find X?

| I want to… | Look in |
| --- | --- |
| Add a new screen | `lib/screens/`. Wire it from `lib/main.dart` if it is a startup gate, or from `lib/screens/shell/app_shell.dart` if it is a tab. Settings screens are pushed from `lib/screens/offline/settings/settings_screen.dart`. |
| Change the bottom bar | `lib/screens/shell/app_shell.dart`. Five tabs, built lazily. Settings is not a tab. |
| Change colors or type | `lib/core/theme/app_color.dart` and `lib/core/theme/app_theme.dart`. `AppPalette` only picks the existing light or dark token. |
| Glass cards and buttons | `lib/widgets/containers/glass.dart` and `lib/widgets/button/glass_button.dart`. They are translucent fills, not backdrop blurs. |
| Bottom sheet chrome | `lib/widgets/containers/glass_sheet.dart`. |
| Money formatting and the active currency symbol | `lib/core/utils/money.dart`. |
| The currency list and the active currency | Catalog: `lib/data/models/currency.dart`. Saved selection: `lib/data/stores/currency_store.dart`. |
| Transactions, balance, savings goals | `lib/data/models/transaction.dart`, `lib/data/models/savings_goal.dart`, and `lib/data/stores/transaction_store.dart`. |
| Custom expense categories | `lib/data/models/expense_categories.dart` and `lib/data/stores/category_store.dart`. |
| Shopping list and recurring bills | `lib/data/stores/shopping_list_store.dart`, `lib/data/stores/recurring_expense_store.dart`. |
| Spending chart | `lib/screens/offline/report/reportscreen.dart` (`fl_chart` line chart). The home donut is `_DistributionChart` in `lib/screens/offline/home/dashboard.dart`. |
| Exchange rates, news, nearby places | Rates and news: `lib/data/services/online_feed_service.dart`, drawn by `lib/screens/online/online_screen.dart`. Nearby places: `lib/data/models/nearby_place_category.dart` (opens a maps search). |
| Notifications | `lib/data/services/notification_service.dart` and `lib/screens/offline/notifications/notifications_screen.dart`. |
| Sign-in and cloud sync | `lib/core/sync/` (`auth_session.dart`, `sync_service.dart`). Login UI: `lib/screens/offline/login/`. |
| App lock | `lib/core/security/app_lock.dart` and `lib/screens/offline/applock/applockscreen.dart`. |
| Profile photo | `lib/data/services/profile_photo.dart`. |
| Google sign-in and Drive backup | `lib/data/services/google_auth_service.dart`, `lib/data/services/drive_backup_client.dart`, `lib/data/services/backup_service.dart`, `lib/core/config/google_sign_in_config.dart`. Drive is off (`driveBackupEnabled`). Leave the re-enable markers in place. |
| On-device preferences | `lib/core/prefs/app_prefs.dart`. Call `AppPrefs.instance` instead of `SharedPreferences.getInstance()`. |

## Startup

`main` warms the preferences cache, then runs `WafarApp`. `AppFlowController`
shows one of: login, first-launch theme, biometric lock, or `AppShell`.

## Tabs

`AppShell` is a `PageView` with a custom bar under it:

1. Home
2. Report
3. Savings
4. Online
5. Notifications

Only the visible page is mounted (`scrollCacheExtent` is zero). The first
visit builds that tab; `AutomaticKeepAliveClientMixin` on each tab keeps it
after that, so scroll position is not lost. Swiping and tapping both move
the pager.

## Data flow

Stores are singletons (`TransactionStore.instance` and the others). They
load from preferences once, keep the list in memory, and notify listeners.
Screens use `AnimatedBuilder` / `Listenable` on those stores. They should
not read preferences again during `build`.

Sync reads the same stores, pushes dirty rows, and merges the server copy.
Tombstones in `lib/core/sync/sync_tombstones.dart` stop a deleted row from
coming back.

## More detail

- [lib/core/README.md](lib/core/README.md)
- [lib/data/README.md](lib/data/README.md)
- [lib/screens/README.md](lib/screens/README.md)
- [lib/widgets/README.md](lib/widgets/README.md)
