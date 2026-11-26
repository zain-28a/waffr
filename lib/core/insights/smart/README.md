# lib/core/insights/smart

The "smart analysis": rule-based insights written in Arabic, entirely on the
device (no network, no model). Data flows one way:
stores -> `SmartFactsLoader` -> `SmartFacts` -> `InsightEngine` -> `SmartReport`.

| File | Contents |
| --- | --- |
| `smart_facts.dart` | `SmartFacts` (plus `GoalFact`, `ObligationFact`): the numbers for one run, with lazily cached derived figures. Pure data, so rules are testable without stores. |
| `smart_facts_loader.dart` | `SmartFactsLoader.load()`: awaits the stores and snapshots the active currency into `SmartFacts`. |
| `wallet_mood.dart` | `SmileForm` (seven faces by health score, the logo's own smile being the happiest, with a 3-point hysteresis so a score on an edge cannot flip the face) and `WalletMood.instance` (shared, coalesced recompute while a widget `retain`s it). Drives the header logo and the profile backdrop. |
| `smart_insight.dart` | Output types: `InsightScope` (reports / savings / profile), `InsightTone`, `InsightKind` (fact / estimate / suggestion, shown as a chip), `HealthBand`, `InsightAction`, `SmartInsight` (with an optional `topic`), `SmartReport`. |
| `insight_engine.dart` | `InsightEngine(facts, seed:).analyze(scope)`: runs one rule group, keeps one card per topic, ranks and caps the cards, adds a closing tip when one fits. Also `healthScore()` and `suggestedMonthlySaving()`. |
| `report_insights.dart` | `ReportInsights.all()`: spending rules (trends, top category, spikes, projection, runway, weekday, small/large/night spending, bills), plus everything in `report_patterns` and the report part of `cashflow_insights`. Also `largestCategory()`, `categoryOf()`. |
| `report_patterns.dart` | `ReportPatterns.all()`: month-to-month and three-month trends, new and steady categories, concentration, purchases that recur monthly, weekend and payday spending, average purchase size and frequency, month-end estimates against past months, the rest of the month's bills, small habits costed over a year, no-spend runs. `normalizedNote()`. |
| `cashflow_insights.dart` | `CashflowInsights`: income as the spending limit. `forReports()` (share of income spent against the month, top category against income, a weekly share, last month's income against its spending, missing income, a daily allowance) and `forProfile()` (90 days of spending against income, variable or rising income, fixed costs). |
| `savings_insights.dart` | `SavingsInsights.all()`: one card per goal (near, late, due soon, new, behind, ahead, on track with its estimated month), stalled goals, saving rate, withdrawals, emergency fund in three bands; `suggestedMonthlySaving()`. Runs `savings_habits` too. |
| `savings_habits.dart` | `SavingsHabits.all()`: months in a row with savings, a weak month, the first saving, idle balance late in the month, the year ahead, a large withdrawal, never saved, goals heavier than the saving pace. |
| `profile_insights.dart` | `ProfileInsights.all()` and the weighted 0-100 `healthScore()`; `healthLabel(score)`. |
| `insight_summary.dart` | `InsightSummary`: headline, summary line, and a closing tip chosen only from tips the data fits (none when nothing fits). |
| `insight_phrasing.dart` | `InsightPhrasing`: shared random wording and money/percent/day formatting. |
| `arabic_text.dart` | Arabic grammar helpers: `ArabicCount` / `Ar` (number-noun agreement), `Ar.category`, `Ar.li`, `Ar.quote`. |
| `reminder_digest.dart` | `ReminderDigest(facts).candidates(fireAt)` / `weekly()` / `streakText()`: short factual texts for device notifications. |
| `category_suggester.dart` | `CategorySuggester(history).suggest(note, allowed)`: picks a category from the expense note, learning from the user's history first, then a dictionary. |

Conventions:

- Every statement comes from recorded data. Rules wait for enough of it:
  month comparisons need the month tracked from its start
  (`SmartFacts.coversMonth`), span comparisons need three expenses in each
  span, and the first two weeks show an "early data" card instead of
  verdicts. Projections are marked `InsightKind.estimate`.
- Cards that tell the same story share a `topic`; the engine keeps the
  highest-priority card of each.
- `test/core/insights/smart/insight_quality_test.dart` runs the engine over
  hundreds of random ledgers and fails on unfinished text (null, NaN,
  negative amounts, doubled spaces).

- `insight_engine.dart` was split: rules live in the `*_insights.dart` files,
  wording in `insight_phrasing.dart`, framing text in `insight_summary.dart`.
- One `InsightPhrasing` and one `Random` are shared by all rule groups in a
  fixed call order, so a fixed `seed` gives the exact same report (tests).
- Cards are cut by priority alone; only ordering inside the cut is jittered.
- Money is formatted through `core/utils/money.dart`; percents are wrapped
  in LTR isolates so "20%" does not flip inside Arabic text.

Users: `SmartAnalysisScreen` and `ProfileScreen` (engine + loader),
`AppShell` and `SystemNotifications` (reminder digest), the add-expense sheet
(category suggester), `NotificationService`, `RecurringExpenseStore` and
`HomeWidgetSync` (`arabic_text.dart`).
