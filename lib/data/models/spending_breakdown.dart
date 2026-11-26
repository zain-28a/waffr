// Where the money went in one period: each category's total and share,
// ranked, with the largest category on top. Pure data for the home donut
// and anything else that names the top spending category.

import 'package:waffr/data/models/expense_categories.dart';

/// The spans the home spending card can show.
enum SpendingPeriod {
  /// Saturday to today.
  week,

  /// The 1st of the month to today.
  month,

  /// The current balance period (since the income that started it).
  cycle,

  /// Every expense ever recorded.
  all;

  /// Short Arabic label for the period chip.
  String get label => switch (this) {
    SpendingPeriod.week => 'الأسبوع',
    SpendingPeriod.month => 'الشهر',
    SpendingPeriod.cycle => 'الفترة',
    SpendingPeriod.all => 'الكل',
  };

  /// The period saved under [name], or [fallback] when unknown.
  static SpendingPeriod parse(String? name, {SpendingPeriod fallback = cycle}) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}

/// One category's slice of a [SpendingBreakdown].
class CategoryShare {
  /// Category label as stored on the expenses.
  final String category;

  /// Total spent in the category.
  final double amount;

  /// [amount] as a share of the breakdown's total, 0..1.
  final double share;

  /// A category slice.
  const CategoryShare({
    required this.category,
    required this.amount,
    required this.share,
  });
}

/// Category totals of one period, largest first.
class SpendingBreakdown {
  /// The slices, largest first; ties in the order described at [rank].
  final List<CategoryShare> items;

  /// Sum of every slice.
  final double total;

  const SpendingBreakdown._(this.items, this.total);

  /// A breakdown with nothing spent.
  static const SpendingBreakdown empty = SpendingBreakdown._([], 0);

  /// Ranks [totals] (category label -> amount). Zero and negative totals
  /// are left out.
  factory SpendingBreakdown.fromTotals(Map<String, double> totals) {
    final entries = [
      for (final entry in totals.entries)
        if (entry.value > 0) entry,
    ]..sort(rank);
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    if (total <= 0) return empty;
    return SpendingBreakdown._([
      for (final entry in entries)
        CategoryShare(
          category: entry.key,
          amount: entry.value,
          share: entry.value / total,
        ),
    ], total);
  }

  /// True when nothing was spent in the period.
  bool get isEmpty => items.isEmpty;

  /// The category with the most spending, or null when nothing was spent.
  CategoryShare? get top => items.isEmpty ? null : items.first;

  /// Orders category totals: larger amounts first. Equal amounts follow the
  /// built-in grid order, then custom categories by label, and «أخرى» last,
  /// so a tie always resolves the same way.
  static int rank(MapEntry<String, double> a, MapEntry<String, double> b) {
    final byAmount = b.value.compareTo(a.value);
    if (byAmount != 0) return byAmount;
    final byPlace = _place(a.key).compareTo(_place(b.key));
    if (byPlace != 0) return byPlace;
    return a.key.compareTo(b.key);
  }

  // Built-ins by grid position, then custom labels, then the fallback.
  static int _place(String label) {
    if (label == fallbackCategory.label) return expenseCategories.length + 1;
    final index = expenseCategories.indexWhere((item) => item.label == label);
    return index < 0 ? expenseCategories.length : index;
  }
}
