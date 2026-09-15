import 'package:flutter/material.dart';
import 'package:waffer/core/data/calendar_period.dart';
import 'package:waffer/core/data/savings_goal.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/screens/offline/savings/sheets/completed_goals_sheet.dart';
import 'package:waffer/screens/offline/savings/sheets/create_goal_sheet.dart';
import 'package:waffer/screens/offline/savings/sheets/manual_save_sheet.dart';
import 'package:waffer/screens/offline/savings/sheets/periodic_goals_sheet.dart';
import 'package:waffer/screens/offline/savings/sheets/shopping_list_sheet.dart';
import 'package:waffer/screens/offline/savings/sheets/recurring_expenses_sheet.dart';
import 'package:waffer/screens/offline/savings/sheets/withdraw_savings_sheet.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  static const int _maxPeriodOffset = 240;

  final TransactionStore _store = TransactionStore.instance;
  final PageController _periodController = PageController();

  SavingsRange _range = SavingsRange.month;
  int _periodOffset = 0;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded().then((_) => _store.processDuePeriods());
  }

  @override
  void dispose() {
    _periodController.dispose();
    super.dispose();
  }

  void _selectRange(SavingsRange range) {
    if (_range == range) return;

    setState(() {
      _range = range;
      _periodOffset = 0;
    });

    if (_periodController.hasClients) {
      _periodController.jumpToPage(0);
    }
  }

  void _showOlderPeriod() {
    if (_periodOffset >= _maxPeriodOffset - 1) return;

    _periodController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _showNewerPeriod() {
    if (_periodOffset == 0) return;

    _periodController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final goal = _store.activeGoal;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
          child: Column(
            children: [
              _TimeRangeSelector(selected: _range, onSelected: _selectRange),

              const SizedBox(height: 10),

              SizedBox(
                height: 108,
                child: PageView.builder(
                  controller: _periodController,
                  itemCount: _maxPeriodOffset,
                  clipBehavior: Clip.none,
                  onPageChanged: (index) {
                    setState(() => _periodOffset = index);
                  },
                  itemBuilder: (context, offset) {
                    final pagePeriod = CalendarPeriod.forRange(_range, offset);

                    final previousPeriod = CalendarPeriod.forRange(
                      _range,
                      offset + 1,
                    );

                    return _PeriodSavingsCard(
                      range: _range,
                      period: pagePeriod,
                      amount: _store.savingsNetDuring(
                        pagePeriod.start,
                        pagePeriod.end,
                      ),
                      previousAmount: _store.savingsNetDuring(
                        previousPeriod.start,
                        previousPeriod.end,
                      ),
                      isCurrent: offset == 0,
                      canShowNewer: offset > 0,
                      onOlder: _showOlderPeriod,
                      onNewer: _showNewerPeriod,
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // إجمالي الادخار + أزرار التحكم
              _SplitActionRow(
                leading: _TotalSavingsCard(total: _store.savingsBalance),
                first: _ActionButton(
                  label: 'ادخار مبلغ',
                  onTap: () => showManualSaveSheet(context),
                ),
                second: _ActionButton(
                  label: 'سحب إلى الرصيد',
                  onTap: () => showWithdrawSavingsSheet(context),
                ),
              ),

              const SizedBox(height: 12),

              // الهدف + أزرار الأهداف
              _SplitActionRow(
                leading: goal == null
                    ? _CreateGoalCard(
                        onCreate: () => showCreateGoalSheet(context),
                      )
                    : _GoalProgressCard(
                        goal: goal,
                        saved: _store.goalProgress(goal),
                      ),
                first: _ActionButton(
                  label: 'خطط دورية',
                  mark: false,
                  onTap: () => showPeriodicGoalsSheet(context),
                ),
                second: _ActionButton(
                  label: 'الأهداف المحققة',
                  onTap: () => showCompletedGoalsSheet(context),
                ),
              ),

              const SizedBox(height: 12),

              const ShoppingListPreviewCard(),

              const SizedBox(height: 12),

            ],
          ),
        );
      },
    );
  }
}

class _TimeRangeSelector extends StatelessWidget {
  final SavingsRange selected;
  final ValueChanged<SavingsRange> onSelected;

  const _TimeRangeSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = _SavingsColors.of(context);
    final ranges = SavingsRange.values;
    final selectedIndex = ranges.indexOf(selected);

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.all(5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / ranges.length;

          return Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                start: selectedIndex * itemWidth,
                width: itemWidth,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(23),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final range in ranges)
                    Expanded(
                      child: Semantics(
                        selected: selected == range,
                        button: true,
                        label: range.label,
                        child: GestureDetector(
                          onTap: () => onSelected(range),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 11,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: selected == range
                                      ? colors.surface
                                      : colors.textPrimary,
                                ),
                                child: Text(range.label, maxLines: 1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PeriodSavingsCard extends StatelessWidget {
  final SavingsRange range;
  final CalendarPeriod period;
  final double amount;
  final double previousAmount;
  final bool isCurrent;
  final bool canShowNewer;
  final VoidCallback onOlder;
  final VoidCallback onNewer;

  const _PeriodSavingsCard({
    required this.range,
    required this.period,
    required this.amount,
    required this.previousAmount,
    required this.isCurrent,
    required this.canShowNewer,
    required this.onOlder,
    required this.onNewer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _SavingsColors.of(context);

    final comparison = _SavingsComparison.calculate(
      current: amount,
      previous: previousAmount,
      colors: colors,
    );

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      height: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PeriodArrow(
                icon: Icons.chevron_right_rounded,
                tooltip: 'الفترة الأحدث',
                enabled: canShowNewer,
                onTap: onNewer,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'المبلغ الموفر',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        isCurrent
                            ? CalendarPeriod.currentPeriodCaption(range)
                            : CalendarPeriod.rangeLabel(range, period),
                        key: ValueKey(period.start),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _PeriodArrow(
                icon: Icons.chevron_left_rounded,
                tooltip: 'الفترة السابقة',
                enabled: true,
                onTap: onOlder,
              ),
            ],
          ),

          const SizedBox(height: 2),

          if (amount <= 0)
            Text(
              'لا يوجد توفير في هذه الفترة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: colors.textPrimary.withValues(alpha: 0.55),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(amount),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  currencyLabel,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
                if (comparison != null) ...[
                  const SizedBox(width: 8),
                  Icon(comparison.icon, size: 15, color: comparison.color),
                  const SizedBox(width: 2),
                  Text(
                    comparison.text,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: comparison.color,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _SavingsComparison {
  final IconData icon;
  final Color color;
  final String text;

  const _SavingsComparison({
    required this.icon,
    required this.color,
    required this.text,
  });

  static _SavingsComparison? calculate({
    required double current,
    required double previous,
    required _SavingsColors colors,
  }) {
    if (previous <= 0) return null;

    final percentage = (current - previous) / previous * 100;

    if (percentage == 0) return null;

    final isPositive = percentage > 0;

    return _SavingsComparison(
      icon: isPositive
          ? Icons.trending_up_rounded
          : Icons.trending_down_rounded,
      color: isPositive ? colors.accent : colors.textPrimary,
      text:
          '${isPositive ? '+' : '−'}'
          '${percentage.abs().toStringAsFixed(0)}%',
    );
  }
}

class _PeriodArrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _PeriodArrow({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _SavingsColors.of(context);

    return IconButton(
      onPressed: enabled ? onTap : null,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        icon,
        color: enabled
            ? colors.accent
            : colors.textSecondary.withValues(alpha: 0.35),
      ),
    );
  }
}

class _SplitActionRow extends StatelessWidget {
  final Widget leading;
  final Widget first;
  final Widget second;

  const _SplitActionRow({
    required this.leading,
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الكرت الرئيسي — على اليمين بسبب RTL
          Expanded(flex: 72, child: leading),

          const SizedBox(width: 10),

          // الزرين — على اليسار بسبب RTL
          Expanded(
            flex: 28,
            child: Column(
              children: [
                Expanded(child: first),
                const SizedBox(height: 8),
                Expanded(child: second),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalSavingsCard extends StatelessWidget {
  final double total;

  const _TotalSavingsCard({required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = _SavingsColors.of(context);

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  size: 19,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'إجمالي المبالغ الموفرة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (total <= 0)
            Text(
              'لا توجد مبالغ موفرة بعد',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary.withValues(alpha: 0.65),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      formatMoney(total),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    currencyLabel,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 7),

          Text(
            total > 0
                ? 'إجمالي المبلغ المدخر حالياً'
                : 'ادخر أول مبلغ ليظهر هنا',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              color: colors.textSecondary.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool mark;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.mark = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _SavingsColors.of(context);

    return GlassButton(
      onTap: onTap,
      colorType: GlassColorType.surface,
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mark) ...[const SizedBox(height: 2)],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateGoalCard extends StatelessWidget {
  final VoidCallback onCreate;

  const _CreateGoalCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final colors = _SavingsColors.of(context);

    return GlassButton(
      onTap: onCreate,
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Text(
            'إنشاء هدف',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalProgressCard extends StatelessWidget {
  final SavingsGoal goal;
  final double saved;

  const _GoalProgressCard({required this.goal, required this.saved});

  @override
  Widget build(BuildContext context) {
    final colors = _SavingsColors.of(context);

    final ratio = goal.targetAmount <= 0
        ? 0.0
        : (saved / goal.targetAmount).clamp(0.0, 1.0);

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // اسم الهدف
          Text(
            goal.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),

          const SizedBox(height: 10),

          // البار الأفقي + النسبة
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _HorizontalProgress(
                  ratio: ratio,
                  height: 18,
                  trackColor: colors.textPrimary.withValues(alpha: 0.08),
                  fillColor: colors.accent,
                ),
              ),

              const SizedBox(width: 10),

              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // المبلغ الحالي / الهدف
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${formatMoney(saved)} / ${formatMoney(goal.targetAmount)}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),

          const SizedBox(height: 2),

          Text(
            currencyLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalProgress extends StatelessWidget {
  final double ratio;
  final double height;
  final Color trackColor;
  final Color fillColor;

  const _HorizontalProgress({
    required this.ratio,
    required this.trackColor,
    required this.fillColor,
    this.height = 18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          children: [
            // خلفية البار
            Positioned.fill(child: ColoredBox(color: trackColor)),

            // نسبة التقدم
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: ratio.clamp(0.0, 1.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  height: height,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavingsColors {
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const _SavingsColors({
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  factory _SavingsColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _SavingsColors(
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      accent: isDark ? AppColors.darkAccent : AppColors.lightAccent,
      textPrimary: isDark
          ? AppColors.darkTextPrimary
          : AppColors.lightTextPrimary,
      textSecondary: isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary,
    );
  }
}
