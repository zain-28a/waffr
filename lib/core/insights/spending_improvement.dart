// Same spending comparison Reports uses: down is an improvement, up is not.

/// Direction of a spending change, from the user's point of view.
enum SpendingChange {
  /// Spending went down.
  positive,

  /// Spending went up.
  negative,

  /// No change, or nothing to compare.
  neutral,
}

/// A period's spending compared with the previous period.
class SpendingImprovement {
  /// Whether the change is good, bad or neutral.
  final SpendingChange kind;

  /// The badge text ("+12.5%", "−3.0%", "0%").
  final String text;

  /// One Arabic sentence explaining the badge.
  final String detail;

  /// Always true now: the badge always shows a percentage against the
  /// previous period. Kept for callers that branch on it.
  final bool hasPercentage;

  /// A comparison result.
  const SpendingImprovement(
    this.kind,
    this.text,
    this.detail,
    this.hasPercentage,
  );

  /// Compares [currentTotal] with [previousTotal]. A drop is shown as a
  /// positive percentage because spending less is the improvement.
  factory SpendingImprovement.calculate({
    required double currentTotal,
    required double previousTotal,
  }) {
    // Nothing spent before: there is no base for a ratio, so the change is
    // shown at its bound (no change, or a full rise) and the sentence says why.
    if (previousTotal <= 0) {
      if (currentTotal <= 0) {
        return const SpendingImprovement(
          SpendingChange.neutral,
          '0%',
          'لا توجد مصروفات في الفترتين',
          true,
        );
      }
      return const SpendingImprovement(
        SpendingChange.negative,
        '−100.0%',
        'لا توجد مصروفات في الفترة السابقة',
        true,
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
