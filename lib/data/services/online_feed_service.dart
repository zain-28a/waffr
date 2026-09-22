import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:waffer/data/models/exchange_rate.dart';
import 'package:waffer/data/models/news_article.dart';
import 'package:waffer/core/sync/api_config.dart';

/// Online feed helpers: hardcoded exchange rates plus news from the API.
class OnlineFeedService {
  OnlineFeedService._();

  static final OnlineFeedService instance = OnlineFeedService._();

  static const Duration _timeout = Duration(seconds: 25);

  static const List<ExchangeRate> rates = [
    ExchangeRate(
      asset: ExchangeAsset.usd,
      chipLabel: 'دولار',
      pairLabel: 'دولار أمريكي',
      buy: 11850,
      sell: 12120,
    ),
    ExchangeRate(
      asset: ExchangeAsset.eur,
      chipLabel: 'يورو',
      pairLabel: 'يورو',
      buy: 12840,
      sell: 13180,
    ),
    ExchangeRate(
      asset: ExchangeAsset.tryLira,
      chipLabel: 'ليرة',
      pairLabel: 'ليرة تركية',
      buy: 345,
      sell: 368,
    ),
    ExchangeRate(
      asset: ExchangeAsset.gold,
      chipLabel: 'ذهب',
      pairLabel: 'ذهب عيار 21',
      buy: 852000,
      sell: 868000,
    ),
  ];

  static ExchangeRate rateFor(ExchangeAsset asset) {
    return rates.firstWhere((rate) => rate.asset == asset);
  }

  /// GET `/online/news` and parse each map into a [NewsArticle].
  Future<List<NewsArticle>> fetchArticles() async {
    final base = await ApiConfig.baseUrl();
    final response = await http
        .get(
          Uri.parse('$base/online/news'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('news ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const FormatException('news payload');
    }

    final articles = <NewsArticle>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final article = NewsArticle.fromApi(Map<String, dynamic>.from(item));
      if (article != null) articles.add(article);
    }
    return articles;
  }
}
