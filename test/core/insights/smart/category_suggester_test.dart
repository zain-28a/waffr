import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/smart/category_suggester.dart';
import 'package:waffr/data/models/transaction.dart';

const _all = [
  'طعام',
  'مواصلات',
  'تسوق',
  'فواتير',
  'صحة',
  'ترفيه',
  'تعليم',
  'أخرى',
];

WaffrTransaction _expense(String note, String category) => WaffrTransaction(
  id: note + category,
  type: TransactionType.expense,
  amount: 10,
  dateTime: DateTime(2026, 10, 1),
  category: category,
  note: note,
);

void main() {
  test('common words map to built-in categories', () {
    final suggester = CategorySuggester(const []);

    expect(suggester.suggest('غداء بالمطعم', _all), 'طعام');
    expect(suggester.suggest('تكسي للشغل', _all), 'مواصلات');
    expect(suggester.suggest('فاتورة الكهرباء', _all), 'فواتير');
    expect(suggester.suggest('صيدليّة', _all), 'صحة');
    expect(suggester.suggest('Netflix', _all), 'فواتير');
  });

  test('history beats the dictionary', () {
    final suggester = CategorySuggester([
      _expense('قهوة مع الشباب', 'ترفيه'),
      _expense('قهوة مع الشباب', 'ترفيه'),
    ]);

    expect(suggester.suggest('قهوة مع الشباب', _all), 'ترفيه');
  });

  test('learns new words from history', () {
    final suggester = CategorySuggester([
      _expense('بيتزا هت', 'طعام'),
      _expense('اشتراك جيم', 'صحة'),
    ]);

    expect(suggester.suggest('هت', _all), 'طعام');
  });

  test('unknown text and disallowed categories give nothing', () {
    final suggester = CategorySuggester(const []);

    expect(suggester.suggest('شيء غريب', _all), isNull);
    expect(suggester.suggest('غداء', const ['مواصلات']), isNull);
    expect(suggester.suggest('', _all), isNull);
  });
}
