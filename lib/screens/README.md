# lib/screens

Feature screens. Navigation is not a separate router package: `main.dart`
picks the gate, `AppShell` holds the five tabs, and everything else is a
`Navigator.push`.

| Path | Screen |
| --- | --- |
| `shell/app_shell.dart` | Header, lazy `PageView`, bottom bar. |
| `offline/home/` | Balance, add income/expense, category donut, recent expenses, goal pager. |
| `offline/report/` | Spending line chart (`fl_chart`), category split, transaction history. |
| `offline/savings/` | Goals and the sheets for saving, withdrawing, shopping, and recurring bills. |
| `online/` | Exchange rates, nearby places, news. |
| `offline/notifications/` | Notification list. |
| `offline/settings/` | Settings stack: account, privacy, currencies, help. |
| `offline/login/` | Login, register, and the account-creation steps. |
| `offline/applock/` | Biometric lock. |
| `offline/user_info/` | Profile fields after registration. |
| `offline/theme_select_screen.dart` | First-launch light/dark choice. |

A new tab means a new child in `_tabAt` inside `app_shell.dart` and a new
icon in `_BottomNavBar`. A new pushed screen does not belong in the pager.
