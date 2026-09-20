import 'package:waffer/core/data/exchange_rate.dart';
import 'package:waffer/core/data/news_article.dart';

/// بيانات تجريبية للواجهة فقط. لا تُحمَّل أسعار أو أخبار حقيقية.
class OnlineFeedService {
  OnlineFeedService._();

  static final OnlineFeedService instance = OnlineFeedService._();

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

  List<NewsArticle> get articles {
    final now = DateTime.now();
    return [
      NewsArticle(
        title: 'ارتفاع طفيف في أسعار المواد الغذائية مع بداية الأسبوع',
        body:
            'سجّلت أسواق الخضار والحبوب ارتفاعاً محدوداً مع عودة الحركة التجارية بعد العطلة. التجار عزوا التغير إلى تكاليف النقل، فيما بقيت أسعار الألبان والبيض شبه مستقرة في معظم الأحياء.',
        source: 'الوطن',
        publishedAt: now.subtract(const Duration(hours: 2)),
      ),
      NewsArticle(
        title: 'تحسّن حركة النقل بين المحافظات بعد أعمال الصيانة',
        body:
            'عادت الحافلات إلى جداولها المعتادة على الخطوط الرئيسية بعد انتهاء أعمال الصيانة في عدة مقاطع. المسافرون لاحظوا انخفاضاً في زمن الرحلة، مع استمرار بعض التأخير في ساعات الذروة.',
        source: 'سانا',
        publishedAt: now.subtract(const Duration(hours: 5)),
      ),
      NewsArticle(
        title: 'افتتاح سوق شعبي جديد يضم محال بقالة ومطاعم محلية',
        body:
            'افتُتح السوق في أحد الأحياء السكنية ويضم أكشاكاً للخضار والبقالة إلى جانب مطاعم صغيرة. الهدف تسهيل التسوق اليومي وتقليل الحاجة إلى التنقل نحو الأسواق المركزية.',
        source: 'تشرين',
        publishedAt: now.subtract(const Duration(hours: 8)),
      ),
      NewsArticle(
        title: 'نصائح لتوفير استهلاك الوقود خلال التنقل اليومي',
        body:
            'أوصى مختصون بتجنب التسارع المفاجئ وصيانة الإطارات بانتظام لتقليل الاستهلاك. كما اقترحوا دمج المشاوير اليومية في رحلة واحدة عندما يكون ذلك ممكناً.',
        source: 'الاقتصاد اليوم',
        publishedAt: now.subtract(const Duration(hours: 11)),
      ),
      NewsArticle(
        title: 'زيادة الإقبال على المقاهي مع اعتدال درجات الحرارة',
        body:
            'شهدت المقاهي الخارجية إقبالاً أوضح خلال الأيام الماضية مع تحسّن الطقس. أصحاب المحال قالوا إن الطلب ارتفع على المشروبات الباردة، مع بقاء الحركة المسائية هي الأعلى.',
        source: 'أثر برس',
        publishedAt: now.subtract(const Duration(days: 1, hours: 1)),
      ),
      NewsArticle(
        title: 'صيدليات الأحياء تمدّد ساعات العمل في عطلة نهاية الأسبوع',
        body:
            'أعلنت عدة صيدليات عن تمديد الدوام مساء الجمعة والسبت لتغطية الطلب على الأدوية الأساسية. التنسيق يشمل تناوباً بين الأحياء حتى تبقى خدمة ليلية قريبة من السكان.',
        source: 'الصحة',
        publishedAt: now.subtract(const Duration(days: 1, hours: 4)),
      ),
    ];
  }
}
