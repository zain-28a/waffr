// SpendingBreakdown: ranking, shares, the top category and tie order.

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/models/spending_breakdown.dart';

void main() {
  test('ranks categories by amount and computes shares', () {
    final breakdown = SpendingBreakdown.fromTotals({
      'مواصلات': 30,
      'طعام': 50,
      'تسوق': 20,
    });
    expect(breakdown.total, 100);
    expect(breakdown.items.map((item) => item.category), [
      'طعام',
      'مواصلات',
      'تسوق',
    ]);
    expect(breakdown.top!.category, 'طعام');
    expect(breakdown.top!.share, closeTo(0.5, 1e-9));
  });

  test('nothing spent gives an empty breakdown without a top', () {
    for (final totals in [
      <String, double>{},
      {'طعام': 0.0},
      {'طعام': -5.0},
    ]) {
      final breakdown = SpendingBreakdown.fromTotals(totals);
      expect(breakdown.isEmpty, isTrue);
      expect(breakdown.top, isNull);
      expect(breakdown.total, 0);
    }
  });

  test('ties follow the grid order, then labels, with أخرى last', () {
    final breakdown = SpendingBreakdown.fromTotals({
      'أخرى': 10,
      'قهوة': 10,
      'ترفيه': 10,
      'طعام': 10,
      'إيجار': 10,
    });
    expect(breakdown.items.map((item) => item.category), [
      'طعام',
      'ترفيه',
      'إيجار',
      'قهوة',
      'أخرى',
    ]);
    // The same input in another order resolves the same way.
    final reversed = SpendingBreakdown.fromTotals({
      'إيجار': 10,
      'طعام': 10,
      'ترفيه': 10,
      'قهوة': 10,
      'أخرى': 10,
    });
    expect(reversed.top!.category, 'طعام');
  });

  test('saved period names parse back, unknown ones fall back', () {
    for (final period in SpendingPeriod.values) {
      expect(SpendingPeriod.parse(period.name), period);
    }
    expect(SpendingPeriod.parse(null), SpendingPeriod.cycle);
    expect(SpendingPeriod.parse('year'), SpendingPeriod.cycle);
  });
}
