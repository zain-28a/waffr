import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:waffer/core/data/category_store.dart';
import 'package:waffer/core/data/expense_categories.dart';
import 'package:waffer/core/data/transaction.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _maxPeriodOffset = 240;

  final TransactionStore _store = TransactionStore.instance;
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
        builder: (_) => const _ExpenseHistoryScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_store, CategoryStore.instance]),
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
              _TimeRangeSelector(selected: _range, onSelected: _selectRange),
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

enum _ReportRange { week, month, threeMonths, sixMonths, year }

extension on _ReportRange {
  String get label => switch (this) {
    _ReportRange.week => 'أسبوع',
    _ReportRange.month => 'شهر',
    _ReportRange.threeMonths => '3 أشهر',
    _ReportRange.sixMonths => '6 أشهر',
    _ReportRange.year => 'سنة',
  };
}

class _ReportPeriod {
  final DateTime start;
  final DateTime end;
  final _ReportRange range;

  const _ReportPeriod({
    required this.start,
    required this.end,
    required this.range,
  });

  String get label {
    final lastDay = end.subtract(const Duration(days: 1));
    switch (range) {
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

class _CategoryTotal {
  final String category;
  final double amount;

  const _CategoryTotal(this.category, this.amount);
}

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

class _TimeRangeSelector extends StatelessWidget {
  final _ReportRange selected;
  final ValueChanged<_ReportRange> onSelected;

  const _TimeRangeSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
    final ranges = _ReportRange.values;
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
                                  fontFamily: 'Tajawal',
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
    final colors = _ReportColors.of(context);
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
                        fontFamily: 'Tajawal',
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
                          fontFamily: 'Tajawal',
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
    final colors = _ReportColors.of(context);
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

class _SpendingLineChart extends StatelessWidget {
  final List<_ChartBucket> buckets;

  const _SpendingLineChart({super.key, required this.buckets});

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
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
                      fontFamily: 'Tajawal',
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
                      fontFamily: 'Tajawal',
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
                    fontFamily: 'Tajawal',
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

class _SpendingSummary extends StatelessWidget {
  final double total;
  final VoidCallback onHistory;

  const _SpendingSummary({required this.total, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
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
                    fontFamily: 'Tajawal',
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
                            fontFamily: 'Tajawal',
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
                        fontFamily: 'Tajawal',
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
                      fontFamily: 'Tajawal',
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

class _ExpenseDistribution extends StatelessWidget {
  final _ReportData report;

  const _ExpenseDistribution({required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
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
                  fontFamily: 'Tajawal',
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
                    fontFamily: 'Tajawal',
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

class _CategoryRow extends StatelessWidget {
  final _CategoryTotal item;
  final double total;

  const _CategoryRow({required this.item, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
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
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
        Text(
          '${percentage.round()}%',
          style: TextStyle(
            fontFamily: 'Tajawal',
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
                fontFamily: 'Tajawal',
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

class _ImprovementCard extends StatelessWidget {
  final double currentTotal;
  final double previousTotal;

  const _ImprovementCard({
    required this.currentTotal,
    required this.previousTotal,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
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
                    fontFamily: 'Tajawal',
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
                          fontFamily: 'Tajawal',
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
                    fontFamily: 'Tajawal',
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
                    fontFamily: 'Tajawal',
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

enum _ImprovementKind { positive, negative, neutral }

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

class _ExpenseHistoryScreen extends StatefulWidget {
  const _ExpenseHistoryScreen();

  @override
  State<_ExpenseHistoryScreen> createState() => _ExpenseHistoryScreenState();
}

class _ExpenseHistoryScreenState extends State<_ExpenseHistoryScreen> {
  final TransactionStore _store = TransactionStore.instance;

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colors.background.withValues(alpha: 0),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          'سجل المصاريف',
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([_store, CategoryStore.instance]),
        builder: (context, _) {
          final expenses = _store.expenses;
          final groups = _groupExpensesByDay(expenses);
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
                              'كل المصاريف',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                            Text(
                              '${formatMoney(_sumExpenses(expenses))} '
                              '$currencyLabel',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: colors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.receipt_long_outlined, color: colors.accent),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: expenses.isEmpty
                    ? const Center(
                        child: _EmptyState(
                          icon: Icons.receipt_long_outlined,
                          message: 'لا يوجد مصروف مسجّل بعد',
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

class _ExpenseDayGroup {
  final DateTime date;
  final List<WafferTransaction> expenses;

  const _ExpenseDayGroup(this.date, this.expenses);
}

class _HistoryDayGroup extends StatelessWidget {
  final DateTime date;
  final List<WafferTransaction> expenses;

  const _HistoryDayGroup({required this.date, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 7, bottom: 7),
          child: Text(
            _historyDateLabel(date),
            style: TextStyle(
              fontFamily: 'Tajawal',
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
                _HistoryExpenseRow(expense: expenses[index]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryExpenseRow extends StatelessWidget {
  final WafferTransaction expense;

  const _HistoryExpenseRow({required this.expense});

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
    final category = categoryFor(expense.category);
    final note = expense.note?.trim();
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
          child: Icon(category.icon, size: 21, color: colors.accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
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
                  fontFamily: 'Tajawal',
                  fontSize: 10.5,
                  color: colors.textSecondary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${formatMoney(expense.amount)} $currencyLabel',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 14,
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = _ReportColors.of(context);
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
                fontFamily: 'Tajawal',
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

class _ReportColors {
  final Color background;
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const _ReportColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  factory _ReportColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _ReportColors(
      background: isDark ? AppColors.darkBackground : AppColors.lightBackground,
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

_ReportPeriod _periodFor(_ReportRange range, int offset) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  late DateTime start;
  late DateTime end;

  switch (range) {
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

List<_ChartBucket> _buildChartBuckets(
  List<WafferTransaction> expenses,
  _ReportPeriod period,
) {
  late final List<_ChartBucket> buckets;

  switch (period.range) {
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
    late int index;
    switch (period.range) {
      case _ReportRange.week:
      case _ReportRange.month:
        index = DateTime(
          expense.dateTime.year,
          expense.dateTime.month,
          expense.dateTime.day,
        ).difference(period.start).inDays;
      case _ReportRange.threeMonths:
        index =
            DateTime(
              expense.dateTime.year,
              expense.dateTime.month,
              expense.dateTime.day,
            ).difference(period.start).inDays ~/
            7;
      case _ReportRange.sixMonths:
      case _ReportRange.year:
        index =
            (expense.dateTime.year - period.start.year) * 12 +
            expense.dateTime.month -
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
    final date = DateTime(
      expense.dateTime.year,
      expense.dateTime.month,
      expense.dateTime.day,
    );
    grouped.putIfAbsent(date, () => []).add(expense);
  }
  return grouped.entries
      .map((entry) => _ExpenseDayGroup(entry.key, entry.value))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
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
