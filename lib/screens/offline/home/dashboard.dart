// Offline home tab (library root): the balance hero, quick actions, one
// line from the smart analysis, the spending strip, recent expenses,
// obligations and the savings goals carousel. Each section opens the
// screen that holds its full details.
//
// The sections live in dashboard_* part files of this library.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/insight_engine.dart';
import 'package:waffr/core/insights/smart/smart_facts_loader.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/insights/smart/wallet_mood.dart';
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
import 'package:waffr/screens/offline/report/reportscreen.dart';
import 'package:waffr/screens/offline/savings/sheets/create_goal_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/manual_save_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/shopping_list_sheet.dart';
import 'package:waffr/screens/offline/smart/smart_analysis_screen.dart';
import 'package:waffr/screens/shell/app_shell_scope.dart';
import 'package:waffr/widgets/brand/waffr_mouth.dart';
import 'package:waffr/widgets/containers/glass.dart';
import 'package:waffr/widgets/glass/tilt.dart';
import 'package:waffr/widgets/motion/active_listenable_builder.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/widgets/motion/pressable.dart';

part 'dashboard_actions.dart';
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

  void _openIncomeLog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TransactionHistoryScreen.incomes(),
      ),
    );
  }

  void _openExpenseLog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TransactionHistoryScreen.expenses(),
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
              _InsightStrip(
                text: _insight ?? 'سجّل دخلك ومصروفك ليبدأ التحليل الذكي',
                onTap: () => openSmartAnalysis(context, InsightScope.reports),
              ),
              const SizedBox(height: kCardGap),
              // expensesByCategory is rolled up in memory from the store.
              _SpendingStrip(
                totals: _store.expensesByCategory(),
                totalExpense: _store.totalExpense,
                onTap: () =>
                    AppShellScope.selectTabOf(context, AppShellTabs.report),
              ),
              const SizedBox(height: kCardGap),
              _RecentCard(expenses: _store.expenses, onAll: _openExpenseLog),
              if (hasObligations) ...[
                const SizedBox(height: kCardGap),
                _ObligationsCard(
                  obligations: obligations,
                  onTap: () => showObligationsSheet(context),
                ),
              ],
              const SizedBox(height: kCardGap),
              _GoalsCarousel(
                goals: _store.activeGoals,
                store: _store,
                onOpen: () =>
                    AppShellScope.selectTabOf(context, AppShellTabs.savings),
                onCreate: () => showCreateGoalSheet(context),
              ),
            ]),
          ),
        );
      },
    );
  }
}
