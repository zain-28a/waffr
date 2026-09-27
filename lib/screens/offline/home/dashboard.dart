import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:waffer/data/stores/category_store.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/data/models/expense_categories.dart';
import 'package:waffer/data/models/savings_goal.dart';
import 'package:waffer/data/models/transaction.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/screens/offline/home/sheets/add_expense_sheet.dart';
import 'package:waffer/screens/offline/home/sheets/add_income_sheet.dart';
import 'package:waffer/screens/offline/report/reportscreen.dart';
import 'package:waffer/screens/offline/savings/sheets/shopping_list_sheet.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';

// Offline home tab: balance, add actions, spending distribution, recent
// expenses, and active savings goals — all from TransactionStore.

const double kBalanceCardActionTop = 14;
const double kBalanceCardActionEnd = 14;
const double kBalanceCardActionGap = 8;
const double kDashboardCardActionSize = 48;

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
  ]);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    CategoryStore.instance.ensureLoaded();
    CurrencyStore.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: _listenables,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BalanceCard(
                balance: _store.balance,
                spent: _store.totalExpense,
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
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'إضافة دخل',
                      icon: Icons.add_circle_outline_rounded,
                      onTap: () => showAddIncomeSheet(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ActionButton(
                      label: 'إضافة مصروف',
                      icon: Icons.remove_circle_outline_rounded,
                      onTap: () => showAddExpenseSheet(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // expensesByCategory is rolled up in memory from the store.
              _DistributionCard(
                totals: _store.expensesByCategory(),
                totalExpense: _store.totalExpense,
              ),
              const SizedBox(height: 6),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _RecentExpensesCard(
                        expenses: _store.expenses,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: _SavingGoalCard(
                        compact: true,
                        goals: _store.activeGoals,
                        store: _store,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BalanceCardIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _BalanceCardIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return GlassButton(
      onTap: onTap,
      width: kDashboardCardActionSize,
      height: kDashboardCardActionSize,
      borderRadius: 999,
      padding: EdgeInsets.zero,
      colorType: GlassColorType.surface,
      child: Center(
        child: Icon(
          icon,
          color: accent,
          size: 22,
        ),
      ),
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
              duration: const Duration(milliseconds: 280),
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
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
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
                            child: Text(
                              formatMoney(balance),
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${(ratio * 100).round()}%',
                        style: TextStyle(
                          fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    _HorizontalProgress(
                      ratio: ratio,
                      trackColor: accent.withValues(alpha: 0.12),
                      fillColor: accent,
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
          PositionedDirectional(
            top: kBalanceCardActionTop,
            end: kBalanceCardActionEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BalanceCardIconButton(
                  icon: Icons.payments_outlined,
                  onTap: onIncomeLog,
                ),
                const SizedBox(width: kBalanceCardActionGap),
                _BalanceCardIconButton(
                  icon: Icons.format_list_bulleted_rounded,
                  onTap: onShoppingList,
                ),
              ],
            ),
          ),
        ],
      ),
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                color: fillColor,
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

  const _DistributionCard({required this.totals, required this.totalExpense});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'توزيع المصروفات',
      caption: 'النسبة من إجمالي الصرف وليس الرصيد',
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
            child: PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 2,
                centerSpaceRadius: 34,
                centerSpaceColor: isDark
                    ? AppColors.darkSurface
                    : AppColors.lightSurface,
                sections: [
                  for (var i = 0; i < totals.length; i++)
                    PieChartSectionData(
                      value: totals[i].amount,
                      color: categoryChartColor(context, totals[i].category),
                      radius: i == 0 ? 18 : 15,
                      showTitle: false,
                    ),
                ],
              ),
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

  const _SavingGoalCard({
    this.compact = false,
    required this.goals,
    required this.store,
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
          _GoalPageDots(
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

// Page dots under the goals pager. Follows the same direction as the
// PageView, so the highlighted dot stays aligned in RTL.
class _GoalPageDots extends StatelessWidget {
  final PageController controller;
  final int count;
  final Color activeColor;
  final Color inactiveColor;

  const _GoalPageDots({
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
              _GoalPageDot(
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

class _GoalPageDot extends StatelessWidget {
  final double selected;
  final Color activeColor;
  final Color inactiveColor;

  const _GoalPageDot({
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
              child: FractionallySizedBox(
                heightFactor: ratio.clamp(0.0, 1.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  width: width,
                  color: fillColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Last few expenses from the store (up to three rows).
class _RecentExpensesCard extends StatelessWidget {
  final List<WafferTransaction> expenses;
  final bool compact;

  const _RecentExpensesCard({required this.expenses, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final latest = expenses.take(3).toList();

    return _SectionCard(
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
                  _ExpenseRow(expense: latest[index], compact: compact),
                ],
              ],
            ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final WafferTransaction expense;
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

// Shared glass card shell used by the dashboard sections.
class _SectionCard extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget child;
  final bool compact;

  // Centers [child] in the leftover height; used in fixed-height rows.
  final bool centerChild;

  const _SectionCard({
    required this.title,
    required this.child,
    this.caption,
    this.compact = false,
    this.centerChild = false,
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

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: compact
          ? const EdgeInsets.fromLTRB(16, 15, 16, 16)
          : const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (caption == null)
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: compact ? 14.5 : 16,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                    fontSize: compact ? 14.5 : 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
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
            ),
          SizedBox(height: compact ? 14 : 16),
          if (centerChild) Expanded(child: Center(child: child)) else child,
        ],
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 12 : 18),
      child: Column(
        children: [
          Icon(
            icon,
            size: compact ? 30 : 38,
            color: textPrimary.withValues(alpha: 0.3),
          ),
          SizedBox(height: compact ? 8 : 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              fontSize: compact ? 12 : 13.5,
              color: textPrimary.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
