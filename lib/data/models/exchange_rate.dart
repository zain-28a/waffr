// Live FX / gold quotes shown on the home exchange strip.
// Buy and sell stay null until a live source exists; the UI shows a minus.

// One row: asset code, labels for the chip/pair, and buy/sell against SYP.
class ExchangeRate {
  static const String unavailable = '−';

  final String code;
  final String chipLabel;
  final String pairLabel;
  final double? buy;
  final double? sell;
  final DateTime? updatedAt;

  const ExchangeRate({
    required this.code,
    required this.chipLabel,
    required this.pairLabel,
    this.buy,
    this.sell,
    this.updatedAt,
  });
}
