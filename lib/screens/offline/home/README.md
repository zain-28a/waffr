# Home tab

The home tab of the app shell (`HomeScreen`, tab 0). One Dart library split
into part files: `dashboard.dart` holds the imports and the `part`
directives, and the other `dashboard_*.dart` files start with
`part of 'dashboard.dart'`, so their private card widgets are visible to the
screen. Import only `dashboard.dart`.

| File | What it holds |
| --- | --- |
| `dashboard.dart` | `HomeScreen`: the scrollable stack of sections, what each one opens, the goal on show, and the coalesced read of the smart insight line. |
| `dashboard_hero.dart` | `_BalanceHero`: the balance on a dimensional card that leans with touch and the phone (`TiltBuilder`), a thick bar for what is left of the period, currency dots, income-log / shopping-list chips. A swipe turns it over to the next or previous currency; with one currency a half turn opens `showAddCurrencySheet`. |
| `dashboard_flip.dart` | `_SwipeFlip`: a card that leans with a vertical drag and turns over in the direction of the swipe (`onTurn` asks for the next face); with nothing to turn to it makes a half turn and calls `onEmpty`. A new `face` from elsewhere turns it over too. Used by the hero and the goal card. |
| `dashboard_actions.dart` | `_QuickActions` (expense, income, save, obligations) and `_InsightBar` (the way into the smart analysis: a card with a lightbulb and the analysis headline, which turns every few seconds through several wordings while the tab is visible; `HomeScreen` reads the wordings with eight seeds). |
| `dashboard_spending.dart` | `_SpendingCard`: a donut of category shares (`_Donut`, the largest slice a little thicker, the total in the middle; it sweeps in once and glides on changes) with the largest five categories listed beside it, across the full width. |
| `dashboard_recent.dart` | `_RecentCard` (last four expenses, compact) and `_ObligationsCard` (up to two, hidden when there are none). |
| `dashboard_goals.dart` | `_GoalTile`: one active goal at a time in a `LiquidVessel` that fills as it is saved for, with page dots; a swipe turns to the next goal, and with no other goal opens a new one. `_NewGoalCard` while there is none. |
| `dashboard_sections.dart` | Shared chrome: `_SectionCard` (with a `compact` mode), `_CardPair` (two cards in a row, two thirds and one third, the same height), `_HeaderLink`, `_EmptyState`, the `_text` style helper. |
| `sheets/` | Add-expense and add-income sheets; see `sheets/README.md`. |

How it connects:

- Data comes from `TransactionStore` (balance, cycle spend, category totals,
  expenses, active goals), `RecurringExpenseStore` (obligations for the
  active currency), `CategoryStore` and `CurrencyStore`. The four are merged
  into one `ActiveListenableBuilder`, so a hidden tab does not rebuild.
- Taps: the quick actions open `showAddExpenseSheet` / `showAddIncomeSheet`
  / `showManualSaveSheet` / `showObligationsSheet`; the hero's chips open the
  income `TransactionHistoryScreen` (which grows out of the chip) and the
  shopping list sheet; the insight bar opens the smart analysis (growing
  out of the bar); the spending card switches to the report tab and the
  goal card to the savings tab (`AppShellScope.selectTabOf`); the recent
  card opens the expense history, growing out of the card.
- Layout: hero, quick actions, the insight bar, the spending card, a
  `_CardPair` row (recent expenses with the goal card), then the
  obligations card.
- Obligation rows reuse `obligationTitle` / `obligationStatus` /
  `obligationNeedsAttention` from `obligations/obligations_sheet.dart`.

Conventions: the screen is kept alive across tab switches
(`AutomaticKeepAliveClientMixin`); spacing uses `kCardGap` and the bottom
padding `kFloatingNavClearance` from the shell. The scroll view does not clip,
so content passes beneath the shell's glass header. The hero and the goal
card claim vertical drags, so a swipe on them turns them over instead of
scrolling the page.
The hero listens to the accelerometer only while the tab is visible, motion
is allowed and `TiltSettings` is on.

Tests: `test/screens/offline/home/dashboard_test.dart` and
`hero_flip_test.dart`.
