import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';

class MonthlySpendScreen extends StatefulWidget {
  final bool isActive;

  const MonthlySpendScreen({
    super.key,
    required this.isActive,
  });

  @override
  State<MonthlySpendScreen> createState() =>
      _MonthlySpendScreenState();
}

class _MonthlySpendScreenState extends State<MonthlySpendScreen> {
  static const _monthNames = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  List<_MonthSpend> _months = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMonthlySpend();
  }

  @override
  void didUpdateWidget(covariant MonthlySpendScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadMonthlySpend();
    }
  }

  Future<void> _loadMonthlySpend() async {
    final store = TransactionStore.instance;
    await store.ensureLoaded();

    final now = DateTime.now();

    final totals = <String, double>{};
    for (var i = 5; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      totals[_monthKey(date)] = 0;
    }

    for (final expense in store.expenses) {
      final date = expense.dateTime;
      final key = _monthKey(DateTime(date.year, date.month, 1));

      if (totals.containsKey(key)) {
        totals[key] = (totals[key] ?? 0) + expense.amount;
      }
    }

    final months = totals.entries.map((e) {
      final parts = e.key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      return _MonthSpend(
        year: year,
        month: month,
        amount: e.value,
        label: _monthNames[month - 1],
      );
    }).toList();

    if (!mounted) return;
    setState(() {
      _months = months;
      _loading = false;
    });
  }

  String _monthKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  double get _thisMonthTotal =>
      _months.isEmpty ? 0 : _months.last.amount;

  double get _maxAmount {
    final max = _months.fold<double>(
      0,
      (sum, item) => item.amount > sum ? item.amount : sum,
    );
    return max <= 0 ? 100 : max * 1.2;
  }

  String _formatNumber(double number) {
    final intValue = number.toInt();
    final str = intValue.toString();
    final buffer = StringBuffer();

    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    final cardDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      color: isDark
          ? AppColors.darkSurface
          : const Color.fromARGB(153, 255, 253, 249),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 40,
          offset: const Offset(0, -3),
        ),
      ],
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الإنفاق الشهري',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'رسم يوضح مجموع ما صرفته في كل شهر خلال الأشهر الستة الماضية.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  height: 1.5,
                  color: textPrimary.withValues(alpha: 0.55),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 22,
              ),
              decoration: cardDecoration,
              child: Column(
                children: [
                  Text(
                    'هذا الشهر',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatNumber(_thisMonthTotal),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              height: 320,
              padding: const EdgeInsets.fromLTRB(12, 22, 18, 12),
              decoration: cardDecoration,
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : _months.every((m) => m.amount == 0)
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bar_chart_rounded,
                              size: 46,
                              color: textPrimary.withValues(alpha: 0.35),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'لا يوجد إنفاق مسجّل بعد',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                color: textPrimary.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        )
                      : Directionality(
                          textDirection: TextDirection.ltr,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _maxAmount,
                              barTouchData: BarTouchData(
                                enabled: true,
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipColor: (_) =>
                                      isDark
                                          ? AppColors.darkSurface
                                          : AppColors.lightSurface,
                                  getTooltipItem:
                                      (group, groupIndex, rod, rodIndex) {
                                    final month = _months[group.x.toInt()];
                                    return BarTooltipItem(
                                      '${month.label}\n${_formatNumber(month.amount)}',
                                      TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    );
                                  },
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
                                    reservedSize: 42,
                                    getTitlesWidget: (value, meta) {
                                      if (value == 0 || value == meta.max) {
                                        return const SizedBox.shrink();
                                      }
                                      return Text(
                                        _formatNumber(value),
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          color: textPrimary.withValues(alpha: 0.45),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 32,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.toInt();
                                      if (index < 0 || index >= _months.length) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          _months[index].label,
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10,
                                            color: textPrimary.withValues(alpha: 0.7),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (value) {
                                  return FlLine(
                                    color: textPrimary.withValues(alpha: 0.06),
                                    strokeWidth: 1,
                                  );
                                },
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: List.generate(_months.length, (index) {
                                return BarChartGroupData(
                                  x: index,
                                  barRods: [
                                    BarChartRodData(
                                      toY: _months[index].amount,
                                      width: 18,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(8),
                                      ),
                                      color: accent,
                                      backDrawRodData: BackgroundBarChartRodData(
                                        show: true,
                                        toY: _maxAmount,
                                        color: accent.withValues(alpha: 0.08),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _MonthSpend {
  final int year;
  final int month;
  final double amount;
  final String label;

  const _MonthSpend({
    required this.year,
    required this.month,
    required this.amount,
    required this.label,
  });
}
