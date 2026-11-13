// Report data (part of reportscreen.dart): ranges, periods, chart buckets
// and the pure helpers that build them from expenses.

part of 'reportscreen.dart';

/// Bucket width for the chart and summary (day through year).
enum _ReportRange { day, week, month, threeMonths, sixMonths, year }

/// Labels and calendar mapping for [_ReportRange].
extension on _ReportRange {
  /// Chip label in the range selector.
  String get label => switch (this) {
    _ReportRange.day => 'اليوم',
    _ReportRange.week => 'أسبوع',
    _ReportRange.month => 'شهر',
    _ReportRange.threeMonths => '3 أشهر',
    _ReportRange.sixMonths => '6 أشهر',
    _ReportRange.year => 'سنة',
  };

  /// The matching calendar window; null for a single day.
  SavingsRange? get calendarRange => switch (this) {
    _ReportRange.day => null,
    _ReportRange.week => SavingsRange.week,
    _ReportRange.month => SavingsRange.month,
    _ReportRange.threeMonths => SavingsRange.threeMonths,
    _ReportRange.sixMonths => SavingsRange.sixMonths,
    _ReportRange.year => SavingsRange.year,
  };
}

/// Half-open [start, end) window for one page of the period PageView.
class _ReportPeriod {
  final DateTime start;
  final DateTime end;
  final _ReportRange range;

  const _ReportPeriod({
    required this.start,
    required this.end,
    required this.range,
  });

  /// Human-readable caption shown above the chart for this window.
  String get label {
    final calendarRange = range.calendarRange;
    if (calendarRange == null) {
      return '${start.day} ${CalendarPeriod.monthName(start.month)} ${start.year}';
    }
    return CalendarPeriod.rangeLabel(
      calendarRange,
      CalendarPeriod(start: start, end: end),
    );
  }
}

/// One category's share of spending in the selected period.
class _CategoryTotal {
  final String category;
  final double amount;

  const _CategoryTotal(this.category, this.amount);
}

/// One X-axis slot on the line chart (hour, day, week, or month depending on
/// range).
class _ChartBucket {
  // Full label for the tooltip.
  final String label;
  // Short axis label; empty to leave that tick unlabelled.
  final String axisLabel;
  final double amount;

  const _ChartBucket({
    required this.label,
    required this.axisLabel,
    required this.amount,
  });
}

/// Filters expenses for a period, sums by category, and buckets them into
/// chart points. With a [focus] category the total and the chart cover only
/// that category, while [categoryTotals] still lists them all.
class _ReportData {
  final _ReportPeriod period;

  /// The expenses behind [total] and the chart (one category when focused).
  final List<WaffrTransaction> expenses;

  /// Spending shown: the focused category, or everything.
  final double total;

  /// Spending in every category; shares are measured against it.
  final double allTotal;

  /// The focused category's label, or null for all categories.
  final String? focus;

  // Category totals, largest first.
  final List<_CategoryTotal> categoryTotals;
  final List<_ChartBucket> chartBuckets;

  /// Last bucket that has started; later ones are still in the future and
  /// are not drawn.
  final int lastBucket;

  const _ReportData({
    required this.period,
    required this.expenses,
    required this.total,
    required this.allTotal,
    required this.focus,
    required this.categoryTotals,
    required this.chartBuckets,
    required this.lastBucket,
  });

  /// Builds the report for [period] from the full expense list.
  factory _ReportData.from(
    List<WaffrTransaction> allExpenses,
    _ReportPeriod period, {
    String? focus,
    DateTime? now,
  }) {
    final inPeriod = _expensesInPeriod(allExpenses, period);
    final totals = <String, double>{};
    for (final expense in inPeriod) {
      final category = categoryFor(expense.category).label;
      totals[category] = (totals[category] ?? 0) + expense.amount;
    }
    final categoryTotals =
        totals.entries
            .map((entry) => _CategoryTotal(entry.key, entry.value))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    final shown = focus == null
        ? inPeriod
        : inPeriod
              .where((e) => categoryFor(e.category).label == focus)
              .toList(growable: false);
    final buckets = _buildChartBuckets(shown, period);

    return _ReportData(
      period: period,
      expenses: shown,
      total: _sumExpenses(shown),
      allTotal: _sumExpenses(inPeriod),
      focus: focus,
      categoryTotals: categoryTotals,
      chartBuckets: buckets,
      lastBucket: _lastStartedBucket(
        period,
        buckets.length,
        now ?? DateTime.now(),
      ),
    );
  }
}

