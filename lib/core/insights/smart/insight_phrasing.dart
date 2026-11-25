// Wording helpers shared by every insight rule: random phrasing choices
// and money, percent and day formatting.
//
// Cards used to gain a random opener ("بحسب أرقامك،") and closing remark;
// they were filler, so each rule now writes complete sentences and names
// its own next step where there is one.

import 'dart:math' as math;

import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/utils/money.dart';

/// Picks and formats the words of one analysis run.
///
/// One instance is shared by all rule groups of a run, in a fixed order, so
/// a given seed always produces the same report.
class InsightPhrasing {
  /// Phrasing for amounts in [currencySymbol], driven by [random].
  InsightPhrasing(this.currencySymbol, this._random);

  /// Symbol appended to every amount.
  final String currencySymbol;

  final math.Random _random;

  /// A random integer in [0, max), from the run's random source.
  int nextInt(int max) => _random.nextInt(max);

  /// Shuffles [items] in place with the run's random source.
  void shuffle(List<Object?> items) => items.shuffle(_random);

  /// One of [options], chosen at random.
  T pick<T>(List<T> options) => options[_random.nextInt(options.length)];

  /// An amount with the currency symbol ("1,500 ل.س").
  String money(double value) => '${formatMoney(value)} $currencySymbol';

  /// A ratio as a whole percent, isolated left-to-right so "20%" never
  /// flips inside Arabic text.
  String percent(double ratio) => '\u2066${(ratio * 100).abs().round()}%\u2069';

  /// A day count in words; below one it reads "less than a day".
  String days(int n) => n < 1 ? 'أقل من يوم' : Ar.days.of(n);
}
