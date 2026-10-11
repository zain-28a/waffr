import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/widgets/motion/active_listenable_builder.dart';
import 'package:waffr/widgets/containers/app_empty_state.dart';
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/savings_goal.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/screens/offline/home/sheets/add_expense_sheet.dart';
import 'package:waffr/screens/offline/home/sheets/add_income_sheet.dart';
import 'package:waffr/screens/offline/obligations/obligations_sheet.dart';
import 'package:waffr/screens/offline/report/reportscreen.dart';
import 'package:waffr/screens/offline/savings/sheets/shopping_list_sheet.dart';
import 'package:waffr/screens/shell/app_shell_scope.dart';
import 'package:waffr/widgets/button/glass_button.dart';
import 'package:waffr/widgets/containers/glass.dart';

// Offline home tab: balance, add actions, spending distribution, recent
// expenses / obligations, and active savings goals. Each card opens the
// screen that holds its full details.

const double kBalanceCardActionTop = 14;
const double kBalanceCardActionEnd = 14;
const double kBalanceCardActionGap = 8;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// Kept alive in the shell PageView so scroll position survives tab switches.
class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final TransactionStore _store = TransactionStore.instance;
  late final Listenable _listenables = Listenable.merge([
    _store,
    CategoryStore.instance,
    CurrencyStore.instance,
    RecurringExpenseStore.instance,
  ]);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    CategoryStore.instance.ensureLoaded();
    CurrencyStore.instance.ensureLoaded();
    RecurringExpenseStore.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ActiveListenableBuilder(
      listenable: _listenables,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, kFloatingNavClearance),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: staggered([
              _BalanceCard(
                balance: _store.balance,
                spent: _store.cycleSpent,
                maxBalance: _store.maxBalance,
                ratio: _store.remainingRatio,
                onShoppingList: () => showShoppingListSheet(context),
                onIncomeLog: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TransactionHistoryScreen.incomes(),
                    ),
                  );
                },
              ),
              const SizedBox(height: kCardGap),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'إضافة دخل',
                      icon: Icons.add_circle_outline_rounded,
                      onTap: () => showAddIncomeSheet(context),
                    ),
                  ),
                  const SizedBox(width: kCardGap),
                  Expanded(
                    child: _ActionButton(
                      label: 'إضافة مصروف',
                      icon: Icons.remove_circle_outline_rounded,
                      onTap: () => showAddExpenseSheet(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: kCardGap),
              // expensesByCategory is rolled up in memory from the store.
              _DistributionCard(
                totals: _store.expensesByCategory(),
                totalExpense: _store.totalExpense,
                onTap: () => AppShellScope.selectTabOf(
                  context,
                  AppShellTabs.report,
                ),
              ),
              const SizedBox(height: kCardGap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _ExpensesAndObligationsCard(
                        expenses: _store.expenses,
                        obligations: RecurringExpenseStore.instance.itemsFor(
                          CurrencyStore.instance.activeCode,
                        ),
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: kCardGap),
                    Expanded(
                      flex: 4,
                      child: _SavingGoalCard(
                        compact: true,
                        goals: _store.activeGoals,
                        store: _store,
                        onTap: () => AppShellScope.selectTabOf(
                          context,
                          AppShellTabs.savings,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// Current balance, remaining-ratio bar, and spend vs max. Vertical swipe
// cycles currency when more than one is enabled. Corner actions open income
// history and the shopping list.
class _BalanceCard extends StatelessWidget {
  final double balance;
  final double spent;
  final double maxBalance;
  final double ratio;
  final VoidCallback onShoppingList;
  final VoidCallback onIncomeLog;

  const _BalanceCard({
    required this.balance,
    required this.spent,
    required this.maxBalance,
    required this.ratio,
    required this.onShoppingList,
    required this.onIncomeLog,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final codes = CurrencyStore.instance.enabledCodes;
    final activeIndex = codes.indexOf(CurrencyStore.instance.activeCode);
    final showDots = codes.length > 1;

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          GestureDetector(
            onVerticalDragUpdate:
                CurrencyStore.instance.enabledCodes.length > 1 ? (_) {} : null,
            onVerticalDragEnd: CurrencyStore.instance.enabledCodes.length > 1
                ? (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -180) {
                      CurrencyStore.instance.selectNext();
                    } else if (velocity > 180) {
                      CurrencyStore.instance.selectPrevious();
                    }
                  }
                : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.medium),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Padding(
                key: ValueKey(CurrencyStore.instance.activeCode),
                padding: EdgeInsetsDirectional.fromSTEB(
                  showDots ? 34 : 22,
                  20,
                  22,
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'الرصيد الحالي',
                          style: TextStyle(
                            fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                            fontSize: 13.5,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: RollingMoney(
                              value: balance,
                              style: TextStyle(
                                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currencyLabel,
                          style: TextStyle(
                            fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                            fontSize: 15,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 0),
                    AnimatedRatio(
                      value: ratio,
                      builder: (context, shown) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${(shown * 100).round()}%',
                              style: TextStyle(
                                fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          _HorizontalProgress(
                            ratio: shown,
                            trackColor: accent.withValues(alpha: 0.12),
                            fillColor: accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'مصروف ${formatMoney(spent)} $currencyLabel '
                      'من ${formatMoney(maxBalance)} $currencyLabel',
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                        fontSize: 12.5,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showDots)
            PositionedDirectional(
              start: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CurrencyDots(
                  count: codes.length,
                  activeIndex: activeIndex < 0 ? 0 : activeIndex,
                  activeColor: accent,
                  inactiveColor: textSecondary.withValues(alpha: 0.35),
                ),
              ),
            ),
          PositionedDirectional(
            top: kBalanceCardActionTop,
            end: kBalanceCardActionEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassIconButton(
                  icon: Icons.payments_outlined,
                  label: 'سجل الدخل',
                  onPressed: onIncomeLog,
                ),
                const SizedBox(width: kBalanceCardActionGap),
                GlassIconButton(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'قائمة المشتريات',
                  onPressed: onShoppingList,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Vertical page dots for the balance-card currency swipe. The active
// mark grows and takes the accent color; PositionedDirectional places
// the column on the start edge in both LTR and RTL.
class _CurrencyDots extends StatelessWidget {
  final int count;
  final int activeIndex;
  final Color activeColor;
  final Color inactiveColor;

  const _CurrencyDots({
    required this.count,
    required this.activeIndex,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < count; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.medium),
              curve: Curves.easeOutCubic,
              width: 6,
              height: index == activeIndex ? 18 : 6,
              decoration: BoxDecoration(
                color: index == activeIndex ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
      ],
    );
  }
}

class _HorizontalProgress extends StatelessWidget {
  final double ratio;
  final Color trackColor;
  final Color fillColor;

  const _HorizontalProgress({
    required this.ratio,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 30, color: trackColor),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: ratio.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(fillColor, Colors.white, 0.18)!,
                      fillColor,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    return GlassButton(
      onTap: onTap,
      colorType: GlassColorType.surface,
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Spending share by category: legend + donut.
class _DistributionCard extends StatelessWidget {
  final List<({String category, double amount})> totals;
  final double totalExpense;
  final VoidCallback onTap;

  const _DistributionCard({
    required this.totals,
    required this.totalExpense,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'توزيع المصروفات',
      onTap: onTap,
      caption: 'النسبة من إجمالي الصرف ',
      child: totals.isEmpty || totalExpense <= 0
          ? const _EmptyState(
              icon: Icons.pie_chart_outline_rounded,
              message: 'ستظهر النسب بعد تسجيل أول مصروف',
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _DistributionLegend(
                    totals: totals,
                    totalExpense: totalExpense,
                  ),
                ),
                const SizedBox(width: 16),
                RepaintBoundary(
                  child: _DistributionChart(
                    totals: totals,
                    totalExpense: totalExpense,
                  ),
                ),
              ],
            ),
    );
  }
}

// Donut of spending shares. fl_chart paints this with its pie renderer, not
// an app-owned CustomPainter. PieChartData uses value equality, so a parent
// rebuild with the same slices does not mark the chart dirty. RepaintBoundary
// keeps that layer off the rest of the dashboard.
class _DistributionChart extends StatelessWidget {
  final List<({String category, double amount})> totals;
  final double totalExpense;

  const _DistributionChart({required this.totals, required this.totalExpense});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final topShare = (totals.first.amount / totalExpense * 100).round();

    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            // The ring draws itself in once: a clear filler slice shrinks
            // while the real slices grow.
            child: AnimatedRatio(
              value: 1,
              duration: const Duration(milliseconds: 900),
              builder: (context, sweep) {
                final total =
                    totals.fold<double>(0, (sum, item) => sum + item.amount);
                return PieChart(
                  PieChartData(
                    startDegreeOffset: -90,
                    sectionsSpace: sweep < 1 ? 0 : 2,
                    centerSpaceRadius: 34,
                    centerSpaceColor: isDark
                        ? AppColors.darkSurface
                        : AppColors.lightSurface,
                    sections: [
                      for (var i = 0; i < totals.length; i++)
                        PieChartSectionData(
                          value: totals[i].amount * sweep,
                          color: categoryChartColor(
                            context,
                            totals[i].category,
                          ),
                          radius: i == 0 ? 18 : 15,
                          showTitle: false,
                        ),
                      if (sweep < 1)
                        PieChartSectionData(
                          value: total * (1 - sweep),
                          color: Colors.transparent,
                          radius: 15,
                          showTitle: false,
                        ),
                    ],
                  ),
                  // After the first sweep, data changes glide between values.
                  swapAnimationDuration:
                      sweep < 1 ? Duration.zero : AppMotion.slow,
                  swapAnimationCurve: AppMotion.enter,
                );
              },
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$topShare%',
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              Text(
                totals.first.category,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: 10.5,
                  color: textPrimary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistributionLegend extends StatelessWidget {
  final List<({String category, double amount})> totals;
  final double totalExpense;

  const _DistributionLegend({required this.totals, required this.totalExpense});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: totals.take(5).map((item) {
        final share = (item.amount / totalExpense * 100).round();
        final swatch = categoryChartColor(context, item.category);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: swatch.withValues(alpha: 0.35),
                      blurRadius: 5,
                      spreadRadius: 0.4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              Text(
                '$share%',
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// Active goals in a PageView — one goal per page; swipe to move between them.
class _SavingGoalCard extends StatefulWidget {
  final bool compact;
  final List<SavingsGoal> goals;
  final TransactionStore store;
  final VoidCallback onTap;

  const _SavingGoalCard({
    this.compact = false,
    required this.goals,
    required this.store,
    required this.onTap,
  });

  @override
  State<_SavingGoalCard> createState() => _SavingGoalCardState();
}

class _SavingGoalCardState extends State<_SavingGoalCard> {
  late final PageController _controller;
  String? _goalId;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (widget.goals.isNotEmpty) {
      _goalId = widget.goals.first.id;
    }
  }

  @override
  void didUpdateWidget(covariant _SavingGoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVisibleGoal();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Keeps the pager on the same goal id when the goals list changes.
  void _syncVisibleGoal() {
    final goals = widget.goals;
    if (goals.isEmpty) {
      _goalId = null;
      return;
    }

    var index = goals.indexWhere((goal) => goal.id == _goalId);
    if (index < 0) {
      index = 0;
    }
    _goalId = goals[index].id;

    if (!_controller.hasClients) {
      return;
    }

    final current = _controller.page?.round() ?? _controller.initialPage;
    if (current == index) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final length = widget.goals.length;
      if (length == 0) {
        return;
      }
      final next = index.clamp(0, length - 1);
      if ((_controller.page?.round() ?? _controller.initialPage) != next) {
        _controller.jumpToPage(next);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final compact = widget.compact;
    final goals = widget.goals;

    if (goals.isEmpty) {
      return _SectionCard(
        title: 'هدف التوفير',
        compact: compact,
        centerChild: compact,
        onTap: widget.onTap,
        child: Text(
          'لا يوجد هدف حالياً',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w700,
            color: textSecondary,
          ),
        ),
      );
    }

    final inactiveDot = textPrimary.withValues(alpha: 0.22);

    return _SectionCard(
      title: 'هدف التوفير',
      compact: compact,
      centerChild: compact,
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: compact ? 128 : 150,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                return notification.metrics.axis == Axis.horizontal;
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: goals.length,
                physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
                onPageChanged: (index) {
                  _goalId = goals[index].id;
                },
                itemBuilder: (context, index) {
                  final goal = goals[index];
                  final saved = widget.store.currentSaved(goal);
                  final target = goal.targetAmount;
                  final ratio = target <= 0
                      ? 0.0
                      : (saved / target).clamp(0.0, 1.0);

                  return Center(
                    child: _SavingGoalPage(
                      compact: compact,
                      ratio: ratio,
                      saved: saved,
                      target: target,
                      accent: accent,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          _PageDots(
            controller: _controller,
            count: goals.length,
            activeColor: accent,
            inactiveColor: inactiveDot,
          ),
        ],
      ),
    );
  }
}

// Page dots under a dashboard pager. Follows the same direction as the
// PageView, so the highlighted dot stays aligned in RTL.
class _PageDots extends StatelessWidget {
  final PageController controller;
  final int count;
  final Color activeColor;
  final Color inactiveColor;

  const _PageDots({
    required this.controller,
    required this.count,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < count; index++)
              _PageDot(
                selected: 1 - (page - index).abs().clamp(0.0, 1.0),
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
          ],
        );
      },
    );
  }
}

class _PageDot extends StatelessWidget {
  final double selected;
  final Color activeColor;
  final Color inactiveColor;

  const _PageDot({
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final width = 6 + (8 * selected);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        width: width,
        height: 6,
        decoration: BoxDecoration(
          color: Color.lerp(inactiveColor, activeColor, selected),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _SavingGoalPage extends StatelessWidget {
  final bool compact;
  final double ratio;
  final double saved;
  final double target;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const _SavingGoalPage({
    required this.compact,
    required this.ratio,
    required this.saved,
    required this.target,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _VerticalProgress(
              ratio: ratio,
              width: compact ? 26 : 30,
              height: compact ? 92 : 96,
              trackColor: textPrimary.withValues(alpha: 0.08),
              fillColor: accent,
            ),
            SizedBox(width: compact ? 6 : 10),
            Flexible(
              child: Text(
                '${(ratio * 100).round()}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: compact ? 11 : 12.5,
                  fontWeight: FontWeight.w700,
                  color: textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${formatMoney(saved)} / ${formatMoney(target)}',
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              fontSize: compact ? 14 : 17,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _VerticalProgress extends StatelessWidget {
  final double ratio;
  final double width;
  final double height;
  final Color trackColor;
  final Color fillColor;

  const _VerticalProgress({
    required this.ratio,
    required this.trackColor,
    required this.fillColor,
    this.width = 26,
    this.height = 92,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: trackColor)),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedRatio(
                value: ratio,
                builder: (context, shown) => FractionallySizedBox(
                  heightFactor: shown,
                  child: Container(width: width, color: fillColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Two pages in one card: the last expenses and the obligations. Swiping
// switches pages; a tap opens the full screen of the visible page.
class _ExpensesAndObligationsCard extends StatefulWidget {
  final List<WaffrTransaction> expenses;
  final List<RecurringExpense> obligations;
  final bool compact;

  const _ExpensesAndObligationsCard({
    required this.expenses,
    required this.obligations,
    this.compact = false,
  });

  @override
  State<_ExpensesAndObligationsCard> createState() =>
      _ExpensesAndObligationsCardState();
}

class _ExpensesAndObligationsCardState
    extends State<_ExpensesAndObligationsCard> {
  // The page the user last swiped to stays selected, across restarts too.
  static const String _pageKey = 'home_expenses_card_page';

  late int _page = (AppPrefs.cached?.getInt(_pageKey) ?? 0).clamp(0, 1);
  late final PageController _controller = PageController(initialPage: _page);

  void _onPageChanged(int index) {
    _page = index;
    AppPrefs.instance.then((prefs) => prefs.setInt(_pageKey, index));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    if (_page == 0) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const TransactionHistoryScreen.expenses(),
        ),
      );
    } else {
      showObligationsSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final compact = widget.compact;

    List<Widget> pages() => [
          _RecentExpensesPage(expenses: widget.expenses, compact: compact),
          _ObligationsPage(obligations: widget.obligations, compact: compact),
        ];

    return _SectionCard(
      onTap: _open,
      compact: compact,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The hidden stack sizes the card to the taller page, so swiping
          // never changes the card's height.
          Stack(
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: IndexedStack(children: pages()),
              ),
              Positioned.fill(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    return notification.metrics.axis == Axis.horizontal;
                  },
                  child: PageView(
                    controller: _controller,
                    physics: const PageScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    onPageChanged: _onPageChanged,
                    children: pages(),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          _PageDots(
            controller: _controller,
            count: 2,
            activeColor: accent,
            inactiveColor: textPrimary.withValues(alpha: 0.22),
          ),
        ],
      ),
    );
  }
}

// Last three expenses from the store.
class _RecentExpensesPage extends StatelessWidget {
  final List<WaffrTransaction> expenses;
  final bool compact;

  const _RecentExpensesPage({required this.expenses, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final latest = expenses.take(3).toList();

    return _CardPage(
      title: 'آخر المصروفات',
      compact: compact,
      child: latest.isEmpty
          ? _EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'لا يوجد مصروف مسجّل بعد',
              compact: compact,
            )
          : Column(
              children: [
                for (int index = 0; index < latest.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: compact ? 11 : 16,
                      thickness: 1,
                      color: textPrimary.withValues(alpha: 0.08),
                    ),
                  // Keyed by id so only a newly added expense plays the
                  // entrance; rows already shown keep their state.
                  Reveal(
                    key: ValueKey(latest[index].id),
                    index: index,
                    child: _ExpenseRow(expense: latest[index], compact: compact),
                  ),
                ],
              ],
            ),
    );
  }
}

// Up to three obligations: those waiting for the user first, then the
// nearest charge dates.
class _ObligationsPage extends StatelessWidget {
  final List<RecurringExpense> obligations;
  final bool compact;

  const _ObligationsPage({required this.obligations, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final now = deviceNow();
    final active = obligations.where((item) => item.enabled).toList()
      ..sort((a, b) {
        final aFirst = obligationNeedsAttention(a, now: now) ? 0 : 1;
        final bFirst = obligationNeedsAttention(b, now: now) ? 0 : 1;
        if (aFirst != bFirst) return aFirst.compareTo(bFirst);
        return a.nextDueAt.compareTo(b.nextDueAt);
      });
    final shown = active.take(3).toList();

    return _CardPage(
      title: 'الالتزامات',
      compact: compact,
      child: shown.isEmpty
          ? _EmptyState(
              icon: Icons.event_repeat_outlined,
              message: 'لا توجد التزامات بعد',
              compact: compact,
            )
          : Column(
              children: [
                for (int index = 0; index < shown.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: compact ? 11 : 16,
                      thickness: 1,
                      color: textPrimary.withValues(alpha: 0.08),
                    ),
                  _ObligationRow(
                    item: shown[index],
                    now: now,
                    compact: compact,
                  ),
                ],
              ],
            ),
    );
  }
}

// Title plus body, laid out like [_SectionCard] for pages inside a card.
class _CardPage extends StatelessWidget {
  final String title;
  final Widget child;
  final bool compact;

  const _CardPage({
    required this.title,
    required this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionTitle(title: title, compact: compact),
        SizedBox(height: compact ? 14 : 16),
        child,
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final WaffrTransaction expense;
  final bool compact;

  const _ExpenseRow({required this.expense, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final category = categoryFor(expense.category);
    final note = expense.note;

    final amount = Text(
      '${formatMoney(expense.amount)} $currencyLabel',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
        fontSize: compact ? 11.5 : 14,
        fontWeight: FontWeight.bold,
        color: accent,
      ),
    );

    final iconSize = compact ? 26.0 : 44.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.12),
          ),
          child: Icon(category.icon, size: compact ? 14 : 21, color: accent),
        ),
        SizedBox(width: compact ? 6 : 12),
        Expanded(
          flex: compact ? 6 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: compact ? 12.5 : 15.5,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              if (note != null && note.isNotEmpty) ...[
                SizedBox(height: compact ? 1 : 2),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                    fontSize: compact ? 10.5 : 12.5,
                    color: textSecondary,
                  ),
                ),
              ],
              SizedBox(height: compact ? 1 : 3),
              Text(
                '${formatDate(expense.dateTime)} • ${formatTime(expense.dateTime)}',
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: compact ? 9 : 11,
                  color: textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: compact ? 4 : 8),
        if (compact)
          Expanded(
            flex: 5,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: amount,
            ),
          )
        else
          Padding(padding: const EdgeInsets.only(top: 2), child: amount),
      ],
    );
  }
}

// One obligation, styled like [_ExpenseRow].
class _ObligationRow extends StatelessWidget {
  final RecurringExpense item;
  final DateTime now;
  final bool compact;

  const _ObligationRow({
    required this.item,
    required this.now,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final warning = AppColors.warningOf(context);

    final category = categoryFor(item.category);
    final attention = obligationNeedsAttention(item, now: now);
    final iconSize = compact ? 26.0 : 44.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.12),
          ),
          child: Icon(category.icon, size: compact ? 14 : 21, color: accent),
        ),
        SizedBox(width: compact ? 6 : 12),
        Expanded(
          flex: compact ? 6 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                obligationTitle(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: compact ? 12.5 : 15.5,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: compact ? 1 : 2),
              Text(
                obligationStatus(item, now: now, short: compact),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: compact ? 10.5 : 12.5,
                  fontWeight: attention ? FontWeight.w700 : FontWeight.w400,
                  color: attention ? warning : textSecondary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: compact ? 4 : 8),
        Expanded(
          flex: compact ? 5 : 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)}',
              maxLines: 1,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: compact ? 11.5 : 14,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Shared glass card shell used by the dashboard sections.
class _SectionCard extends StatelessWidget {
  final String? title;
  final String? caption;
  final Widget child;
  final bool compact;

  // Centers [child] in the leftover height; used in fixed-height rows.
  final bool centerChild;

  // Opens the screen with the card's full details.
  final VoidCallback? onTap;

  const _SectionCard({
    required this.child,
    this.title,
    this.caption,
    this.compact = false,
    this.centerChild = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final padding = compact
        ? const EdgeInsets.fromLTRB(16, 15, 16, 16)
        : const EdgeInsets.fromLTRB(20, 18, 20, 20);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          _SectionTitle(title: title!, caption: caption, compact: compact),
          SizedBox(height: compact ? 14 : 16),
        ],
        if (centerChild) Expanded(child: Center(child: child)) else child,
      ],
    );

    if (onTap == null) {
      return GlassContainer(
        colorType: GlassColorType.surface,
        borderRadius: 28,
        padding: padding,
        child: content,
      );
    }

    return GlassButton(
      onTap: onTap!,
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: padding,
      child: content,
    );
  }
}

// Card title with an optional caption beside it.
class _SectionTitle extends StatelessWidget {
  final String title;
  final String? caption;
  final bool compact;

  const _SectionTitle({
    required this.title,
    this.caption,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
        fontSize: compact ? 14.5 : 16,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
    );

    if (caption == null) return titleText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        titleText,
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            caption!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              fontSize: compact ? 10.5 : 11,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool compact;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(icon: icon, title: message, compact: compact);
  }
}
