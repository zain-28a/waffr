import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/smart/arabic_text.dart';

void main() {
  test('counted nouns agree with the number', () {
    expect(Ar.days.of(1), 'يوم واحد');
    expect(Ar.days.of(2), 'يومين');
    expect(Ar.days.of(3), '3 أيام');
    expect(Ar.days.of(10), '10 أيام');
    expect(Ar.days.of(11), '11 يوماً');
    expect(Ar.days.of(99), '99 يوماً');
    expect(Ar.days.of(100), '100 يوم');
    expect(Ar.days.of(103), '103 أيام');
    expect(Ar.days.of(115), '115 يوماً');
    expect(Ar.smallExpenses.of(6), '6 مصاريف صغيرة');
    expect(Ar.smallExpenses.of(14), '14 مصروفاً صغيراً');
  });

  test('categories take the definite article when they can', () {
    expect(Ar.category('طعام'), 'الطعام');
    expect(Ar.category('ترفيه'), 'الترفيه');
    expect(Ar.category('الرياضة'), 'الرياضة');
    expect(Ar.category('أخرى'), 'تصنيف «أخرى»');
    expect(Ar.category('مصاريف البيت'), 'تصنيف «مصاريف البيت»');
    expect(Ar.category('Netflix'), 'تصنيف «Netflix»');
  });

  test('prepositions join the article', () {
    expect(Ar.li('الطعام'), 'للطعام');
    expect(Ar.li('تصنيف «أخرى»'), 'لتصنيف «أخرى»');
  });
}
