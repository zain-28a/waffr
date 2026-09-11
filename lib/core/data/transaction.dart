import 'dart:convert';

enum TransactionType { income, expense }

/// عملية واحدة (دخل أو مصروف) كما تُخزَّن في SharedPreferences بصيغة JSON.
class WafferTransaction {
  final String id;
  final TransactionType type;
  final double amount;

  /// للمصروف فقط.
  final String? category;

  /// للمصروف فقط.
  final String? paymentMethod;

  /// ملاحظة المصروف أو مصدر الدخل.
  final String? note;

  final DateTime dateTime;

  const WafferTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.dateTime,
    this.category,
    this.paymentMethod,
    this.note,
  });

  bool get isIncome => type == TransactionType.income;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'category': category,
        'paymentMethod': paymentMethod,
        'note': note,
        'dateTime': dateTime.toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  static WafferTransaction? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final amount = (decoded['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) return null;

      return WafferTransaction(
        id: _text(decoded['id']) ?? newId(),
        type: _text(decoded['type']) == TransactionType.income.name
            ? TransactionType.income
            : TransactionType.expense,
        amount: amount,
        category: _text(decoded['category']),
        paymentMethod: _text(decoded['paymentMethod']),
        note: _text(decoded['note']),
        dateTime:
            DateTime.tryParse(_text(decoded['dateTime']) ?? '') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
