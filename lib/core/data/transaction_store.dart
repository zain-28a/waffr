import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/transaction.dart';

/// المصدر الوحيد لبيانات العمليات والرصيد.
///
/// العمليات محفوظة كقائمة JSON في SharedPreferences، والرصيد يُحتسب منها
/// دائماً حتى لا يتعارض رقمان مخزّنان. يُكتب `balance` و `max_balance` عند كل
/// تعديل فقط، لذلك لا يمكن أن تكتب الشاشة صفراً فوق الرصيد المحفوظ أثناء
/// التحميل.
class TransactionStore extends ChangeNotifier {
  TransactionStore._();

  static final TransactionStore instance = TransactionStore._();

  static const String transactionsKey = 'transactions';
  static const String balanceKey = 'balance';
  static const String maxBalanceKey = 'max_balance';

  /// التنسيق القديم: `amount|description|isoDate`.
  static const String legacyExpensesKey = 'expenses';

  final List<WafferTransaction> _transactions = [];

  Future<void>? _loader;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// من الأحدث إلى الأقدم.
  List<WafferTransaction> get transactions => List.unmodifiable(_transactions);

  List<WafferTransaction> get expenses =>
      _transactions.where((item) => !item.isIncome).toList(growable: false);

  double get totalIncome => _totalOf(income: true);

  double get totalExpense => _totalOf(income: false);

  double get balance => totalIncome - totalExpense;

  /// أقصى رصيد وصل إليه المستخدم، أي مجموع كل الدخل المسجّل.
  double get maxBalance => totalIncome;

  /// نسبة ما تبقى من الرصيد الأقصى (0.0 – 1.0).
  double get remainingRatio {
    final max = maxBalance;
    if (max <= 0) return 0;
    return (balance / max).clamp(0.0, 1.0);
  }

  /// مجموع المصروف لكل تصنيف، من الأكبر إلى الأصغر، بدون التصنيفات الفارغة.
  List<({String category, double amount})> expensesByCategory() {
    final totals = <String, double>{};

    for (final expense in expenses) {
      final category = expense.category ?? 'أخرى';
      totals[category] = (totals[category] ?? 0) + expense.amount;
    }

    final entries = totals.entries
        .map((entry) => (category: entry.key, amount: entry.value))
        .toList();

    entries.sort((a, b) => b.amount.compareTo(a.amount));
    return entries;
  }

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> addIncome({
    required double amount,
    String? source,
  }) {
    return _add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.income,
        amount: amount,
        note: source,
        dateTime: DateTime.now(),
      ),
    );
  }

  Future<void> addExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? note,
  }) {
    return _add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.expense,
        amount: amount,
        category: category,
        paymentMethod: paymentMethod,
        note: note,
        dateTime: DateTime.now(),
      ),
    );
  }

  /// تُفرِغ النسخة المحفوظة في الذاكرة، فتُقرأ العمليات من التخزين عند أول
  /// استخدام لاحق. تُستخدم بعد حذف بيانات التطبيق.
  void resetCache() {
    _transactions.clear();
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  Future<void> _add(WafferTransaction transaction) async {
    await ensureLoaded();

    _transactions.add(transaction);
    _sort();

    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);

    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(transactionsKey);

    _transactions.clear();

    if (stored != null) {
      _transactions.addAll(
        stored.map(WafferTransaction.decode).whereType<WafferTransaction>(),
      );
      _sort();
    } else {
      _transactions.addAll(
        _migrateLegacyExpenses(prefs.getStringList(legacyExpensesKey)),
      );
      _sort();

      if (_transactions.isNotEmpty) {
        await _persist(prefs);
      }
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setStringList(
      transactionsKey,
      _transactions.map((item) => item.encode()).toList(),
    );

    await prefs.setDouble(balanceKey, balance);
    await prefs.setDouble(maxBalanceKey, maxBalance);
  }

  List<WafferTransaction> _migrateLegacyExpenses(List<String>? legacy) {
    if (legacy == null || legacy.isEmpty) return const [];

    final migrated = <WafferTransaction>[];

    for (final entry in legacy) {
      final parts = entry.split('|');
      final amount = double.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
      if (amount <= 0) continue;

      final note = parts.length > 1 && parts[1].trim().isNotEmpty
          ? parts[1].trim()
          : null;

      final date = parts.length > 2 ? DateTime.tryParse(parts[2]) : null;

      migrated.add(
        WafferTransaction(
          id: WafferTransaction.newId() + migrated.length.toString(),
          type: TransactionType.expense,
          amount: amount,
          category: 'أخرى',
          note: note,
          dateTime: date ?? DateTime.now(),
        ),
      );
    }

    return migrated;
  }

  void _sort() {
    _transactions.sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  double _totalOf({required bool income}) {
    return _transactions
        .where((item) => item.isIncome == income)
        .fold<double>(0, (sum, item) => sum + item.amount);
  }
}
