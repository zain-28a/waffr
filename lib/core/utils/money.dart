import 'package:intl/intl.dart';

const String currencyLabel = 'ل.س';

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
