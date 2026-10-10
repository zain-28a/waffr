// Same spending comparison Reports uses: down is an improvement, up is not.

enum SpendingChange { positive, negative, neutral }

class SpendingImprovement {
  final SpendingChange kind;
  final String text;
  final String detail;
  final bool hasPercentage;

  const SpendingImprovement(
    this.kind,
    this.text,
    this.detail,
    this.hasPercentage,
  );

  factory SpendingImprovement.calculate({
    required double currentTotal,
    required double previousTotal,
  }) {
    if (previousTotal <= 0) {
      if (currentTotal <= 0) {
        return const SpendingImprovement(
          SpendingChange.neutral,
          '—',
          'لا توجد بيانات للمقارنة',
          false,
        );
      }
      return const SpendingImprovement(
        SpendingChange.neutral,
        '—',
        'لا توجد مصروفات في الفترة السابقة',
        false,
      );
    }
    final percentage = (previousTotal - currentTotal) / previousTotal * 100;
    if (percentage > 0) {
      return SpendingImprovement(
        SpendingChange.positive,
        '+${percentage.toStringAsFixed(1)}%',
        'المصروف انخفض مقارنة بالفترة السابقة',
        true,
      );
    }
    if (percentage < 0) {
      return SpendingImprovement(
        SpendingChange.negative,
        '−${percentage.abs().toStringAsFixed(1)}%',
        'المصروف ارتفع مقارنة بالفترة السابقة',
        true,
      );
    }
    return const SpendingImprovement(
      SpendingChange.neutral,
      '0%',
      'لا تغيير في المصروف',
      true,
    );
  }
}
