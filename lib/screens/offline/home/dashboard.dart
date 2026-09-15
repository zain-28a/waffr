import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:waffer/core/data/expense_categories.dart';
import 'package:waffer/core/data/transaction.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/screens/offline/home/sheets/add_expense_sheet.dart';
import 'package:waffer/screens/offline/home/sheets/add_income_sheet.dart';
import 'package:waffer/screens/offline/savings/sheets/recurring_expenses_sheet.dart';
import 'package:waffer/screens/offline/savings/sheets/shopping_list_sheet.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';

const double kDashboardListFabEnd = 31;
const double kDashboardListFabBottom = 614;
const double kDashboardListFabSize = 48;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TransactionStore _store = TransactionStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return Stack(
          children: [
            SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BalanceCard(
                balance: _store.balance,
                spent: _store.totalExpense,
                maxBalance: _store.maxBalance,
                ratio: _store.remainingRatio,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'إضافة دخل',
                      icon: Icons.add_circle_outline_rounded,
                      onTap: () => showAddIncomeSheet(context),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _ActionButton(
                      label: 'إضافة مصروف',
                      icon: Icons.remove_circle_outline_rounded,
                      onTap: () => showAddExpenseSheet(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DistributionCard(
                totals: _store.expensesByCategory(),
                totalExpense: _store.totalExpense,
              ),
              const SizedBox(height: 16),
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
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 4,
                      child: _SavingGoalCard(
                        compact: true,
                        saved: _store.activeGoal == null
                            ? 0
                            : _store.goalProgress(_store.activeGoal!),
                        target: _store.activeGoal?.targetAmount ?? 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
            PositionedDirectional(
              end: kDashboardListFabEnd,
              bottom: kDashboardListFabBottom,
              child: _DashboardListFab(
                onTap: () => showShoppingListSheet(context)
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardListFab extends StatelessWidget {
  final VoidCallback onTap;

  const _DashboardListFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return GlassButton(
      onTap: onTap,
      width: kDashboardListFabSize,
      height: kDashboardListFabSize,
      borderRadius: 999,
      padding: EdgeInsets.zero,
      colorType: GlassColorType.surface,
      child: Center(
        child: Icon(
          Icons.format_list_bulleted_rounded,
          color: accent,
          size: 22,
        ),
      ),
    );
  }
}

// ================= الرصيد =================

class _BalanceCard extends StatelessWidget {
  final double balance;
  final double spent;
  final double maxBalance;
  final double ratio;

  const _BalanceCard({
    required this.balance,
    required this.spent,
    required this.maxBalance,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الرصيد الحالي',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13.5,
              color: textSecondary,
            ),
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
                      fontFamily: 'Cairo',
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
                  fontFamily: 'Cairo',
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
                fontFamily: 'Cairo',
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
              fontFamily: 'Cairo',
              fontSize: 12.5,
              color: textSecondary,
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

// ================= أزرار الإضافة =================

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
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

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
                fontFamily: 'Cairo',
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

// ================= توزيع المصروفات =================

class _DistributionCard extends StatelessWidget {
  final List<({String category, double amount})> totals;
  final double totalExpense;

  const _DistributionCard({
    required this.totals,
    required this.totalExpense,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'توزيع المصروفات',
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

class _DistributionChart extends StatelessWidget {
  final List<({String category, double amount})> totals;
  final double totalExpense;

  const _DistributionChart({
    required this.totals,
    required this.totalExpense,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    final topShare = (totals.first.amount / totalExpense * 100).round();

    return SizedBox(
      width: 118,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 2,
                centerSpaceRadius: 34,
                sections: totals
                    .map(
                      (item) => PieChartSectionData(
                        value: item.amount,
                        color: categoryFor(item.category).color,
                        radius: 20,
                        showTitle: false,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$topShare%',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              Text(
                totals.first.category,
                style: TextStyle(
                  fontFamily: 'Cairo',
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

  const _DistributionLegend({
    required this.totals,
    required this.totalExpense,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: totals.take(5).map((item) {
        final share = (item.amount / totalExpense * 100).round();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: categoryFor(item.category).color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              Text(
                '$share%',
                style: TextStyle(
                  fontFamily: 'Cairo',
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

// ================= هدف التوفير =================

class _SavingGoalCard extends StatelessWidget {
  final bool compact;
  final double saved;
  final double target;

  const _SavingGoalCard({
    this.compact = false,
    this.saved = 0,
    this.target = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final ratio = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);

    if (target <= 0) {
      return _SectionCard(
        title: 'هدف التوفير',
        compact: compact,
        centerChild: compact,
        child: Text(
          'لا يوجد هدف حالياً',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w700,
            color: textSecondary,
          ),
        ),
      );
    }

    return _SectionCard(
      title: 'هدف التوفير',
      compact: compact,
      centerChild: compact,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                    fontFamily: 'Cairo',
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
                fontFamily: 'Cairo',
                fontSize: compact ? 14 : 17,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
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

// ================= آخر المصروفات =================

class _RecentExpensesCard extends StatelessWidget {
  final List<WafferTransaction> expenses;
  final bool compact;

  const _RecentExpensesCard({
    required this.expenses,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

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
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final category = categoryFor(expense.category);
    final note = expense.note;

    final amount = Text(
      '${formatMoney(expense.amount)} $currencyLabel',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontFamily: 'Cairo',
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
          child: Icon(
            category.icon,
            size: compact ? 14 : 21,
            color: accent,
          ),
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
                  fontFamily: 'Cairo',
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
                    fontFamily: 'Cairo',
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
                  fontFamily: 'Cairo',
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
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: amount,
          ),
      ],
    );
  }
}

// ================= عناصر مشتركة =================

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool compact;

  /// يوسّط المحتوى في المساحة المتبقية، ويُستخدم فقط داخل صف بارتفاع محدَّد.
  final bool centerChild;

  const _SectionCard({
    required this.title,
    required this.child,
    this.compact = false,
    this.centerChild = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: compact
          ? const EdgeInsets.fromLTRB(16, 15, 16, 16)
          : const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 14.5 : 16,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
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

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

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
              fontFamily: 'Cairo',
              fontSize: compact ? 12 : 13.5,
              color: textPrimary.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
