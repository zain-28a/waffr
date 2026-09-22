import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الليرة السورية: العملة الإلزامية الافتراضية.
const String defaultCurrencyCode = 'SYP';

/// عملة واحدة من القائمة المعرّفة مسبقاً.
class CurrencyInfo {
  final String code;
  final String arabicName;
  final String symbol;

  const CurrencyInfo({
    required this.code,
    required this.arabicName,
    required this.symbol,
  });
}

/// الكتالوج الثابت: الليرة السورية + أكثر 20 عملة تداولاً.
class Currencies {
  Currencies._();

  static const CurrencyInfo syp = CurrencyInfo(
    code: defaultCurrencyCode,
    arabicName: 'ليرة سورية',
    symbol: 'ل.س',
  );

  static const List<CurrencyInfo> catalog = [
    syp,
    CurrencyInfo(code: 'USD', arabicName: 'دولار أمريكي', symbol: '\$'),
    CurrencyInfo(code: 'EUR', arabicName: 'يورو', symbol: '€'),
    CurrencyInfo(code: 'TRY', arabicName: 'ليرة تركية', symbol: '₺'),
    CurrencyInfo(code: 'JOD', arabicName: 'دينار أردني', symbol: 'د.أ'),
    CurrencyInfo(code: 'AED', arabicName: 'درهم إماراتي', symbol: 'د.إ'),
    CurrencyInfo(code: 'SAR', arabicName: 'ريال سعودي', symbol: 'ر.س'),
    CurrencyInfo(code: 'GBP', arabicName: 'جنيه إسترليني', symbol: '£'),
    CurrencyInfo(code: 'EGP', arabicName: 'جنيه مصري', symbol: 'ج.م'),
    CurrencyInfo(code: 'KWD', arabicName: 'دينار كويتي', symbol: 'د.ك'),
    CurrencyInfo(code: 'QAR', arabicName: 'ريال قطري', symbol: 'ر.ق'),
    CurrencyInfo(code: 'CAD', arabicName: 'دولار كندي', symbol: 'C\$'),
    CurrencyInfo(code: 'AUD', arabicName: 'دولار أسترالي', symbol: 'A\$'),
    CurrencyInfo(code: 'CHF', arabicName: 'فرنك سويسري', symbol: 'CHF'),
    CurrencyInfo(code: 'SEK', arabicName: 'كرونة سويدية', symbol: 'kr'),
    CurrencyInfo(code: 'NOK', arabicName: 'كرونة نرويجية', symbol: 'kr'),
    CurrencyInfo(code: 'DKK', arabicName: 'كرونة دنماركية', symbol: 'kr'),
    CurrencyInfo(code: 'RUB', arabicName: 'روبل روسي', symbol: '₽'),
    CurrencyInfo(code: 'CNY', arabicName: 'يوان صيني', symbol: '¥'),
    CurrencyInfo(code: 'JPY', arabicName: 'ين ياباني', symbol: '¥'),
    CurrencyInfo(code: 'INR', arabicName: 'روبية هندية', symbol: '₹'),
  ];

  static final Map<String, CurrencyInfo> _byCode = {
    for (final item in catalog) item.code: item,
  };

  static CurrencyInfo of(String code) {
    return _byCode[normalize(code)] ??
        CurrencyInfo(
          code: normalize(code),
          arabicName: normalize(code),
          symbol: normalize(code),
        );
  }

  static bool isKnown(String code) => _byCode.containsKey(normalize(code));

  static String normalize(String? raw) {
    final code = (raw ?? '').trim().toUpperCase();
    return code.isEmpty ? defaultCurrencyCode : code;
  }

  static String symbolOf(String? code) => of(normalize(code)).symbol;
}

/// العملات المفعّلة والعملة النشطة. لا يحذف البيانات المالية أبداً.
class CurrencyStore extends ChangeNotifier {
  CurrencyStore._();

  static final CurrencyStore instance = CurrencyStore._();

  static const String enabledKey = 'enabled_currencies';
  static const String activeKey = 'active_currency';

  final List<String> _enabled = [defaultCurrencyCode];
  String _activeCode = defaultCurrencyCode;

  Future<void>? _loader;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  String get activeCode => _activeCode;

  CurrencyInfo get active => Currencies.of(_activeCode);

  String get activeSymbol => active.symbol;

  /// العملات الظاهرة في دوّار الرصيد وفي منتقي المبلغ.
  List<CurrencyInfo> get enabledCurrencies {
    return [
      for (final code in _enabled) Currencies.of(code),
    ];
  }

  List<String> get enabledCodes => List.unmodifiable(_enabled);

  List<CurrencyInfo> get availableToAdd {
    return [
      for (final item in Currencies.catalog)
        if (!_enabled.contains(item.code)) item,
    ];
  }

  bool isEnabled(String code) => _enabled.contains(Currencies.normalize(code));

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> setActive(String code) async {
    await ensureLoaded();

    final normalized = Currencies.normalize(code);
    if (!_enabled.contains(normalized)) {
      return;
    }
    if (_activeCode == normalized) {
      return;
    }

    _activeCode = normalized;
    await _persistActive();
    notifyListeners();
  }

  Future<void> selectNext() async {
    await ensureLoaded();
    if (_enabled.length < 2) return;

    final index = _enabled.indexOf(_activeCode);
    final next = (index < 0 ? 0 : index + 1) % _enabled.length;
    await setActive(_enabled[next]);
  }

  Future<void> selectPrevious() async {
    await ensureLoaded();
    if (_enabled.length < 2) return;

    final index = _enabled.indexOf(_activeCode);
    final previous = (index < 0 ? 0 : index - 1 + _enabled.length) %
        _enabled.length;
    await setActive(_enabled[previous]);
  }

  Future<bool> addCurrency(String code) async {
    await ensureLoaded();

    final normalized = Currencies.normalize(code);
    if (normalized == defaultCurrencyCode) {
      return false;
    }
    if (!Currencies.isKnown(normalized) || _enabled.contains(normalized)) {
      return false;
    }

    _enabled.add(normalized);
    await _persistEnabled();
    notifyListeners();
    return true;
  }

  /// يُخرج العملة من القائمة النشطة دون حذف سجلاتها المالية.
  Future<bool> removeCurrency(String code) async {
    await ensureLoaded();

    final normalized = Currencies.normalize(code);
    if (normalized == defaultCurrencyCode) {
      return false;
    }
    if (!_enabled.contains(normalized)) {
      return false;
    }

    _enabled.remove(normalized);
    if (_activeCode == normalized) {
      _activeCode = defaultCurrencyCode;
      await _persistActive();
    }
    await _persistEnabled();
    notifyListeners();
    return true;
  }

  void resetCache() {
    _enabled
      ..clear()
      ..add(defaultCurrencyCode);
    _activeCode = defaultCurrencyCode;
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(enabledKey) ?? const [];

    _enabled
      ..clear()
      ..add(defaultCurrencyCode);

    for (final raw in stored) {
      final code = Currencies.normalize(raw);
      if (code == defaultCurrencyCode) continue;
      if (!Currencies.isKnown(code)) continue;
      if (_enabled.contains(code)) continue;
      _enabled.add(code);
    }

    final active = Currencies.normalize(prefs.getString(activeKey));
    _activeCode = _enabled.contains(active) ? active : defaultCurrencyCode;

    _loaded = true;
    notifyListeners();
  }

  Future<void> _persistEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(enabledKey, _enabled);
  }

  Future<void> _persistActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeKey, _activeCode);
  }
}
