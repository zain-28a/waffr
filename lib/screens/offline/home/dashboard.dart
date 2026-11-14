// Offline home tab (library root): the balance hero, quick actions, the
// way into the smart analysis, the spending donut, the recent expenses
// beside one savings goal, and the obligations. Each section opens the screen that
// holds its full details.
//
// The sections live in dashboard_* part files of this library.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show listEquals, mapEquals;

import 'package:flutter/material.dart';
import 'package:waffr/widgets/motion/origin_route.dart';
import 'package:waffr/core/insights/smart/insight_engine.dart';
import 'package:waffr/core/insights/smart/smart_facts_loader.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/calendar_days.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/savings_goal.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/screens/offline/home/sheets/add_expense_sheet.dart';
import 'package:waffr/screens/offline/home/sheets/add_income_sheet.dart';
import 'package:waffr/screens/offline/obligations/obligations_sheet.dart';
import 'package:waffr/screens/offline/report/edit_transaction_sheet.dart';
import 'package:waffr/screens/offline/report/reportscreen.dart';
import 'package:waffr/screens/offline/savings/sheets/create_goal_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/manual_save_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/shopping_list_sheet.dart';
import 'package:waffr/screens/offline/settings/sheets/currencies_sheet.dart';
import 'package:waffr/screens/offline/smart/smart_analysis_screen.dart';
import 'package:waffr/screens/shell/app_shell_scope.dart';
import 'package:waffr/widgets/containers/glass.dart';
import 'package:waffr/widgets/glass/liquid_glass.dart';
import 'package:waffr/widgets/glass/tilt.dart';
import 'package:waffr/widgets/motion/active_listenable_builder.dart';
import 'package:waffr/widgets/motion/liquid_vessel.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/widgets/motion/pressable.dart';
import 'package:waffr/widgets/smart/smart_glow.dart';

part 'dashboard_actions.dart';
part 'dashboard_flip.dart';
part 'dashboard_goals.dart';
part 'dashboard_hero.dart';
part 'dashboard_recent.dart';
part 'dashboard_sections.dart';
part 'dashboard_spending.dart';

/// The home tab of the app shell: a scrollable stack of dashboard cards.
class HomeScreen extends StatefulWidget {
  /// Creates a [HomeScreen].
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// State of [HomeScreen].
///
/// Kept alive in the shell PageView so scroll position survives tab
/// switches. Rebuilds whenever the transaction, category, currency or
/// recurring-expense store notifies.
class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final TransactionStore _store = TransactionStore.instance;

  /// All stores the dashboard reads, merged so one builder covers them.
  late final Listenable _listenables = Listenable.merge([
    _store,
    CategoryStore.instance,
    CurrencyStore.instance,
    RecurringExpenseStore.instance,
  ]);

  /// One line from the smart analysis; null until the first read, and
  /// with nothing logged yet.
  String? _insight;

  /// Data changed since the insight was last read.
  bool _insightDirty = true;
  bool _insightLoading = false;

  /// Folds a burst of store notifications into one read.
  Timer? _insightTimer;

  /// The savings goal on the goal card; wraps around the active goals.
  int _goalIndex = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    CategoryStore.instance.ensureLoaded();
    CurrencyStore.instance.ensureLoaded();
    RecurringExpenseStore.instance.ensureLoaded();
    _listenables.addListener(_queueInsight);
    _queueInsight();
  }

  @override
  void dispose() {
    _listenables.removeListener(_queueInsight);
    _insightTimer?.cancel();
    super.dispose();
  }

  void _queueInsight() {
    _insightDirty = true;
    if (_insightLoading || _insightTimer?.isActive == true) return;
    _insightTimer = Timer(const Duration(milliseconds: 400), _readInsight);
  }

  /// The headline of the reports analysis. The wording is seeded by the
  /// day, so it stays the same until tomorrow or until the data changes.
  Future<void> _readInsight() async {
    if (!mounted || _insightLoading || !_insightDirty) return;
    _insightDirty = false;
    _insightLoading = true;
    try {
      final facts = await SmartFactsLoader.load();
      if (!mounted || _insightDirty) return;
      final empty = facts.expenses.isEmpty && facts.incomes.isEmpty;
      final now = facts.now;
      final line = empty
          ? null
          : InsightEngine(
              facts,
              seed: now.year * 400 + now.month * 32 + now.day,
            ).analyze(InsightScope.reports).headline;
      if (line != _insight) setState(() => _insight = line);
    } finally {
      _insightLoading = false;
      if (mounted && _insightDirty) _queueInsight();
    }
  }

  /// The card the expense history grows out of.
  final GlobalKey _recentCard = GlobalKey();

  /// Opens the income history out of the chip that was tapped.
  void _openIncomeLog(BuildContext chip) {
    Navigator.of(context).push(
      originPageRoute<void>(
        chip,
        (_) => const TransactionHistoryScreen.incomes(),
        radius: 14,
      ),
    );
  }

  void _openExpenseLog() {
    Navigator.of(context).push(
      originPageRoute<void>(
        _recentCard.currentContext ?? context,
        (_) => const TransactionHistoryScreen.expenses(),
        radius: 28,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ActiveListenableBuilder(
      listenable: _listenables,
      builder: (context, _) {
        final obligations = RecurringExpenseStore.instance.itemsFor(
          CurrencyStore.instance.activeCode,
        );
        final now = deviceNow();
        final attention = obligations
            .where((item) => obligationNeedsAttention(item, now: now))
            .length;
        final hasObligations = obligations.any((item) => item.enabled);
        final goals = _store.activeGoals;

        return SingleChildScrollView(
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, kFloatingNavClearance),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: staggered([
              // The balance on its dimensional glass card.
              _BalanceHero(
                balance: _store.balance,
                spent: _store.cycleSpent,
                maxBalance: _store.maxBalance,
                ratio: _store.remainingRatio,
                onShoppingList: () => showShoppingListSheet(context),
                onIncomeLog: _openIncomeLog,
              ),
              const SizedBox(height: 20),
              _QuickActions(
                attention: attention,
                onExpense: () => showAddExpenseSheet(context),
                onIncome: () => showAddIncomeSheet(context),
                onSave: () => showManualSaveSheet(context),
                onObligations: () => showObligationsSheet(context),
              ),
              const SizedBox(height: 20),
              // The way into the smart analysis, then where the money went.
              _InsightBar(insight: _insight),
              const SizedBox(height: 14),
              _SpendingCard(
                totals: _store.expensesByCategory(),
                totalExpense: _store.totalExpense,
                onTap: () =>
                    AppShellScope.selectTabOf(context, AppShellTabs.report),
              ),
              const SizedBox(height: kCardGap),
              // The latest expenses, with one savings goal beside them.
              _CardPair(
                wide: _RecentCard(
                  key: _recentCard,
                  expenses: _store.expenses,
                  onAll: _openExpenseLog,
                ),
                narrow: _GoalTile(
                  goals: goals,
                  index: _goalIndex,
                  store: _store,
                  onIndex: (index) => setState(() => _goalIndex = index),
                  onOpen: () =>
                      AppShellScope.selectTabOf(context, AppShellTabs.savings),
                  onCreate: () => showCreateGoalSheet(context),
                ),
              ),
              if (hasObligations) ...[
                const SizedBox(height: kCardGap),
                _ObligationsCard(
                  obligations: obligations,
                  onTap: () => showObligationsSheet(context),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}