/// The chart bucket [moment] falls in for [period]'s grain; may be outside
/// 0..count-1 when the moment is outside the period.
int _bucketIndex(_ReportPeriod period, DateTime moment) {
  final local = moment.toLocal();
  switch (period.range) {
    case _ReportRange.day:
      return local.hour;
    case _ReportRange.week:
    case _ReportRange.month:
      return calendarDaysBetween(period.start, local);
    case _ReportRange.threeMonths:
      return calendarDaysBetween(period.start, local) ~/ 7;
    case _ReportRange.sixMonths:
    case _ReportRange.year:
      return (local.year - period.start.year) * 12 +
          local.month -
          period.start.month;
  }
}

/// The last bucket that has started at [now]: the one holding [now] while
/// the period is running, otherwise the final bucket.
int _lastStartedBucket(_ReportPeriod period, int count, DateTime now) {
  if (count <= 0) return 0;
  if (now.isBefore(period.start) || !now.isBefore(period.end)) {
    return count - 1;
  }
  return _bucketIndex(period, now).clamp(0, count - 1);
}

/// Builds the [start, end) window for a range at the given PageView offset
/// (0 = current).
_ReportPeriod _periodFor(_ReportRange range, int offset) {
  final calendarRange = range.calendarRange;
  if (calendarRange == null) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = addCalendarDays(today, -offset);
    return _ReportPeriod(
      start: start,
      end: addCalendarDays(start, 1),
      range: range,
    );
  }
  final period = CalendarPeriod.forRange(calendarRange, offset);
  return _ReportPeriod(start: period.start, end: period.end, range: range);
}

/// Expenses whose time falls inside [period].
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

/// Sum of the expense amounts.
double _sumExpenses(List<WaffrTransaction> expenses) {
  return expenses.fold<double>(0, (sum, expense) => sum + expense.amount);
}

/// Creates empty buckets for the range grain, then fills amounts from
/// expenses.
List<_ChartBucket> _buildChartBuckets(
  List<WaffrTransaction> expenses,
  _ReportPeriod period,
) {
  late final List<_ChartBucket> buckets;

  // Empty buckets with labels for each range grain.
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
      final days = calendarDaysBetween(period.start, period.end);
      final axisDays = {1, 8, 15, 22, days};
      buckets = List.generate(days, (index) {
        final day = index + 1;
        final date = addCalendarDays(period.start, index);
        return _ChartBucket(
          label: '$day ${_shortMonthName(date.month)}',
          axisLabel: axisDays.contains(day) ? '$day' : '',
          amount: 0,
        );
      });
    case _ReportRange.threeMonths:
      final days = calendarDaysBetween(period.start, period.end);
      final count = (days / 7).ceil();
      buckets = List.generate(count, (index) {
        final date = addCalendarDays(period.start, index * 7);
        final month = _shortMonthName(date.month);
        final previous = index == 0
            ? null
            : addCalendarDays(period.start, (index - 1) * 7);
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
        final show =
            index == 0 || index == 11 || (index % 2 == 0 && index != 10);
        return _ChartBucket(
          label: month,
          axisLabel: show ? month : '',
          amount: 0,
        );
      });
  }

  // Drop each expense into its bucket by hour, day, week or month offset.
  final amounts = List<double>.filled(buckets.length, 0);
  for (final expense in expenses) {
    final index = _bucketIndex(period, expense.dateTime);
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

/// Round Y-axis step (1/2/5 x 10^n) so grid labels stay readable.
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

/// Short Y-axis money label, using thousand / million words for big values.
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

/// Short Levantine month name used on chart axes (1 = January).
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
