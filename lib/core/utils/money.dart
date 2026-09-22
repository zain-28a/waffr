import 'package:intl/intl.dart';
import 'package:waffer/core/data/currency.dart';

/// رمز الليرة السورية الثابت (أسعار الصرف في تبويب أونلاين).
const String sypCurrencyLabel = 'ل.س';

/// وحدة العملة النشطة في الواجهة المالية.
String get currencyLabel => CurrencyStore.instance.activeSymbol;

String currencyLabelFor(String? code) => Currencies.symbolOf(code);

final NumberFormat _moneyFormat = NumberFormat('#,##0', 'en');

String formatMoney(num value) => _moneyFormat.format(value.round());

/// تُكتب التواريخ والأوقات يدوياً بأرقام لاتينية، فلا تحتاج بيانات المواقع
/// الخاصة بـ DateFormat.
String formatDate(DateTime date) {
  final local = date.toLocal();
  return '${_twoDigits(local.day)}/${_twoDigits(local.month)}/${local.year}';
}

String formatTime(DateTime date) {
  final local = date.toLocal();
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
