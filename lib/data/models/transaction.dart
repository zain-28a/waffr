// Money movement types and the WafferTransaction record stored as JSON in prefs.

import 'dart:convert';

import 'package:waffer/data/models/currency.dart';

enum TransactionType { income, expense, savingsIn, savingsOut }

// Income cadence: none means no automatic savings rollover for that entry.
enum RecurringFrequency { none, weekly, monthly }

// Why a savings transfer happened — auto leftover, goal plan, manual, or withdraw.
enum SavingsTransferKind { periodLeftover, goalPeriodic, manual, withdraw }

// One ledger row: income, expense, or savings in/out, with optional period/goal links.
class WafferTransaction {
  final String id;
  final TransactionType type;
  final double amount;

  final String currencyCode;

  final String? category;

  final String? paymentMethod;

  final String? note;

  final String? sourceId;

  final DateTime dateTime;

  final RecurringFrequency frequency;

  final String? periodKey;

  final SavingsTransferKind? transferKind;

  final String? goalId;

  final String? processedPeriodKey;

  final DateTime? updatedAt;

  const WafferTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.currencyCode = defaultCurrencyCode,
    required this.dateTime,
    this.category,
    this.paymentMethod,
    this.note,
    this.sourceId,
    this.frequency = RecurringFrequency.none,
    this.periodKey,
    this.transferKind,
    this.goalId,
    this.processedPeriodKey,
    this.updatedAt,
  });

  DateTime get syncUpdatedAt => (updatedAt ?? dateTime).toUtc();

  WafferTransaction copyWith({DateTime? dateTime, String? currencyCode}) {
    return WafferTransaction(
      id: id,
      type: type,
      amount: amount,
      currencyCode: currencyCode ?? this.currencyCode,
      dateTime: dateTime ?? this.dateTime,
      category: category,
      paymentMethod: paymentMethod,
      note: note,
      sourceId: sourceId,
      frequency: frequency,
      periodKey: periodKey,
      transferKind: transferKind,
      goalId: goalId,
      processedPeriodKey: processedPeriodKey,
      updatedAt: updatedAt,
    );
  }

  bool get isIncome => type == TransactionType.income;

  bool get isExpense => type == TransactionType.expense;

  bool get isSavingsIn => type == TransactionType.savingsIn;

  bool get isSavingsOut => type == TransactionType.savingsOut;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'amount': amount,
    'currencyCode': currencyCode,
    'category': category,
    'paymentMethod': paymentMethod,
    'note': note,
    'sourceId': sourceId,
    'dateTime': dateTime.toIso8601String(),
    'frequency': frequency.name,
    'periodKey': periodKey,
    'transferKind': transferKind?.name,
    'goalId': goalId,
    'processedPeriodKey': processedPeriodKey,
    'updatedAt': syncUpdatedAt.toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  // Prefs decode; rejects non-positive amounts. Accepts legacy currency_code.
  static WafferTransaction? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final amount = (decoded['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) return null;

      return WafferTransaction(
        id: _text(decoded['id']) ?? newId(),
        type: _parseType(_text(decoded['type'])),
        amount: amount,
        currencyCode: Currencies.normalize(
          _text(decoded['currencyCode']) ?? _text(decoded['currency_code']),
        ),
        category: _text(decoded['category']),
        paymentMethod: _text(decoded['paymentMethod']),
        note: _text(decoded['note']),
        sourceId: _text(decoded['sourceId']),
        dateTime:
            (DateTime.tryParse(_text(decoded['dateTime']) ?? '') ??
                    DateTime.now())
                .toLocal(),
        frequency: _parseFrequency(_text(decoded['frequency'])),
        periodKey: _text(decoded['periodKey']),
        transferKind: _parseTransferKind(_text(decoded['transferKind'])),
        goalId: _text(decoded['goalId']),
        processedPeriodKey: _text(decoded['processedPeriodKey']),
        updatedAt: DateTime.tryParse(_text(decoded['updatedAt']) ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  static int _seq = 0;

  static String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  static TransactionType _parseType(String? raw) {
    return switch (raw) {
      'income' => TransactionType.income,
      'savingsIn' => TransactionType.savingsIn,
      'savingsOut' => TransactionType.savingsOut,
      _ => TransactionType.expense,
    };
  }

  static RecurringFrequency frequencyFrom(String? raw) =>
      _parseFrequency(raw);

  static SavingsTransferKind? transferKindFrom(String? raw) =>
      _parseTransferKind(raw);

  static RecurringFrequency _parseFrequency(String? raw) {
    return switch (raw) {
      'weekly' => RecurringFrequency.weekly,
      'monthly' => RecurringFrequency.monthly,
      _ => RecurringFrequency.none,
    };
  }

  static SavingsTransferKind? _parseTransferKind(String? raw) {
    return switch (raw) {
      'periodLeftover' => SavingsTransferKind.periodLeftover,
      'goalPeriodic' => SavingsTransferKind.goalPeriodic,
      'manual' => SavingsTransferKind.manual,
      'withdraw' => SavingsTransferKind.withdraw,
      _ => null,
    };
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
