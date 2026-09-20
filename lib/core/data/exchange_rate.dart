enum ExchangeAsset { usd, eur, tryLira, gold }

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
