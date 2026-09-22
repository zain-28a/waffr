import 'dart:convert';

enum TransactionType { income, expense, savingsIn, savingsOut }

/// مدة الدخل المضافة: بدون مدة لا تُرحَّل تلقائياً إلى الادخار.
enum RecurringFrequency { none, weekly, monthly }

/// سبب حركة الادخار، لتمييز التحويلات التلقائية عن اليدوية.
enum SavingsTransferKind { periodLeftover, goalPeriodic, manual, withdraw }

/// عملية واحدة كما تُخزَّن في SharedPreferences بصيغة JSON.
class WafferTransaction {
  final String id;
  final TransactionType type;
  final double amount;

  /// للمصروف فقط.
  final String? category;

  /// للمصروف فقط.
  final String? paymentMethod;

  /// ملاحظة المصروف أو مصدر الدخل أو وصف حركة الادخار.
  final String? note;

  /// معرّف اختياري للعملية في الميزة التي أنشأتها، لمنع الإنشاء المكرر.
  final String? sourceId;

  final DateTime dateTime;

  /// للدخل: أسبوعي / شهري / بدون مدة.
  final RecurringFrequency frequency;

  /// مفتاح الفترة التقويمية التي ينتمي إليها الدخل الدوري.
  final String? periodKey;

  /// لحركات الادخار فقط.
  final SavingsTransferKind? transferKind;

  /// الهدف المرتبط بحركة ادخار دورية، إن وُجد.
  final String? goalId;

  /// الفترة التي سُوِّيت عند إنهاء المدة (لمنع التكرار).
  final String? processedPeriodKey;

  /// وقت آخر تعديل محلي/سحابي. إن غاب يُستخدم [dateTime].
  final DateTime? updatedAt;

  const WafferTransaction({
    required this.id,
    required this.type,
    required this.amount,
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

  WafferTransaction copyWith({DateTime? dateTime}) {
    return WafferTransaction(
      id: id,
      type: type,
      amount: amount,
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
