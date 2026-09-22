// Live FX / gold quotes shown on the home exchange strip.

enum ExchangeAsset { usd, eur, tryLira, gold }

// One row: asset, labels for the chip/pair, and buy/sell against SYP.
class ExchangeRate {
  final ExchangeAsset asset;
  final String chipLabel;
  final String pairLabel;
  final double buy;
  final double sell;
  final DateTime? updatedAt;

  const ExchangeRate({
    required this.asset,
    required this.chipLabel,
    required this.pairLabel,
    required this.buy,
    required this.sell,
    this.updatedAt,
  });
}
