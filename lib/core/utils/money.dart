import 'package:intl/intl.dart';

const String currencyLabel = 'ل.س';

final NumberFormat _moneyFormat = NumberFormat('#,##0', 'en');

String formatMoney(num value) => _moneyFormat.format(value.round());

/// تُكتب التواريخ والأوقات يدوياً بأرقام لاتينية، فلا تحتاج بيانات المواقع
/// الخاصة بـ DateFormat.
String formatDate(DateTime date) =>
    '${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}';

String formatTime(DateTime date) =>
    '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');
