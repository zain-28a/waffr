// Offline spending report: range chips, a swipeable period chart (fl_chart),
// total spent, category distribution, and a comparison with the previous period.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:waffer/data/stores/category_store.dart';
import 'package:waffer/data/models/expense_categories.dart';
import 'package:waffer/data/models/transaction.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/theme/app_palette.dart';
import 'package:waffer/data/stores/shopping_list_store.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

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
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetChoiceChips(
                options: [for (final range in _ReportRange.values) range.label],
                selected: _range.label,
                onSelected: (label) {
                  _selectRange(
                    _ReportRange.values.firstWhere((range) => range.label == label),
                  );
                },
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: chartHeight,
                child: PageView.builder(
                  controller: _periodController,
                  itemCount: _maxPeriodOffset,
                  clipBehavior: Clip.none,
                  onPageChanged: (index) {
                    setState(() => _periodOffset = index);
                  },
                  itemBuilder: (context, offset) {
                    final pageReport = _ReportData.from(
                      expenses,
                      _periodFor(_range, offset),
                    );
                    return _SpendingChartCard(
                      report: pageReport,
                      canShowNewer: offset > 0,
                      onOlder: _showOlderPeriod,
                      onNewer: _showNewerPeriod,
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
              _ExpenseDistribution(report: report),
              const SizedBox(height: 6),
              _ImprovementCard(
                currentTotal: report.total,
                previousTotal: previousTotal,
              ),
            ],
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
  final List<WafferTransaction> expenses;
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
    List<WafferTransaction> allExpenses,
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
                        fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        report.period.label,
                        key: ValueKey(report.period.start),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                    message: 'لا توجد مصاريف في هذه الفترة',
                  )
                : Directionality(
                    textDirection: TextDirection.ltr,
                    child: _SpendingLineChart(
                      key: ValueKey(report.period.start),
                      buckets: report.chartBuckets,
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

  const _SpendingLineChart({super.key, required this.buckets});

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
                      fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                      fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                    fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
      duration: const Duration(milliseconds: 280),
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
                    fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                        child: Text(
                          formatMoney(total),
                          style: TextStyle(
                            fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                        fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                    'سجل المصاريف',
                    style: TextStyle(
                      fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                  fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '<النسبة من إجمالي الصرف وليس الرصيد>',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                  duration: const Duration(milliseconds: 350),
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
              fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
        Text(
          '${percentage.round()}%',
          style: TextStyle(
            fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
    final comparison = _ImprovementComparison.calculate(
      currentTotal: currentTotal,
      previousTotal: previousTotal,
    );
    final valueColor = switch (comparison.kind) {
      _ImprovementKind.positive => colors.accent,
      _ImprovementKind.negative => colors.textPrimary,
      _ImprovementKind.neutral => colors.textSecondary,
    };
    final icon = switch (comparison.kind) {
      _ImprovementKind.positive => Icons.trending_up_rounded,
      _ImprovementKind.negative => Icons.trending_down_rounded,
      _ImprovementKind.neutral => Icons.remove_rounded,
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
                    fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                          fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                    fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          GlassButton(
            onTap: () {},
            colorType: GlassColorType.background,
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_graph_rounded, size: 17, color: colors.accent),
                const SizedBox(width: 6),
                Text(
                  "بس اعمل الai",
                  style: TextStyle(
                    fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Whether spending fell, rose, or stayed flat vs the previous period.
enum _ImprovementKind { positive, negative, neutral }

// Percent change text and tone: spending down is positive, up is negative.
class _ImprovementComparison {
  final _ImprovementKind kind;
  final String text;
  final String detail;
  final bool hasPercentage;

  const _ImprovementComparison(
    this.kind,
    this.text,
    this.detail,
    this.hasPercentage,
  );

  factory _ImprovementComparison.calculate({
    required double currentTotal,
    required double previousTotal,
  }) {
    if (previousTotal <= 0) {
      if (currentTotal <= 0) {
        return const _ImprovementComparison(
          _ImprovementKind.neutral,
          '—',
          'لا توجد بيانات للمقارنة',
          false,
        );
      }
      return const _ImprovementComparison(
        _ImprovementKind.neutral,
        '—',
        'لا توجد مصاريف في الفترة السابقة',
        false,
      );
    }
    final percentage = (previousTotal - currentTotal) / previousTotal * 100;
    if (percentage > 0) {
      return _ImprovementComparison(
        _ImprovementKind.positive,
        '+${percentage.toStringAsFixed(1)}%',
        'المصروف انخفض مقارنة بالفترة السابقة',
        true,
      );
    }
    if (percentage < 0) {
      return _ImprovementComparison(
        _ImprovementKind.negative,
        '−${percentage.abs().toStringAsFixed(1)}%',
        'المصروف ارتفع مقارنة بالفترة السابقة',
        true,
      );
    }
    return const _ImprovementComparison(
      _ImprovementKind.neutral,
      '0%',
      'لا تغيير في المصروف',
      true,
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

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final TransactionStore _store = TransactionStore.instance;
  late final Listenable _listenables = Listenable.merge([
    _store,
    CategoryStore.instance,
  ]);

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final isIncome = widget.isIncome;
    final title = isIncome ? 'سجل الدخل' : 'سجل المصاريف';
    final summaryLabel = isIncome ? 'كل الدخل' : 'كل المصاريف';
    final emptyMessage = isIncome
        ? 'لا يوجد دخل مسجّل بعد'
        : 'لا يوجد مصروف مسجّل بعد';
    final summaryIcon = isIncome
        ? Icons.payments_outlined
        : Icons.receipt_long_outlined;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: WafferPageHeader(
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_forward_ios_rounded,
            color: colors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: AnimatedBuilder(
        animation: _listenables,
        builder: (context, _) {
          final items = isIncome ? _store.incomes : _store.expenses;
          final groups = _groupExpensesByDay(items);
          return Column(
            children: [
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
                                fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                            Text(
                              '${formatMoney(_sumExpenses(items))} '
                              '$currencyLabel',
                              style: TextStyle(
                                fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _HistoryDayGroup(
                              date: group.date,
                              expenses: group.expenses,
                              isIncome: isIncome,
                            ),
                          );
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

// Transactions that share the same calendar day for the history list.
class _ExpenseDayGroup {
  final DateTime date;
  final List<WafferTransaction> expenses;

  const _ExpenseDayGroup(this.date, this.expenses);
}

// Confirms, deletes the expense, refunds balance, and undoes linked shopping purchases.
Future<void> _undoExpense(BuildContext context, WafferTransaction expense) async {
  final colors = AppPalette.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Text(
          'التراجع عن المصروف',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          'سيُحذف هذا المصروف من السجل ويُعاد ${formatMoney(expense.amount)} ${currencyLabelFor(expense.currencyCode)} إلى رصيدك.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
            fontSize: 14,
            color: colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'إلغاء',
              style: TextStyle(fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'], color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'تراجع',
              style: TextStyle(fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'], color: colors.accent),
            ),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return;

  final undone = await TransactionStore.instance.undoExpense(expense.id);
  if (!context.mounted) return;

  if (!undone) {
    showAppSnackBar(context, 'تعذر التراجع عن هذا المصروف.');
    return;
  }

  await ShoppingListStore.instance.revertPurchaseForExpense(expense.id);
  if (!context.mounted) return;
  showAppSnackBar(context, 'تم التراجع عن المصروف', success: true);
}

// Confirms, deletes the income entry, and subtracts it from the running balance.
Future<void> _undoIncome(BuildContext context, WafferTransaction income) async {
  final colors = AppPalette.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Text(
          'التراجع عن الدخل',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          'سيُحذف هذا الدخل من السجل ويُخصم ${formatMoney(income.amount)} ${currencyLabelFor(income.currencyCode)} من رصيدك.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
            fontSize: 14,
            color: colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'إلغاء',
              style: TextStyle(fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'], color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'تراجع',
              style: TextStyle(fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'], color: colors.accent),
            ),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return;

  final undone = await TransactionStore.instance.undoIncome(income.id);
  if (!context.mounted) return;

  if (!undone) {
    showAppSnackBar(context, 'تعذر التراجع عن هذا الدخل.');
    return;
  }

  showAppSnackBar(context, 'تم التراجع عن الدخل', success: true);
}

// Date header plus a glass card listing that day's transactions.
class _HistoryDayGroup extends StatelessWidget {
  final DateTime date;
  final List<WafferTransaction> expenses;
  final bool isIncome;

  const _HistoryDayGroup({
    required this.date,
    required this.expenses,
    this.isIncome = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 7, bottom: 7),
          child: Text(
            _historyDateLabel(date),
            style: TextStyle(
              fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colors.textSecondary,
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
                  onUndo: () => isIncome
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
  final WafferTransaction expense;
  final bool isIncome;
  final VoidCallback? onUndo;

  const _HistoryExpenseRow({
    required this.expense,
    this.isIncome = false,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final category = categoryFor(expense.category);
    final note = expense.note?.trim();
    final title = isIncome
        ? (note != null && note.isNotEmpty
            ? note
            : _incomeFrequencyLabel(expense.frequency))
        : category.label;
    final subtitle = isIncome && note != null && note.isNotEmpty
        ? _incomeFrequencyLabel(expense.frequency)
        : (!isIncome ? note : null);
    final icon = isIncome ? Icons.payments_outlined : category.icon;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                    fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 12.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                '${formatDate(expense.dateTime)} • '
                '${formatTime(expense.dateTime)}',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
                  fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
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
    );
  }
}

// Centered icon + message used when a chart or list has nothing to show.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 36,
              color: colors.textPrimary.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'BebasNeue', fontFamilyFallback: const ['Tajawal'],
                fontSize: 13,
                color: colors.textPrimary.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
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

List<WafferTransaction> _expensesInPeriod(
  List<WafferTransaction> expenses,
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

double _sumExpenses(List<WafferTransaction> expenses) {
  return expenses.fold<double>(0, (sum, expense) => sum + expense.amount);
}

// Creates empty buckets for the range grain, then fills amounts from expenses.
List<_ChartBucket> _buildChartBuckets(
  List<WafferTransaction> expenses,
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

List<_ExpenseDayGroup> _groupExpensesByDay(List<WafferTransaction> expenses) {
  final grouped = <DateTime, List<WafferTransaction>>{};
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
