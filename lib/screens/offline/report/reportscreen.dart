// Offline spending report: range chips, a swipeable period chart (fl_chart),
// total spent, category distribution, and a comparison with the previous period.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/screens/shell/app_shell_scope.dart';
import 'package:waffr/widgets/containers/app_empty_state.dart';
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/insights/spending_improvement.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/shopping_list_store.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/button/glass_button.dart';
import 'package:waffr/widgets/containers/glass.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';
import 'package:waffr/widgets/dialogs/waffr_date_picker.dart';
import 'package:waffr/screens/offline/report/expense_history_share.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/widgets/smart/smart_analysis_button.dart';

// Picks a range (day / week / month / 3 months / 6 months / year) via chips.
// A horizontal PageView pages between older and newer periods; itemBuilder
// builds one _SpendingChartCard per offset (not every period at once).
// Below the chart: total spent, category bars, and a prior-period comparison.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _maxPeriodOffset = 240;

  final TransactionStore _store = TransactionStore.instance;
  late final Listenable _listenables = Listenable.merge([
    _store,
    CategoryStore.instance,
  ]);
  final PageController _periodController = PageController();
  _ReportRange _range = _ReportRange.month;
  int _periodOffset = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    CategoryStore.instance.ensureLoaded();
  }

  @override
  void dispose() {
    _periodController.dispose();
    super.dispose();
  }

  // Switching range resets to the current period (offset 0).
  void _selectRange(_ReportRange range) {
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
      duration: AppMotion.medium,
      curve: Curves.easeOutCubic,
    );
  }

  void _showNewerPeriod() {
    if (_periodOffset == 0) return;
    _periodController.previousPage(
      duration: AppMotion.medium,
      curve: Curves.easeOutCubic,
    );
  }

  void _openExpenseHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TransactionHistoryScreen.expenses(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: _listenables,
      builder: (context, _) {
        final expenses = _store.expenses;
        final period = _periodFor(_range, _periodOffset);
        final previousPeriod = _periodFor(_range, _periodOffset + 1);
        final report = _ReportData.from(expenses, period);
        final previousTotal = _sumExpenses(
          _expensesInPeriod(expenses, previousPeriod),
        );
        final chartHeight = (MediaQuery.sizeOf(context).height * 0.32).clamp(
          220.0,
          300.0,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, kFloatingNavClearance),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: staggered([
              SheetChoiceChips(
                options: [for (final range in _ReportRange.values) range.label],
                selected: _range.label,
                onSelected: (label) {
                  _selectRange(
                    _ReportRange.values.firstWhere((range) => range.label == label),
                  );
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: chartHeight,
                child: PageView.builder(
                  controller: _periodController,
                  itemCount: _maxPeriodOffset,
                  clipBehavior: Clip.none,
                  onPageChanged: (index) {
                    setState(() => _periodOffset = index);
                  },
                  allowImplicitScrolling: false,
                  itemBuilder: (context, offset) {
                    final pageReport = _ReportData.from(
                      expenses,
                      _periodFor(_range, offset),
                    );
                    return RepaintBoundary(
                      child: _SpendingChartCard(
                      report: pageReport,
                      canShowNewer: offset > 0,
                      onOlder: _showOlderPeriod,
                      onNewer: _showNewerPeriod,
                    ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              _SpendingSummary(
                total: report.total,
                onHistory: _openExpenseHistory,
              ),
              const SizedBox(height: 6),
              _ImprovementCard(
                currentTotal: report.total,
                previousTotal: previousTotal,
              ),
              const SizedBox(height: 6),
              _ExpenseDistribution(report: report),
            ]),
          ),
        );
      },
    );
  }
}

// Bucket width for the chart and summary (day through year).
enum _ReportRange { day, week, month, threeMonths, sixMonths, year }

extension on _ReportRange {
  String get label => switch (this) {
    _ReportRange.day => 'اليوم',
    _ReportRange.week => 'أسبوع',
    _ReportRange.month => 'شهر',
    _ReportRange.threeMonths => '3 أشهر',
    _ReportRange.sixMonths => '6 أشهر',
    _ReportRange.year => 'سنة',
  };
}

// Half-open [start, end) window for one page of the period PageView.
class _ReportPeriod {
  final DateTime start;
  final DateTime end;
  final _ReportRange range;

  const _ReportPeriod({
    required this.start,
    required this.end,
    required this.range,
  });

  // Human-readable caption shown above the chart for this window.
  String get label {
    final lastDay = end.subtract(const Duration(days: 1));
    switch (range) {
      case _ReportRange.day:
        return '${start.day} ${_monthName(start.month)} ${start.year}';
      case _ReportRange.week:
        if (start.month == lastDay.month && start.year == lastDay.year) {
          return '${start.day} – ${lastDay.day} '
              '${_monthName(start.month)} ${start.year}';
        }
        return '${start.day} ${_monthName(start.month)}'
            ' – ${lastDay.day} ${_monthName(lastDay.month)} ${lastDay.year}';
      case _ReportRange.month:
        return '${_monthName(start.month)} ${start.year}';
      case _ReportRange.threeMonths:
      case _ReportRange.sixMonths:
        if (start.year == lastDay.year) {
          return '${_monthName(start.month)} – '
              '${_monthName(lastDay.month)} ${lastDay.year}';
        }
        return '${_monthName(start.month)} ${start.year} – '
            '${_monthName(lastDay.month)} ${lastDay.year}';
      case _ReportRange.year:
        return start.year.toString();
    }
  }
}

// One category's share of spending in the selected period.
class _CategoryTotal {
  final String category;
  final double amount;

  const _CategoryTotal(this.category, this.amount);
}

// One X-axis slot on the line chart (hour, day, week, or month depending on range).
class _ChartBucket {
  final String label;
  final String axisLabel;
  final double amount;

  const _ChartBucket({
    required this.label,
    required this.axisLabel,
    required this.amount,
  });
}

// Filters expenses for a period, sums by category, and buckets them into chart points.
class _ReportData {
  final _ReportPeriod period;
  final List<WaffrTransaction> expenses;
  final double total;
  final List<_CategoryTotal> categoryTotals;
  final List<_ChartBucket> chartBuckets;

  const _ReportData({
    required this.period,
    required this.expenses,
    required this.total,
    required this.categoryTotals,
    required this.chartBuckets,
  });

  factory _ReportData.from(
    List<WaffrTransaction> allExpenses,
    _ReportPeriod period,
  ) {
    final expenses = _expensesInPeriod(allExpenses, period);
    final total = _sumExpenses(expenses);
    final totals = <String, double>{};
    for (final expense in expenses) {
      final category = categoryFor(expense.category).label;
      totals[category] = (totals[category] ?? 0) + expense.amount;
    }
    final categoryTotals =
        totals.entries
            .map((entry) => _CategoryTotal(entry.key, entry.value))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    return _ReportData(
      period: period,
      expenses: expenses,
      total: total,
      categoryTotals: categoryTotals,
      chartBuckets: _buildChartBuckets(expenses, period),
    );
  }
}

// One PageView page: period label, older/newer arrows, and the line chart (or empty state).
class _SpendingChartCard extends StatelessWidget {
  final _ReportData report;
  final bool canShowNewer;
  final VoidCallback onOlder;
  final VoidCallback onNewer;

  const _SpendingChartCard({
    required this.report,
    required this.canShowNewer,
    required this.onOlder,
    required this.onNewer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 13),
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
                      'الصرف خلال الفترة',
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.fast),
                      child: Text(
                        report.period.label,
                        key: ValueKey(report.period.start),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                          fontSize: 16,
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
          const SizedBox(height: 12),
          Expanded(
            child: report.expenses.isEmpty
                ? const _EmptyState(
                    icon: Icons.show_chart_rounded,
                    message: 'لا توجد مصروفات في هذه الفترة',
                  )
                : Directionality(
                    textDirection: TextDirection.ltr,
                    // Each period's line draws itself in from the left.
                    child: AnimatedRatio(
                      key: ValueKey(report.period.start),
                      value: 1,
                      duration: const Duration(milliseconds: 900),
                      builder: (context, shown) => RevealClip(
                        fraction: shown,
                        child: _SpendingLineChart(
                          buckets: report.chartBuckets,
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

// Chevrons that step the period PageView older or newer.
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
    final colors = AppPalette.of(context);
    return IconButton(
      onPressed: enabled ? onTap : null,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        color: enabled
            ? colors.accent
            : colors.textSecondary.withValues(alpha: 0.35),
      ),
    );
  }
}

// Maps chart buckets to FlSpot values. Y axis uses a "nice" interval so labels
// stay round. Touch shows a tooltip with the bucket label and amount. The area
// under the line is a light accent fill. Dots shrink when there are many buckets.
class _SpendingLineChart extends StatelessWidget {
  final List<_ChartBucket> buckets;

  const _SpendingLineChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final spots = [
      for (var index = 0; index < buckets.length; index++)
        FlSpot(index.toDouble(), buckets[index].amount),
    ];
    final peak = buckets.fold<double>(0, (max, item) {
      return item.amount > max ? item.amount : max;
    });
    final maxValue = math.max(peak, 1).toDouble();
    final yInterval = _niceInterval(maxValue);
    final maxY = math.max(
      yInterval,
      (maxValue / yInterval).ceil() * yInterval,
    ).toDouble();
    final maxX = math.max(1, buckets.length - 1).toDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.none(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: colors.textPrimary.withValues(alpha: 0.07),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                if (value < 0 || value > maxY) {
                  return const SizedBox.shrink();
                }
                if (value != 0 && (value - maxY).abs() < yInterval / 3) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    _axisMoney(value),
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if ((value - index).abs() > 0.05) {
                  return const SizedBox.shrink();
                }
                if (index < 0 || index >= buckets.length) {
                  return const SizedBox.shrink();
                }
                final text = buckets[index].axisLabel;
                if (text.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    text,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (bar, indexes) {
            return indexes
                .map(
                  (_) => TouchedSpotIndicatorData(
                    FlLine(
                      color: colors.accent.withValues(alpha: 0.35),
                      strokeWidth: 1,
                    ),
                    FlDotData(
                      getDotPainter: (spot, percent, bar, index) {
                        return FlDotCirclePainter(
                          radius: 4.5,
                          color: colors.accent,
                          strokeWidth: 0,
                        );
                      },
                    ),
                  ),
                )
                .toList();
          },
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipRoundedRadius: 12,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            getTooltipColor: (_) => colors.accent,
            getTooltipItems: (touched) {
              return touched.map((spot) {
                final index = spot.x.round();
                if (index < 0 || index >= buckets.length) return null;
                return LineTooltipItem(
                  '${buckets[index].label}\n'
                  '${formatMoney(spot.y)} $currencyLabel',
                  TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colors.surface,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: colors.accent,
            barWidth: 2.4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                return FlDotCirclePainter(
                  radius: buckets.length > 16 ? 2.4 : 3.4,
                  color: colors.accent,
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: colors.accent.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
      duration: AppMotion.of(context, AppMotion.medium),
      curve: Curves.easeOut,
    );
  }
}

// Total spent for the selected period, plus a shortcut into expense history.
class _SpendingSummary extends StatelessWidget {
  final double total;
  final VoidCallback onHistory;

  const _SpendingSummary({required this.total, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الصرف',
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 13.5,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: RollingMoney(
                          value: total,
                          style: TextStyle(
                            fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                            fontSize: 28,
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
                        fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: GlassButton(
            onTap: onHistory,
            colorType: GlassColorType.surface,
            borderRadius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'سجل المصروفات',
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Category share of spending: stacked color bar plus a ranked list with %.
class _ExpenseDistribution extends StatelessWidget {
  final _ReportData report;

  const _ExpenseDistribution({required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'توزيع المصروفات',
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'النسبة من إجمالي الصرف ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (report.total <= 0 || report.categoryTotals.isEmpty)
            const _EmptyState(
              icon: Icons.stacked_bar_chart_sharp,
              message: 'ستظهر تفاصيل التصنيفات بعد تسجيل مصروف',
            )
          else ...[
            _DistributionBar(
              totals: report.categoryTotals,
              total: report.total,
            ),
            const SizedBox(height: 18),
            for (
              var index = 0;
              index < report.categoryTotals.length;
              index++
            ) ...[
              if (index > 0)
                Divider(
                  height: 18,
                  color: colors.textPrimary.withValues(alpha: 0.08),
                ),
              _CategoryRow(
                item: report.categoryTotals[index],
                total: report.total,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// Single horizontal bar whose segments are proportional to category totals.
class _DistributionBar extends StatelessWidget {
  final List<_CategoryTotal> totals;
  final double total;

  const _DistributionBar({required this.totals, required this.total});

  @override
  Widget build(BuildContext context) {
    // Grows from the start edge when the card first appears.
    return AnimatedRatio(
      value: 1,
      builder: (context, shown) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: math.max(shown, 0.001),
          child: _bar(context),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            for (var index = 0; index < totals.length; index++) ...[
              if (index > 0) const SizedBox(width: 2),
              Expanded(
                flex: math.max(1, (totals[index].amount / total * 1000).round()),
                child: AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.slow),
                  curve: Curves.easeOut,
                  color: categoryChartColor(context, totals[index].category),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Icon, name, percentage, and amount for one category in the distribution list.
class _CategoryRow extends StatelessWidget {
  final _CategoryTotal item;
  final double total;

  const _CategoryRow({required this.item, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final category = categoryFor(item.category);
    final swatch = categoryChartColor(context, item.category);
    final percentage = total <= 0 ? 0 : item.amount / total * 100;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: swatch.withValues(alpha: 0.18),
          ),
          child: Icon(category.icon, size: 19, color: swatch),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            category.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
        Text(
          '${percentage.round()}%',
          style: TextStyle(
            fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${formatMoney(item.amount)} $currencyLabel',
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// How this period's spending compares to the previous window of the same range.
class _ImprovementCard extends StatelessWidget {
  final double currentTotal;
  final double previousTotal;

  const _ImprovementCard({
    required this.currentTotal,
    required this.previousTotal,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final comparison = SpendingImprovement.calculate(
      currentTotal: currentTotal,
      previousTotal: previousTotal,
    );
    final valueColor = switch (comparison.kind) {
      SpendingChange.positive => colors.accent,
      SpendingChange.negative => colors.textPrimary,
      SpendingChange.neutral => colors.textSecondary,
    };
    final icon = switch (comparison.kind) {
      SpendingChange.positive => Icons.trending_up_rounded,
      SpendingChange.negative => Icons.trending_down_rounded,
      SpendingChange.neutral => Icons.remove_rounded,
    };

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نسبة التحسن',
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(icon, size: 20, color: valueColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        comparison.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                          fontSize: comparison.hasPercentage ? 22 : 12.5,
                          fontWeight: FontWeight.bold,
                          color: valueColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comparison.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const SmartAnalysisButton(
            scope: InsightScope.reports,
            style: SmartButtonStyle.tile,
          ),
        ],
      ),
    );
  }
}

// Full expense or income ledger grouped by day, with undo actions per row.
class TransactionHistoryScreen extends StatefulWidget {
  final bool isIncome;

  const TransactionHistoryScreen.expenses({super.key}) : isIncome = false;

  const TransactionHistoryScreen.incomes({super.key}) : isIncome = true;

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen>
    with SingleTickerProviderStateMixin {
  final TransactionStore _store = TransactionStore.instance;
  late final Listenable _listenables = Listenable.merge([
    _store,
    CategoryStore.instance,
    RecurringExpenseStore.instance,
  ]);

  bool _selecting = false;
  final Set<String> _selected = <String>{};
  bool _sharing = false;
  late final AnimationController _selectionAnim;
  late final CurvedAnimation _selectionReveal;

  @override
  void initState() {
    super.initState();
    RecurringExpenseStore.instance.ensureLoaded();
    _selectionAnim = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
      reverseDuration: AppMotion.fast,
    );
    _selectionReveal = CurvedAnimation(
      parent: _selectionAnim,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _selectionAnim.addStatusListener(_onSelectionStatus);
  }

  @override
  void dispose() {
    _selectionAnim.removeStatusListener(_onSelectionStatus);
    _selectionReveal.dispose();
    _selectionAnim.dispose();
    super.dispose();
  }

  void _onSelectionStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || !_selecting) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _enterSelection({Set<String> selected = const <String>{}}) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addAll(selected);
    });
    _selectionAnim.forward();
  }

  void _exitSelection() {
    if (_selectionAnim.status == AnimationStatus.reverse ||
        _selectionAnim.status == AnimationStatus.dismissed) {
      return;
    }
    _selectionAnim.reverse();
  }

  void _toggleExpense(String id) {
    setState(() {
      if (!_selected.add(id)) {
        _selected.remove(id);
      }
    });
  }

  void _toggleDay(List<WaffrTransaction> expenses) {
    final ids = expenses.map((item) => item.id);
    final allSelected = ids.every(_selected.contains);
    setState(() {
      if (allSelected) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  void _toggleAll(List<WaffrTransaction> expenses) {
    final ids = expenses.map((item) => item.id).toSet();
    final allSelected = ids.isNotEmpty && ids.every(_selected.contains);
    setState(() {
      if (allSelected) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  Future<void> _pickRange(List<WaffrTransaction> expenses) async {
    if (expenses.isEmpty) return;
    var oldest = expenses.first.dateTime.toLocal();
    for (final expense in expenses) {
      final local = expense.dateTime.toLocal();
      if (local.isBefore(oldest)) oldest = local;
    }
    final now = DateTime.now();
    final firstDate = DateTime(oldest.year, oldest.month, oldest.day);
    final lastDate = DateTime(now.year, now.month, now.day);
    final range = await showWaffrDateRangePicker(
      context: context,
      title: 'نطاق التاريخ',
      firstDate: firstDate,
      lastDate: lastDate.isBefore(firstDate) ? firstDate : lastDate,
    );
    if (!mounted || range == null) return;
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final matched = <String>{
      for (final expense in expenses)
        if (_dayOf(expense.dateTime).isBefore(start) == false &&
            _dayOf(expense.dateTime).isAfter(end) == false)
          expense.id,
    };
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addAll(matched);
    });
  }

  Future<void> _confirmShare(List<WaffrTransaction> expenses) async {
    final chosen = expenses.where((item) => _selected.contains(item.id)).toList();
    if (chosen.isEmpty || _sharing) return;
    final format = await showAppDialog<_ExpenseShareFormat>(
      context: context,
      builder: (context) => const _ShareFormatDialog(),
    );
    if (format == null || !mounted) return;
    setState(() => _sharing = true);
    try {
      if (format == _ExpenseShareFormat.pdf) {
        await shareExpenseHistoryPdf(chosen);
      } else {
        await shareExpenseHistoryText(chosen);
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'تعذّر مشاركة السجل.');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final isIncome = widget.isIncome;
    final title = isIncome ? 'سجل الدخل' : 'سجل المصروفات';
    final summaryLabel = isIncome ? 'كل الدخل' : 'كل المصروفات';
    final emptyMessage = isIncome
        ? 'لا يوجد دخل مسجّل بعد'
        : 'لا يوجد مصروف مسجّل بعد';
    final summaryIcon = isIncome
        ? Icons.payments_outlined
        : Icons.receipt_long_outlined;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: WaffrBackHeader(
        title: title,
      ),
      floatingActionButton: isIncome
          ? null
          : AnimatedBuilder(
              animation: _listenables,
              builder: (context, _) {
                final liveIds = _store.expenses.map((item) => item.id).toSet();
                final selectedCount = _selected.where(liveIds.contains).length;
                final canShare = _selecting && selectedCount > 0 && !_sharing;
                return FloatingActionButton(
                  onPressed: _selecting
                      ? (canShare
                          ? () => _confirmShare(_store.expenses)
                          : null)
                      : () => _enterSelection(),
                  backgroundColor: canShare || !_selecting
                      ? colors.accent
                      : colors.accent.withValues(alpha: 0.35),
                  foregroundColor: colors.onAccent,
                  elevation: canShare || !_selecting ? 4 : 0,
                  child: const Icon(Icons.share_rounded),
                );
              },
            ),
      body: AnimatedBuilder(
        animation: _listenables,
        builder: (context, _) {
          final items = isIncome ? _store.incomes : _store.expenses;
          final groups = _groupExpensesByDay(items);
          final liveIds = items.map((item) => item.id).toSet();
          final selectedCount = _selected.where(liveIds.contains).length;
          final allSelected =
              items.isNotEmpty && items.every((item) => _selected.contains(item.id));
          return Column(
            children: [
              if (!isIncome)
                ClipRect(
                  child: SizeTransition(
                    sizeFactor: _selectionReveal,
                    alignment: Alignment.topCenter,
                    child: FadeTransition(
                      opacity: _selectionReveal,
                      child: _SelectionBar(
                        count: selectedCount,
                        allSelected: allSelected,
                        onClose: _exitSelection,
                        onToggleAll: () => _toggleAll(items),
                        onPickRange: () => _pickRange(items),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: GlassContainer(
                  colorType: GlassColorType.surface,
                  borderRadius: 24,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summaryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                            Text(
                              '${formatMoney(_sumExpenses(items))} '
                              '$currencyLabel',
                              style: TextStyle(
                                fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: colors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(summaryIcon, color: colors.accent),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: _EmptyState(
                          icon: summaryIcon,
                          message: emptyMessage,
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          18,
                          0,
                          18,
                          isIncome ? 28 : 96,
                        ),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final row = AnimatedBuilder(
                            animation: _selectionReveal,
                            builder: (context, _) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _HistoryDayGroup(
                              date: group.date,
                              expenses: group.expenses,
                              isIncome: isIncome,
                              selecting: !isIncome && _selectionReveal.value > 0,
                              reveal: _selectionReveal.value,
                              selectedIds: _selected,
                              onToggleDay: () => _toggleDay(group.expenses),
                              onLongPressDay: () {
                                if (_selecting) {
                                  _toggleDay(group.expenses);
                                } else {
                                  _enterSelection(
                                    selected: group.expenses
                                        .map((item) => item.id)
                                        .toSet(),
                                  );
                                }
                              },
                              onToggleExpense: _toggleExpense,
                              onLongPressExpense: (expense) {
                                if (_selecting) {
                                  _toggleExpense(expense.id);
                                } else {
                                  _enterSelection(selected: {expense.id});
                                }
                              },
                            ),
                          );
                            },
                          );
                          // Only the first screenful animates in.
                          return index < 6
                              ? Reveal(index: index, child: row)
                              : row;
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

DateTime _dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

enum _ExpenseShareFormat { pdf, text }

class _ShareFormatDialog extends StatelessWidget {
  const _ShareFormatDialog();

  @override
  Widget build(BuildContext context) {
    return AppDialogFrame(
      title: 'مشاركة السجل',
      message: 'اختر طريقة تصدير المصروفات المحددة.',
      kind: AppFeedbackKind.info,
      child: Row(
        children: [
          Expanded(
            child: _FormatChoice(
              label: 'PDF',
              icon: Icons.picture_as_pdf_outlined,
              onTap: () => Navigator.pop(context, _ExpenseShareFormat.pdf),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FormatChoice(
              label: 'نص',
              icon: Icons.notes_rounded,
              onTap: () => Navigator.pop(context, _ExpenseShareFormat.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FormatChoice({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return GlassButton(
      onTap: onTap,
      colorType: GlassColorType.surface,
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.accent),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleAll;
  final VoidCallback onPickRange;

  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.onClose,
    required this.onToggleAll,
    required this.onPickRange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'إلغاء',
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: colors.textPrimary),
            ),
            _SelectMark(
              state: allSelected ? _SelectState.checked : _SelectState.empty,
              onTap: onToggleAll,
            ),
            const SizedBox(width: 10),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'نطاق التاريخ',
              onPressed: onPickRange,
              icon: Icon(
                Icons.calendar_month_outlined,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SelectState { empty, partial, checked }

class _SelectMark extends StatelessWidget {
  final _SelectState state;
  final VoidCallback onTap;

  const _SelectMark({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final checked = state == _SelectState.checked;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? colors.accent : Colors.transparent,
          border: Border.all(
            color: checked ? colors.accent : colors.textSecondary,
            width: 1.6,
          ),
        ),
        child: state == _SelectState.checked
            ? Icon(Icons.check_rounded, size: 14, color: colors.onAccent)
            : state == _SelectState.partial
                ? Container(
                    width: 10,
                    height: 2,
                    color: colors.accent,
                  )
                : null,
      ),
    );
  }
}

// Transactions that share the same calendar day for the history list.
class _ExpenseDayGroup {
  final DateTime date;
  final List<WaffrTransaction> expenses;

  const _ExpenseDayGroup(this.date, this.expenses);
}

// Confirms, deletes the expense, refunds balance, and undoes linked shopping purchases.
Future<void> _undoExpense(BuildContext context, WaffrTransaction expense) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'التراجع عن المصروف',
    message:
        'سيُحذف هذا المصروف من السجل ويُعاد ${formatMoney(expense.amount)} ${currencyLabelFor(expense.currencyCode)} إلى رصيدك.',
    confirmLabel: 'تراجع',
    kind: AppFeedbackKind.warning,
  );

  if (confirmed != true || !context.mounted) return;

  final undone = await TransactionStore.instance.undoExpense(expense.id);
  if (!context.mounted) return;

  if (!undone) {
    showAppSnackBar(context, 'تعذّر التراجع عن هذا المصروف.');
    return;
  }

  await ShoppingListStore.instance.revertPurchaseForExpense(expense.id);
  if (!context.mounted) return;
  showAppSnackBar(context, 'تم التراجع عن المصروف', success: true);
}

// Confirms, deletes the income entry, and subtracts it from the running balance.
Future<void> _undoIncome(BuildContext context, WaffrTransaction income) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'التراجع عن الدخل',
    message:
        'سيُحذف هذا الدخل من السجل ويُخصم ${formatMoney(income.amount)} ${currencyLabelFor(income.currencyCode)} من رصيدك.',
    confirmLabel: 'تراجع',
    kind: AppFeedbackKind.warning,
  );

  if (confirmed != true || !context.mounted) return;

  final undone = await TransactionStore.instance.undoIncome(income.id);
  if (!context.mounted) return;

  if (!undone) {
    showAppSnackBar(context, 'تعذّر التراجع عن هذا الدخل.');
    return;
  }

  showAppSnackBar(context, 'تم التراجع عن الدخل', success: true);
}

// Date header plus a glass card listing that day's transactions.
class _HistoryDayGroup extends StatelessWidget {
  final DateTime date;
  final List<WaffrTransaction> expenses;
  final bool isIncome;
  final bool selecting;
  final double reveal;
  final Set<String> selectedIds;
  final VoidCallback? onToggleDay;
  final VoidCallback? onLongPressDay;
  final ValueChanged<String>? onToggleExpense;
  final ValueChanged<WaffrTransaction>? onLongPressExpense;

  const _HistoryDayGroup({
    required this.date,
    required this.expenses,
    this.isIncome = false,
    this.selecting = false,
    this.reveal = 1,
    this.selectedIds = const <String>{},
    this.onToggleDay,
    this.onLongPressDay,
    this.onToggleExpense,
    this.onLongPressExpense,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final selectedCount =
        expenses.where((item) => selectedIds.contains(item.id)).length;
    final dayState = selectedCount == 0
        ? _SelectState.empty
        : selectedCount == expenses.length
            ? _SelectState.checked
            : _SelectState.partial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onLongPress: onLongPressDay,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 7, bottom: 7),
            child: Row(
              children: [
                if (selecting) ...[
                  Opacity(
                    opacity: reveal,
                    child: _SelectMark(
                      state: dayState,
                      onTap: reveal > 0.99 ? (onToggleDay ?? () {}) : () {},
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _historyDateLabel(date),
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        GlassContainer(
          colorType: GlassColorType.surface,
          borderRadius: 25,
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: Column(
            children: [
              for (var index = 0; index < expenses.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 22,
                    color: colors.textPrimary.withValues(alpha: 0.08),
                  ),
                _HistoryExpenseRow(
                  expense: expenses[index],
                  isIncome: isIncome,
                  selecting: selecting,
                  reveal: reveal,
                  selected: selectedIds.contains(expenses[index].id),
                  onToggle: () => onToggleExpense?.call(expenses[index].id),
                  onLongPress: () => onLongPressExpense?.call(expenses[index]),
                  onUndo: selecting
                      ? null
                      : () => isIncome
                          ? _undoIncome(context, expenses[index])
                          : _undoExpense(context, expenses[index]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// Single history row: category/note, timestamp, amount, optional undo.
class _HistoryExpenseRow extends StatelessWidget {
  final WaffrTransaction expense;
  final bool isIncome;
  final bool selecting;
  final double reveal;
  final bool selected;
  final VoidCallback? onUndo;
  final VoidCallback? onToggle;
  final VoidCallback? onLongPress;

  const _HistoryExpenseRow({
    required this.expense,
    this.isIncome = false,
    this.selecting = false,
    this.reveal = 1,
    this.selected = false,
    this.onUndo,
    this.onToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final category = categoryFor(expense.category);
    final note = expense.note?.trim();
    final recurring =
        !isIncome && RecurringExpense.isRecurringSource(expense.sourceId);
    final schedule = recurring ? _recurringSchedule(expense) : null;
    final title = isIncome
        ? (note != null && note.isNotEmpty
            ? note
            : _incomeFrequencyLabel(expense.frequency))
        : category.label;
    // A schedule without a note stored its "every N" text as the note; the
    // recurring badge already shows it.
    final noteIsSchedule = recurring &&
        note != null &&
        (note == schedule || _looksLikeSchedule(note));
    final subtitle = isIncome && note != null && note.isNotEmpty
        ? _incomeFrequencyLabel(expense.frequency)
        : (!isIncome && !noteIsSchedule ? note : null);
    final icon = isIncome ? Icons.payments_outlined : category.icon;
    return GestureDetector(
      onLongPress: onLongPress,
      onTap: selecting ? onToggle : null,
      behavior: HitTestBehavior.opaque,
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selecting) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Opacity(
              opacity: reveal,
              child: _SelectMark(
                state: selected ? _SelectState.checked : _SelectState.empty,
                onTap: reveal > 0.99 ? (onToggle ?? () {}) : () {},
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accent.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 21, color: colors.accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 12.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
              if (recurring) ...[
                const SizedBox(height: 4),
                _RecurringBadge(schedule: schedule ?? _scheduleFromNote(note)),
              ],
              const SizedBox(height: 2),
              Text(
                '${formatDate(expense.dateTime)} • '
                '${formatTime(expense.dateTime)}',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                  fontSize: 10.5,
                  color: colors.textSecondary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '${formatMoney(expense.amount)} $currencyLabel',
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colors.accent,
                ),
              ),
            ),
            if (onUndo != null)
              IconButton(
                tooltip: 'تراجع',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onUndo,
                icon: Icon(
                  Icons.undo_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ],
      ),
    );
  }
}

// "Recurring" pill on history rows posted by a schedule, with the schedule
// ("كل شهر") next to it when it is still known.
class _RecurringBadge extends StatelessWidget {
  final String? schedule;

  const _RecurringBadge({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final text = TextStyle(
      fontFamily: 'Outfit',
      fontFamilyFallback: const ['Tajawal'],
      fontSize: 10.5,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: colors.accent,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(7, 3, 8, 3),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.accent.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.autorenew_rounded, size: 12, color: colors.accent),
              const SizedBox(width: 4),
              Text('مصروف متكرر', style: text),
            ],
          ),
        ),
        if (schedule != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              schedule!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// "كل شهر" for the schedule that posted [expense], if it still exists.
String? _recurringSchedule(WaffrTransaction expense) {
  final id = RecurringExpense.idFromSource(expense.sourceId);
  if (id == null) return null;
  return RecurringExpenseStore.instance.byId(id)?.intervalDescription;
}

final RegExp _schedulePattern = RegExp(
  r'^كل (\d+ )?(يوم|أسبوع|شهر|أيام|أسابيع|أشهر)$',
);

bool _looksLikeSchedule(String text) => _schedulePattern.hasMatch(text);

// Deleted schedules: the note may still hold the "every N" text.
String? _scheduleFromNote(String? note) {
  if (note == null || !_looksLikeSchedule(note)) return null;
  return note;
}

// Centered icon + message used when a chart or list has nothing to show.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(child: AppEmptyState(icon: icon, title: message));
  }
}

// Builds the [start, end) window for a range at the given PageView offset (0 = current).
_ReportPeriod _periodFor(_ReportRange range, int offset) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  late DateTime start;
  late DateTime end;

  switch (range) {
    case _ReportRange.day:
      start = today.subtract(Duration(days: offset));
      end = start.add(const Duration(days: 1));
    case _ReportRange.week:
      final daysFromSaturday = (today.weekday + 1) % 7;
      final currentWeekStart = today.subtract(
        Duration(days: daysFromSaturday),
      );
      start = currentWeekStart.subtract(Duration(days: offset * 7));
      end = start.add(const Duration(days: 7));
    case _ReportRange.month:
      start = DateTime(now.year, now.month - offset);
      end = DateTime(start.year, start.month + 1);
    case _ReportRange.threeMonths:
      final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      start = DateTime(now.year, quarterStartMonth - offset * 3);
      end = DateTime(start.year, start.month + 3);
    case _ReportRange.sixMonths:
      final halfStartMonth = now.month <= 6 ? 1 : 7;
      start = DateTime(now.year, halfStartMonth - offset * 6);
      end = DateTime(start.year, start.month + 6);
    case _ReportRange.year:
      start = DateTime(now.year - offset);
      end = DateTime(start.year + 1);
  }
  return _ReportPeriod(start: start, end: end, range: range);
}

List<WaffrTransaction> _expensesInPeriod(
  List<WaffrTransaction> expenses,
  _ReportPeriod period,
) {
  return expenses
      .where(
        (expense) =>
            !expense.dateTime.isBefore(period.start) &&
            expense.dateTime.isBefore(period.end),
      )
      .toList(growable: false);
}

double _sumExpenses(List<WaffrTransaction> expenses) {
  return expenses.fold<double>(0, (sum, expense) => sum + expense.amount);
}

// Creates empty buckets for the range grain, then fills amounts from expenses.
List<_ChartBucket> _buildChartBuckets(
  List<WaffrTransaction> expenses,
  _ReportPeriod period,
) {
  late final List<_ChartBucket> buckets;

  switch (period.range) {
    case _ReportRange.day:
      buckets = List.generate(24, (hour) {
        final hourLabel = hour.toString().padLeft(2, '0');
        return _ChartBucket(
          label: '$hourLabel:00',
          axisLabel: hour % 3 == 0 ? hourLabel : '',
          amount: 0,
        );
      });
    case _ReportRange.week:
      const dayLabels = [
        'سبت',
        'أحد',
        'اثنين',
        'ثلاثاء',
        'أربعاء',
        'خميس',
        'جمعة',
      ];
      buckets = List.generate(
        7,
        (index) => _ChartBucket(
          label: dayLabels[index],
          axisLabel: dayLabels[index],
          amount: 0,
        ),
      );
    case _ReportRange.month:
      final days = period.end.difference(period.start).inDays;
      final axisDays = {1, 8, 15, 22, days};
      buckets = List.generate(days, (index) {
        final day = index + 1;
        final date = period.start.add(Duration(days: index));
        return _ChartBucket(
          label: '$day ${_shortMonthName(date.month)}',
          axisLabel: axisDays.contains(day) ? '$day' : '',
          amount: 0,
        );
      });
    case _ReportRange.threeMonths:
      final days = period.end.difference(period.start).inDays;
      final count = (days / 7).ceil();
      buckets = List.generate(count, (index) {
        final date = period.start.add(Duration(days: index * 7));
        final month = _shortMonthName(date.month);
        final previous = index == 0
            ? null
            : period.start.add(Duration(days: (index - 1) * 7));
        final isNewMonth = previous == null || previous.month != date.month;
        return _ChartBucket(
          label: '${date.day} $month',
          axisLabel: isNewMonth ? month : '',
          amount: 0,
        );
      });
    case _ReportRange.sixMonths:
      buckets = List.generate(6, (index) {
        final date = DateTime(period.start.year, period.start.month + index);
        final month = _shortMonthName(date.month);
        return _ChartBucket(label: month, axisLabel: month, amount: 0);
      });
    case _ReportRange.year:
      buckets = List.generate(12, (index) {
        final date = DateTime(period.start.year, period.start.month + index);
        final month = _shortMonthName(date.month);
        final show = index == 0 || index == 11 || (index % 2 == 0 && index != 10);
        return _ChartBucket(
          label: month,
          axisLabel: show ? month : '',
          amount: 0,
        );
      });
  }

  final amounts = List<double>.filled(buckets.length, 0);
  for (final expense in expenses) {
    final local = expense.dateTime.toLocal();
    late int index;
    switch (period.range) {
      case _ReportRange.day:
        index = local.hour;
      case _ReportRange.week:
      case _ReportRange.month:
        index = DateTime(
          local.year,
          local.month,
          local.day,
        ).difference(period.start).inDays;
      case _ReportRange.threeMonths:
        index =
            DateTime(
              local.year,
              local.month,
              local.day,
            ).difference(period.start).inDays ~/
            7;
      case _ReportRange.sixMonths:
      case _ReportRange.year:
        index =
            (local.year - period.start.year) * 12 +
            local.month -
            period.start.month;
    }
    if (index >= 0 && index < amounts.length) {
      amounts[index] += expense.amount;
    }
  }

  return List.generate(
    buckets.length,
    (index) => _ChartBucket(
      label: buckets[index].label,
      axisLabel: buckets[index].axisLabel,
      amount: amounts[index],
    ),
  );
}

List<_ExpenseDayGroup> _groupExpensesByDay(List<WaffrTransaction> expenses) {
  final grouped = <DateTime, List<WaffrTransaction>>{};
  for (final expense in expenses) {
    final local = expense.dateTime.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    grouped.putIfAbsent(date, () => []).add(expense);
  }
  return grouped.entries
      .map((entry) => _ExpenseDayGroup(entry.key, entry.value))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
}

String _incomeFrequencyLabel(RecurringFrequency frequency) {
  return switch (frequency) {
    RecurringFrequency.weekly => 'دخل أسبوعي',
    RecurringFrequency.monthly => 'دخل شهري',
    RecurringFrequency.none => 'دخل',
  };
}

String _historyDateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(date).inDays;
  if (difference == 0) return 'اليوم';
  if (difference == 1) return 'أمس';
  if (date.year == today.year) {
    return '${date.day} ${_monthName(date.month)}';
  }
  return '${date.day} ${_monthName(date.month)} ${date.year}';
}

// Round Y-axis step (1/2/5×10^n) so grid labels stay readable.
double _niceInterval(double maxValue) {
  if (maxValue <= 3) return 1;
  final rough = maxValue / 3;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor());
  final normalized = rough / magnitude;
  final nice = normalized <= 1
      ? 1
      : normalized <= 2
      ? 2
      : normalized <= 5
      ? 5
      : 10;
  return (nice * magnitude).toDouble();
}

String _axisMoney(double value) {
  if (value <= 0) return '0';
  if (value >= 1000000) {
    final amount = value / 1000000;
    final text = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(1);
    return '$text مليون';
  }
  if (value >= 1000) {
    final amount = value / 1000;
    final text = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(1);
    return '$text ألف';
  }
  return formatMoney(value);
}

String _monthName(int month) => const [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
][month - 1];

String _shortMonthName(int month) => const [
  'كانون 2',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين 1',
  'تشرين 2',
  'كانون 1',
][month - 1];
