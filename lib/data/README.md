# lib/data

Ledger types, the on-device stores, and services that talk to disk or the network.

## models/

Plain data and fixed catalogs. No `SharedPreferences` and no widgets, except
`nearby_place_category.dart`, which also launches a maps search.

| File | Contents |
| --- | --- |
| `transaction.dart` | One income, expense, or savings movement. |
| `savings_goal.dart` | A savings target and its duration. |
| `currency.dart` | The currency catalog and `defaultCurrencyCode`. |
| `expense_categories.dart` | Built-in category names, icons and chart colors. |
| `expense_preset.dart` | A saved expense reused from the star on the expense sheet. |
| `country.dart` | Countries with Arabic names and calling codes. |
| `recurring_expense.dart` | A bill that posts on a schedule. |
| `calendar_period.dart` | Week/month windows used by savings and notifications. |
| `exchange_rate.dart` | One rate row for the online tab. |
| `news_article.dart` | One news item. |
| `app_notification.dart` | A stored notification and its thresholds. |
| `registration_profile.dart` | Fields collected at sign-up. |
| `nearby_place_category.dart` | Chips that open a maps search. |

## stores/

`ChangeNotifier` singletons. Each one loads once (`ensureLoaded`) and then
serves memory.

| File | Contents |
| --- | --- |
| `transaction_store.dart` | Transactions, balance, income settings, savings goals. |
| `currency_store.dart` | Enabled currencies and the active one. Re-exports `models/currency.dart`. |
| `category_store.dart` | User-added categories, removed built-ins (synced in settings), and a local archive of removed categories. |
| `expense_preset_store.dart` | Saved expenses (synced as `expense_presets`). |
| `shopping_list_store.dart` | Shopping items. |
| `recurring_expense_store.dart` | Recurring bills and the "due" pass. |

## services/

| File | Contents |
| --- | --- |
| `notification_service.dart` | Builds and stores in-app notifications. |
| `online_feed_service.dart` | Static exchange rates and news from the API. |
| `profile_photo.dart` | The local profile image. |
| `local_data_reset.dart` | Wipes restorable local data. |
| `backup_service.dart` | Local account data: guest choice, display name, wiping data on account delete or switch. |
