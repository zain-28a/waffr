// Recurring expense schedule: interval units, model, and prefs serialization.

import 'dart:convert';

import 'package:waffer/data/models/currency.dart';

enum RecurringUnit { day, week, month }

extension RecurringUnitLabel on RecurringUnit {
  String get label => switch (this) {
    RecurringUnit.day => 'يوم',
    RecurringUnit.week => 'أسبوع',
    RecurringUnit.month => 'شهر',
  };

  String get plural => switch (this) {
    RecurringUnit.day => 'أيام',
    RecurringUnit.week => 'أسابيع',
    RecurringUnit.month => 'أشهر',
  };
}

// Auto-deducted expense; [nextDueAt] drives catch-up in the store.
class RecurringExpense {
  final String id;
  final double amount;
  final String currencyCode;
  final String category;
  final String paymentMethod;
  final String? note;
  final RecurringUnit unit;
  final int intervalCount;
  final DateTime createdAt;
  final DateTime nextDueAt;
  final bool enabled;
  final DateTime? updatedAt;

  const RecurringExpense({
    required this.id,
    required this.amount,
    this.currencyCode = defaultCurrencyCode,
    required this.category,
    required this.paymentMethod,
    required this.unit,
    required this.intervalCount,
    required this.createdAt,
    required this.nextDueAt,
    this.note,
    this.enabled = true,
    this.updatedAt,
  });

  DateTime get syncUpdatedAt => (updatedAt ?? createdAt).toUtc();

  // Arabic "every N days/weeks/months" for notes and UI.
  String get intervalDescription {
    if (intervalCount <= 1) {
      return 'كل ${unit.label}';
    }

    return 'كل $intervalCount ${unit.plural}';
  }

  RecurringExpense copyWith({
    double? amount,
    String? currencyCode,
    DateTime? nextDueAt,
    bool? enabled,
    DateTime? updatedAt,
    bool touch = true,
  }) {
    return RecurringExpense(
      id: id,
      amount: amount ?? this.amount,
      currencyCode: currencyCode ?? this.currencyCode,
      category: category,
      paymentMethod: paymentMethod,
      note: note,
      unit: unit,
      intervalCount: intervalCount,
      createdAt: createdAt,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      enabled: enabled ?? this.enabled,
      updatedAt: updatedAt ??
          (touch ? DateTime.now().toUtc() : this.updatedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'currencyCode': currencyCode,
    'category': category,
    'paymentMethod': paymentMethod,
    'note': note,
    'unit': unit.name,
    'intervalCount': intervalCount,
    'createdAt': createdAt.toIso8601String(),
    'nextDueAt': nextDueAt.toIso8601String(),
    'enabled': enabled,
    'updatedAt': syncUpdatedAt.toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  // Prefs decode; rejects non-positive amount or interval.
  static RecurringExpense? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final amount = (decoded['amount'] as num?)?.toDouble() ?? 0;
      final intervalCount = (decoded['intervalCount'] as num?)?.toInt() ?? 0;
      if (amount <= 0 || intervalCount <= 0) return null;

      final id = decoded['id']?.toString().trim() ?? '';
      final category = decoded['category']?.toString().trim() ?? '';
      if (id.isEmpty || category.isEmpty) return null;

      final createdAt =
          (DateTime.tryParse(decoded['createdAt']?.toString() ?? '') ??
                  DateTime.now())
              .toLocal();
      final nextDueAt =
          (DateTime.tryParse(decoded['nextDueAt']?.toString() ?? '') ??
                  createdAt)
              .toLocal();

      return RecurringExpense(
        id: id,
        amount: amount,
        currencyCode: Currencies.normalize(
          decoded['currencyCode']?.toString() ??
              decoded['currency_code']?.toString(),
        ),
        category: category,
        paymentMethod: decoded['paymentMethod']?.toString() ?? '',
        note: _text(decoded['note']),
        unit: _parseUnit(decoded['unit']?.toString()),
        intervalCount: intervalCount,
        createdAt: createdAt,
        nextDueAt: nextDueAt,
        enabled: decoded['enabled'] != false,
        updatedAt: DateTime.tryParse(decoded['updatedAt']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  // Advances [from] by count units; months clamp to the last valid day.
  static DateTime nextDueFrom(DateTime from, RecurringUnit unit, int count) {
    final safeCount = count < 1 ? 1 : count;

    switch (unit) {
      case RecurringUnit.day:
        return from.add(Duration(days: safeCount));
      case RecurringUnit.week:
        return from.add(Duration(days: 7 * safeCount));
      case RecurringUnit.month:
        final targetMonth = from.month + safeCount;
        final year = from.year + ((targetMonth - 1) ~/ 12);
        final month = ((targetMonth - 1) % 12) + 1;
        final lastDay = DateTime(year, month + 1, 0).day;
        final day = from.day > lastDay ? lastDay : from.day;
        return DateTime(
          year,
          month,
          day,
          from.hour,
          from.minute,
          from.second,
          from.millisecond,
        );
    }
  }

  static int _seq = 0;

  static String newId() =>
      'r${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  static RecurringUnit _parseUnit(String? raw) {
    return switch (raw) {
      'week' => RecurringUnit.week,
      'month' => RecurringUnit.month,
      _ => RecurringUnit.day,
    };
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
