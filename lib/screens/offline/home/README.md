# Home tab

The home tab of the app shell (`HomeScreen`, tab 0). One Dart library split
into part files: `dashboard.dart` holds the imports and the `part`
directives, and the other `dashboard_*.dart` files start with
`part of 'dashboard.dart'`, so their private card widgets are visible to the
screen. Import only `dashboard.dart`.

| File | What it holds |
| --- | --- |
| `dashboard.dart` | `HomeScreen`: the scrollable stack of sections, what each one opens, and the coalesced read of the smart insight line. |
| `dashboard_hero.dart` | `_BalanceHero`: the balance on a dimensional card that leans with touch and the phone (`TiltBuilder`), a ring for what is left of the period, currency swipe and dots, income-log / shopping-list chips, the wallet's smile as a watermark. `_RingPainter`. |
| `dashboard_actions.dart` | `_QuickActions` (expense, income, save, obligations) and `_InsightStrip` (one line from the smart analysis). |
| `dashboard_spending.dart` | `_SpendingStrip`: one stacked bar of category shares and the three largest. |
| `dashboard_recent.dart` | `_RecentCard` (last four expenses) and `_ObligationsCard` (up to two, hidden when there are none). |
| `dashboard_goals.dart` | `_GoalsCarousel`: one card per active goal with a progress ring, ending with a "new goal" card. |
| `dashboard_sections.dart` | Shared chrome: `_SectionCard`, `_HeaderLink`, `_EmptyState`, the `_text` style helper. |
| `sheets/` | Add-expense and add-income sheets; see `sheets/README.md`. |

How it connects:

- Data comes from `TransactionStore` (balance, cycle spend, category totals,
  expenses, active goals), `RecurringExpenseStore` (obligations for the
  active currency), `CategoryStore` and `CurrencyStore`. The four are merged
  into one `ActiveListenableBuilder`, so a hidden tab does not rebuild.
- Taps: the quick actions open `showAddExpenseSheet` / `showAddIncomeSheet`
  / `showManualSaveSheet` / `showObligationsSheet`; the hero's chips open the
  income `TransactionHistoryScreen` and the shopping list sheet; the insight
  line opens the smart analysis; the spending strip switches to the report
  tab and a goal card to the savings tab (`AppShellScope.selectTabOf`); the
  recent card opens the expense history.
- Obligation rows reuse `obligationTitle` / `obligationStatus` /
  `obligationNeedsAttention` from `obligations/obligations_sheet.dart`.

Conventions: the screen is kept alive across tab switches
(`AutomaticKeepAliveClientMixin`); spacing uses `kCardGap` and the bottom
padding `kFloatingNavClearance` from the shell. The scroll view does not clip,
so content passes beneath the shell's glass header. The goals row swallows
its horizontal scroll notifications so the shell's tab pager does not move.
The hero listens to the accelerometer only while the tab is visible, motion
is allowed and `TiltSettings` is on.

Tests: `test/screens/offline/home/dashboard_test.dart`.
