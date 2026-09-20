import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/calendar_period.dart';
import 'package:waffer/core/data/savings_goal.dart';
import 'package:waffer/core/data/transaction.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/sync/sync_mapper.dart';
import 'package:waffer/core/sync/sync_merge.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';

/// المصدر الوحيد لبيانات العمليات والرصيد والادخار.
///
/// العمليات محفوظة كقائمة JSON في SharedPreferences،
/// والرصيد التشغيلي يُحتسب منها دائماً:
/// الدخل − المصروف − صافي الادخار.
class TransactionStore extends ChangeNotifier {
  TransactionStore._();

  static final TransactionStore instance = TransactionStore._();

  static const String transactionsKey = 'transactions';
  static const String balanceKey = 'balance';
  static const String maxBalanceKey = 'max_balance';
  static const String savingsGoalsKey = 'savings_goals';
  static const String legacySavingsGoalKey = 'savings_goal';
  static const String processedPeriodsKey = 'processed_periods';
  static const String savingsBalanceKey = 'savings_balance';
  static const String monthlyIncomeKey = 'monthly_income_amount';
  static const String weeklyIncomeKey = 'weekly_income_amount';

  /// التنسيق القديم:
  /// `amount|description|isoDate`.
  static const String legacyExpensesKey = 'expenses';

  final List<WafferTransaction> _transactions = [];
  final List<SavingsGoal> _goals = [];
  final Set<String> _processedPeriods = {};
  final Map<String, Future<WafferTransaction?>> _pendingExpenseSources = {};

  Future<void>? _loader;
  bool _loaded = false;
  bool _processingPeriods = false;
  double? _monthlyIncomeOverride;
  double? _weeklyIncomeOverride;

  /// بعد قراءة البيانات المحفوظة وقبل معالجة
  /// الفترات المستحقة.
  Future<void> Function()? onHydrated;

  bool get isLoaded => _loaded;

  Set<String> get processedPeriodTokens => Set.unmodifiable(_processedPeriods);

  double? get monthlyIncomeOverride => _monthlyIncomeOverride;

  double? get weeklyIncomeOverride => _weeklyIncomeOverride;

  /// من الأحدث إلى الأقدم.
  List<WafferTransaction> get transactions => List.unmodifiable(_transactions);

  List<WafferTransaction> get expenses =>
      _transactions.where((item) => item.isExpense).toList(growable: false);

  List<WafferTransaction> get incomes =>
      _transactions.where((item) => item.isIncome).toList(growable: false);

  List<WafferTransaction> get savingsTransfers => _transactions
      .where((item) => item.isSavingsIn || item.isSavingsOut)
      .toList(growable: false);

  List<SavingsGoal> get goals => List.unmodifiable(_goals);

  /// الأهداف غير المكتملة حسب الأولوية (0 = الأعلى).
  List<SavingsGoal> get activeGoals =>
      _goals.where((goal) => !goal.isCompleted).toList(growable: false);

  /// أعلى هدف أولوية غير مكتمل.
  SavingsGoal? get activeGoal {
    final current = activeGoals;
    return current.isEmpty ? null : current.first;
  }

  /// أول هدف نشط بخصم دوري، حسب الأولوية.
  SavingsGoal? get activePeriodicGoal {
    for (final goal in activeGoals) {
      if (goal.isPeriodic) return goal;
    }
    return null;
  }

  bool get hasActivePeriodicPlan => activePeriodicGoal != null;

  List<SavingsGoal> get completedGoals =>
      _goals.where((goal) => goal.isCompleted).toList(growable: false)..sort(
        (a, b) => (b.completedAt ?? b.createdAt).compareTo(
          a.completedAt ?? a.createdAt,
        ),
      );

  double get totalIncome => _totalOf(TransactionType.income);

  double get totalExpense => _totalOf(TransactionType.expense);

  double get totalSavingsIn => _totalOf(TransactionType.savingsIn);

  double get totalSavingsOut => _totalOf(TransactionType.savingsOut);

  /// المال الموجود حالياً في قسم الادخار.
  double get savingsBalance {
    final value = totalSavingsIn - totalSavingsOut;

    return value < 0 ? 0 : value;
  }

  /// الرصيد التشغيلي المتاح للصرف.
  /// لا يشمل المدخرات.
  double get balance {
    return totalIncome - totalExpense - savingsBalance;
  }

  /// هل يمكن خصم [amount] دون أن يصبح الرصيد سالباً.
  bool canDeduct(double amount) => amount > 0 && amount <= balance;

  bool get hasMonthlyIncome {
    if (_monthlyIncomeOverride != null && _monthlyIncomeOverride! > 0) {
      return true;
    }

    return incomes.any((item) => item.frequency == RecurringFrequency.monthly);
  }

  bool get hasWeeklyIncome {
    if (_weeklyIncomeOverride != null && _weeklyIncomeOverride! > 0) {
      return true;
    }

    return incomes.any((item) => item.frequency == RecurringFrequency.weekly);
  }

  bool get hasRecurringIncome => hasMonthlyIncome || hasWeeklyIncome;

  /// أقصى رصيد وصل إليه المستخدم.
  /// أي مجموع كل الدخل المسجل.
  double get maxBalance => totalIncome;

  /// نسبة ما تبقى من الرصيد التشغيلي.
  double get remainingRatio {
    final max = maxBalance;

    if (max <= 0) {
      return 0;
    }

    return (balance / max).clamp(0.0, 1.0);
  }

  /// مجموع المصروف لكل تصنيف،
  /// من الأكبر إلى الأصغر.
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

  /// صافي الادخار داخل فترة [start, end):
  /// ما دخل الادخار ناقص ما سُحب.
  double savingsNetDuring(DateTime start, DateTime end) {
    var incoming = 0.0;
    var outgoing = 0.0;

    for (final item in _transactions) {
      if (item.dateTime.isBefore(start) || !item.dateTime.isBefore(end)) {
        continue;
      }

      if (item.isSavingsIn) {
        incoming += item.amount;
      }

      if (item.isSavingsOut) {
        outgoing += item.amount;
      }
    }

    final net = incoming - outgoing;

    return net < 0 ? 0 : net;
  }

  /// المبلغ المدّخر حالياً لهذا الهدف.
  double currentSaved(SavingsGoal goal) => goalProgress(goal);

  /// تقدّم الهدف:
  /// التحويلات الموسومة بـ [SavingsGoal.id]،
  /// بالإضافة إلى التحويلات القديمة بلا وسم — تُنسب للهدف
  /// الذي كان نشطاً وقت إنشائها حتى لا يُفقد تقدّم المستخدم الحالي.
  double goalProgress(SavingsGoal goal) {
    if (goal.isCompleted) {
      return goal.completedAmount ?? goal.targetAmount;
    }

    var saved = 0.0;
    var withdrawn = 0.0;

    for (final item in _transactions) {
      if (item.dateTime.isBefore(goal.createdAt)) {
        continue;
      }

      if (!_countsTowardGoal(item, goal)) {
        continue;
      }

      if (item.isSavingsIn) {
        saved += item.amount;
      }

      if (item.isSavingsOut) {
        withdrawn += item.amount;
      }
    }

    final progress = saved - withdrawn;

    return progress < 0 ? 0 : progress;
  }

  double goalRatio(SavingsGoal goal) {
    if (goal.targetAmount <= 0) {
      return 0;
    }

    return (goalProgress(goal) / goal.targetAmount).clamp(0.0, 1.0);
  }

  /// دخل الفترة الحالية أو السابقة حسب التردد.
  double referenceIncome(RecurringFrequency frequency) {
    final override = _overrideFor(frequency);
    if (override != null && override > 0) {
      return override;
    }

    if (frequency == RecurringFrequency.none) {
      return _incomeInCalendar(RecurringFrequency.monthly, DateTime.now());
    }

    final now = DateTime.now();

    final currentKey = CalendarPeriod.keyFor(frequency, now);

    final current = _incomeForPeriod(frequency, currentKey);

    if (current > 0) {
      return current;
    }

    final currentPeriod = CalendarPeriod.ofFrequency(frequency, now);

    final previousStart = frequency == RecurringFrequency.weekly
        ? currentPeriod.start.subtract(const Duration(days: 7))
        : DateTime(currentPeriod.start.year, currentPeriod.start.month - 1);

    final previousKey = CalendarPeriod.keyFor(frequency, previousStart);

    final previous = _incomeForPeriod(frequency, previousKey);

    if (previous > 0) {
      return previous;
    }

    return _incomeInCalendar(frequency, now);
  }

  /// يحدد نوع دخل المستخدم من آخر دخل دوري سجله.
  ///
  /// إذا كان آخر راتب Weekly:
  /// الخطة تصبح Weekly.
  ///
  /// إذا كان آخر راتب Monthly:
  /// الخطة تصبح Monthly.
  RecurringFrequency get preferredIncomeFrequency {
    WafferTransaction? latestRecurringIncome;

    for (final income in incomes) {
      if (income.frequency == RecurringFrequency.weekly ||
          income.frequency == RecurringFrequency.monthly) {
        latestRecurringIncome = income;
        break;
      }
    }

    if (latestRecurringIncome != null) {
      return latestRecurringIncome.frequency;
    }

    final weekly = _incomeInCalendar(RecurringFrequency.weekly, DateTime.now());

    final monthly = _incomeInCalendar(
      RecurringFrequency.monthly,
      DateTime.now(),
    );

    if (weekly > 0 && monthly <= 0) {
      return RecurringFrequency.weekly;
    }

    return RecurringFrequency.monthly;
  }

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> addIncome({
    required double amount,
    String? source,
    RecurringFrequency frequency = RecurringFrequency.none,
    bool moveBalanceToSavings = false,
  }) async {
    await ensureLoaded();

    final currentBalance = balance;

    if (moveBalanceToSavings && currentBalance > 0) {
      await _add(
        WafferTransaction(
          id: WafferTransaction.newId(),
          type: TransactionType.savingsIn,
          amount: currentBalance,
          note: 'نقل الرصيد الحالي إلى التوفير',
          dateTime: DateTime.now(),
          transferKind: SavingsTransferKind.manual,
          goalId: activeGoal?.id,
        ),
        persist: false,
        notify: false,
      );
    }

    final now = DateTime.now();

    await _add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.income,
        amount: amount,
        note: source,
        dateTime: now,
        frequency: frequency,
        periodKey: frequency == RecurringFrequency.none
            ? null
            : CalendarPeriod.keyFor(frequency, now),
      ),
      persist: false,
      notify: false,
    );

    if (frequency == RecurringFrequency.monthly ||
        frequency == RecurringFrequency.weekly) {
      _setOverride(frequency, amount);
    }

    final prefs = await SharedPreferences.getInstance();
    await _persistAll(prefs);
    notifyListeners();
  }

  /// يحدّث رقم الدخل الدوري المستخدم في الخطط دون تغيير الرصيد.
  Future<bool> setPreferredIncomeAmount({
    required RecurringFrequency frequency,
    required double amount,
  }) async {
    await ensureLoaded();

    if (!amount.isFinite || amount <= 0) {
      return false;
    }

    if (frequency != RecurringFrequency.monthly &&
        frequency != RecurringFrequency.weekly) {
      return false;
    }

    _setOverride(frequency, amount);
    await SyncDirty.mark(settings: true);
    final goalsChanged = _syncPeriodicGoalAmounts(frequency, amount);

    final prefs = await SharedPreferences.getInstance();
    await _persistIncomeOverrides(prefs);
    if (goalsChanged) {
      await _persistGoals(prefs);
    }

    // After the income dialog closes, let the current frame finish
    // before waking Home/Report/Savings (charts + keep-alive tabs).
    await Future<void>.delayed(Duration.zero);
    notifyListeners();

    return true;
  }

  bool _syncPeriodicGoalAmounts(RecurringFrequency frequency, double income) {
    var changed = false;

    for (var i = 0; i < _goals.length; i++) {
      final goal = _goals[i];
      if (goal.isCompleted || !goal.isPeriodic) continue;
      if (goal.deductFrequency != frequency) continue;

      final percent = goal.allocatePercent;
      if (percent == null || percent <= 0) continue;

      final perPeriod = income * percent / 100;
      if (!perPeriod.isFinite || perPeriod <= 0) continue;
      if (perPeriod == goal.allocateAmount) continue;

      _goals[i] = goal.copyWith(allocateAmount: perPeriod, touch: true);
      changed = true;
    }

    return changed;
  }

  /// يرجع العملية عند النجاح، أو `null` إذا كان المبلغ أكبر من الرصيد.
  Future<WafferTransaction?> addExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? note,
    String? sourceId,
  }) async {
    await ensureLoaded();

    if (!canDeduct(amount)) {
      return null;
    }

    if (sourceId != null) {
      for (final expense in expenses) {
        if (expense.sourceId == sourceId) {
          return expense;
        }
      }

      final pending = _pendingExpenseSources[sourceId];
      if (pending != null) {
        return pending;
      }
    }

    final future = _createExpense(
      amount: amount,
      category: category,
      paymentMethod: paymentMethod,
      note: note,
      sourceId: sourceId,
    );

    if (sourceId == null) {
      return future;
    }

    _pendingExpenseSources[sourceId] = future;

    try {
      return await future;
    } finally {
      if (identical(_pendingExpenseSources[sourceId], future)) {
        _pendingExpenseSources.remove(sourceId);
      }
    }
  }

  /// يحذف المصروف من السجل فيعود مبلغه إلى الرصيد.
  Future<bool> undoExpense(String id) async {
    await ensureLoaded();

    final index = _transactions.indexWhere(
      (item) => item.id == id && item.isExpense,
    );
    if (index < 0) return false;

    _transactions.removeAt(index);
    await SyncTombstones.instance.add(SyncCollection.transactions, id);

    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
    notifyListeners();
    return true;
  }

  /// ادخار يدوي من الرصيد التشغيلي.
  Future<bool> saveManually(double amount) async {
    await ensureLoaded();

    if (amount <= 0 || amount > balance) {
      return false;
    }

    await _add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.savingsIn,
        amount: amount,
        note: 'ادخار يدوي',
        dateTime: DateTime.now(),
        transferKind: SavingsTransferKind.manual,
        goalId: activeGoal?.id,
      ),
    );

    return true;
  }

  /// سحب جزء أو كل المدخرات.
  Future<bool> withdrawFromSavings(double amount) async {
    await ensureLoaded();

    if (amount <= 0 || amount > savingsBalance) {
      return false;
    }

    await _add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.savingsOut,
        amount: amount,
        note: 'سحب إلى الرصيد',
        dateTime: DateTime.now(),
        transferKind: SavingsTransferKind.withdraw,
      ),
    );

    return true;
  }

  /// إنشاء هدف ادخار.
  ///
  /// الهدف الجديد يُضاف في نهاية القائمة (أقل أولوية).
  Future<bool> createGoal({
    required String name,
    required double targetAmount,
    required GoalDurationPreset duration,
    double? allocatePercent,
    double? allocateAmount,
    RecurringFrequency deductFrequency = RecurringFrequency.monthly,
    bool isPeriodic = false,
    int? durationCount,
  }) async {
    await ensureLoaded();

    if (name.trim().isEmpty || targetAmount <= 0) {
      return false;
    }

    final periodicAmount = allocateAmount ?? 0;

    if (isPeriodic) {
      if (periodicAmount <= 0) {
        return false;
      }

      if (deductFrequency == RecurringFrequency.none) {
        return false;
      }

      if (durationCount == null || durationCount <= 0) {
        return false;
      }
    }

    final now = DateTime.now();

    _goals.add(
      SavingsGoal(
        id: SavingsGoal.newId(),
        name: name.trim(),
        targetAmount: targetAmount,
        createdAt: now,
        duration: duration,
        allocatePercent: allocatePercent,
        allocateAmount: isPeriodic ? periodicAmount : null,
        deductFrequency: deductFrequency,
        isPeriodic: isPeriodic && periodicAmount > 0,
        durationCount: durationCount != null && durationCount > 0
            ? durationCount
            : null,
        priority: _goals.length,
      ),
    );

    _reindexPriorities();

    final prefs = await SharedPreferences.getInstance();

    await _persistGoals(prefs);

    notifyListeners();

    return true;
  }

  /// إنشاء / تعديل خطة دورية من شاشة الخطط الدورية.
  Future<bool> applyPeriodicPlan({
    required double percent,
    required GoalDurationPreset duration,
    required RecurringFrequency frequency,
    required double income,
  }) async {
    await ensureLoaded();

    if (percent <= 0 || income <= 0) {
      return false;
    }

    final cycles = duration.cycleCount(frequency);

    final perPeriod = income * percent / 100;

    if (perPeriod <= 0 || cycles <= 0) {
      return false;
    }

    final target = perPeriod * cycles;

    final existing = activeGoal;

    if (existing != null) {
      final index = _goals.indexWhere((goal) => goal.id == existing.id);

      if (index < 0) {
        return false;
      }

      _goals[index] = existing.copyWith(
        allocatePercent: percent,
        allocateAmount: perPeriod,
        deductFrequency: frequency,
        isPeriodic: true,
        durationCount: cycles,
        touch: true,
      );
    } else {
      _goals.add(
        SavingsGoal(
          id: SavingsGoal.newId(),
          name: 'ادخار ${percent.round()}٪',
          targetAmount: target,
          createdAt: DateTime.now(),
          duration: duration,
          allocatePercent: percent,
          allocateAmount: perPeriod,
          deductFrequency: frequency,
          isPeriodic: true,
          durationCount: cycles,
          priority: _goals.length,
        ),
      );
    }

    _reindexPriorities();

    final prefs = await SharedPreferences.getInstance();

    await _persistGoals(prefs);

    notifyListeners();

    return true;
  }

  /// حذف هدف بعد تأكيد المستخدم.
  /// المدخرات نفسها تبقى في الرصيد؛ يُحذف سجل الهدف فقط.
  Future<bool> deleteGoal(String id) async {
    await ensureLoaded();

    final index = _goals.indexWhere((goal) => goal.id == id);

    if (index < 0) {
      return false;
    }

    _goals.removeAt(index);
    await SyncTombstones.instance.add(SyncCollection.savingsGoals, id);
    _reindexPriorities();

    final prefs = await SharedPreferences.getInstance();

    await _persistGoals(prefs);

    notifyListeners();

    return true;
  }

  /// إعادة ترتيب الأهداف النشطة.
  /// [newIndex] هو الموقع النهائي بعد إزالة العنصر.
  Future<void> reorderActiveGoals(int oldIndex, int newIndex) async {
    await ensureLoaded();

    final active = activeGoals.toList();

    if (oldIndex < 0 || oldIndex >= active.length) {
      return;
    }

    if (newIndex < 0 || newIndex >= active.length) {
      return;
    }

    if (oldIndex == newIndex) {
      return;
    }

    final moved = active.removeAt(oldIndex);
    active.insert(newIndex, moved);

    var activeIndex = 0;
    for (var i = 0; i < _goals.length; i++) {
      if (_goals[i].isCompleted) {
        continue;
      }

      _goals[i] = active[activeIndex++];
    }

    _reindexPriorities();

    final prefs = await SharedPreferences.getInstance();

    await _persistGoals(prefs);

    notifyListeners();
  }

  Future<void> applyRemoteSync({
    required List<Map<String, dynamic>> transactions,
    required List<SyncTombstone> transactionDeletes,
    required List<Map<String, dynamic>> transfers,
    required List<SyncTombstone> transferDeletes,
    required List<Map<String, dynamic>> goals,
    required List<SyncTombstone> goalDeletes,
    Map<String, dynamic>? settings,
  }) async {
    await ensureLoaded();

    var changed = mergeRemoteRecords<WafferTransaction>(
      items: _transactions,
      upserts: [
        for (final raw in transactions)
          if (transactionFromSync(raw) != null) transactionFromSync(raw)!,
      ],
      deletes: transactionDeletes,
      collection: SyncCollection.transactions,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );

    changed |= mergeRemoteRecords<WafferTransaction>(
      items: _transactions,
      upserts: [
        for (final raw in transfers)
          if (transferFromSync(raw) != null) transferFromSync(raw)!,
      ],
      deletes: transferDeletes,
      collection: SyncCollection.savingsTransfers,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );

    changed |= mergeRemoteRecords<SavingsGoal>(
      items: _goals,
      upserts: [
        for (final raw in goals)
          if (goalFromSync(raw) != null) goalFromSync(raw)!,
      ],
      deletes: goalDeletes,
      collection: SyncCollection.savingsGoals,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );

    if (settings != null) {
      final keys = settings['processed_period_keys'];
      if (keys is List) {
        final before = _processedPeriods.length;
        _processedPeriods.addAll(keys.map((item) => item.toString()));
        if (_processedPeriods.length != before) changed = true;
      }

      final remoteUpdated = parseSyncDate(settings['updated_at']);
      final localUpdated = await SyncDirty.settingsUpdatedAt();
      if (newerOrEqual(remoteUpdated, localUpdated)) {
        if (settings.containsKey('monthly_income_amount')) {
          _monthlyIncomeOverride = parseMoney(settings['monthly_income_amount']);
        }
        if (settings.containsKey('weekly_income_amount')) {
          _weeklyIncomeOverride = parseMoney(settings['weekly_income_amount']);
        }
        if (remoteUpdated != null) {
          await SyncDirty.setSettingsUpdatedAt(remoteUpdated);
        }
        changed = true;
      }
    }

    if (!changed) return;

    _sort();
    _completeGoalIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    await _persistAll(prefs);
    notifyListeners();
  }

  /// إعادة تحميل البيانات من SharedPreferences.
  void resetCache() {
    _transactions.clear();
    _goals.clear();
    _processedPeriods.clear();
    _pendingExpenseSources.clear();
    _monthlyIncomeOverride = null;
    _weeklyIncomeOverride = null;

    _loaded = false;
    _loader = null;

    notifyListeners();
  }

  Future<WafferTransaction?> _createExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? note,
    String? sourceId,
  }) async {
    if (!canDeduct(amount)) {
      return null;
    }

    final transaction = WafferTransaction(
      id: WafferTransaction.newId(),
      type: TransactionType.expense,
      amount: amount,
      category: category,
      paymentMethod: paymentMethod,
      note: note,
      sourceId: sourceId,
      dateTime: DateTime.now(),
    );

    await _add(transaction);
    return transaction;
  }

  Future<void> processDuePeriods() async {
    await ensureLoaded();

    final prefs = await SharedPreferences.getInstance();

    final changed = await _processDuePeriods(prefs);

    if (changed) {
      notifyListeners();
    }
  }

  Future<void> _add(
    WafferTransaction transaction, {
    bool persist = true,
    bool notify = true,
  }) async {
    await ensureLoaded();

    _transactions.add(transaction);

    _sort();

    _completeGoalIfNeeded();

    if (persist) {
      final prefs = await SharedPreferences.getInstance();

      await _persistAll(prefs);
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final stored = prefs.getStringList(transactionsKey);

    _transactions.clear();
    _goals.clear();
    _processedPeriods.clear();

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

    final storedGoals = prefs.getStringList(savingsGoalsKey) ?? const [];

    var schemaNeedsWrite = false;

    if (storedGoals.isNotEmpty) {
      for (final raw in storedGoals) {
        final decoded = SavingsGoal.decode(raw);
        if (decoded == null) continue;
        _goals.add(decoded);
        if (!_encodedHasPriority(raw)) {
          schemaNeedsWrite = true;
        }
      }
    } else {
      final legacy = _loadLegacySingleGoal(prefs);
      if (legacy != null) {
        _goals.add(legacy);
        schemaNeedsWrite = true;
      }
    }

    if (_normalizeGoalPriorities() || schemaNeedsWrite) {
      await _persistGoals(prefs);
    }

    final storedPeriods = prefs.getStringList(processedPeriodsKey) ?? const [];

    _processedPeriods.addAll(storedPeriods);

    _monthlyIncomeOverride = prefs.getDouble(monthlyIncomeKey);
    _weeklyIncomeOverride = prefs.getDouble(weeklyIncomeKey);

    _loaded = true;

    if (onHydrated != null) {
      await onHydrated!();
    }

    await _processDuePeriods(prefs);

    notifyListeners();
  }

  Future<bool> _processDuePeriods(SharedPreferences prefs) async {
    if (_processingPeriods) {
      return false;
    }

    _processingPeriods = true;

    try {
      var changed = false;

      final now = DateTime.now();

      final periodicIds = [
        for (final goal in activeGoals)
          if (goal.isPeriodic &&
              goal.allocateAmount != null &&
              goal.allocateAmount! > 0 &&
              goal.deductFrequency != RecurringFrequency.none)
            goal.id,
      ];

      for (final goalId in periodicIds) {
        final initialGoal = _goalById(goalId);

        if (initialGoal == null || initialGoal.isCompleted) {
          continue;
        }

        final keys = CalendarPeriod.completedKeysSince(
          initialGoal.deductFrequency,
          initialGoal.createdAt,
          now,
        );

        final maxCycles = initialGoal.cyclesFor(initialGoal.deductFrequency);

        var processedGoalCycles = 0;

        for (final key in keys) {
          final goal = _goalById(goalId);

          if (goal == null || goal.isCompleted) {
            break;
          }

          if (processedGoalCycles >= maxCycles) {
            break;
          }

          final token = _goalPeriodToken(goal.id, key);

          if (_processedPeriods.contains(token)) {
            processedGoalCycles++;
            continue;
          }

          final deducted = _deductGoalForPeriod(goal, key);

          if (!deducted) {
            break;
          }

          _processedPeriods.add(token);
          changed = true;
          changed |= _completeGoalIfNeeded();
          processedGoalCycles++;
        }
      }

      // ==========================================
      // معالجة المتبقي من الفترات
      // ==========================================

      final leftoverKeys = <(RecurringFrequency, String)>{};

      for (final income in incomes) {
        if (income.frequency == RecurringFrequency.none) {
          continue;
        }

        final key = income.periodKey;

        if (key == null || key.isEmpty) {
          continue;
        }

        final period = CalendarPeriod.parseKey(key);

        if (period == null || !period.isComplete) {
          continue;
        }

        leftoverKeys.add((income.frequency, key));
      }

      final leftovers = leftoverKeys.toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));

      for (final entry in leftovers) {
        final token = _leftoverToken(entry.$2);

        if (_markProcessed(token)) {
          changed = true;

          changed |= _transferLeftover(entry.$1, entry.$2);
        }
      }

      changed |= _completeGoalIfNeeded();

      if (changed) {
        await _persistAll(prefs);
      }

      return changed;
    } finally {
      _processingPeriods = false;
    }
  }

  bool _deductGoalForPeriod(SavingsGoal goal, String periodKey) {
    if (goal.isCompleted) {
      return true;
    }

    final amount = goal.allocateAmount ?? 0;

    if (amount <= 0) {
      return true;
    }

    if (!canDeduct(amount)) {
      return false;
    }

    _transactions.add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.savingsIn,
        amount: amount,
        note: 'ادخار دوري: ${goal.name}',
        dateTime: DateTime.now(),
        transferKind: SavingsTransferKind.goalPeriodic,
        goalId: goal.id,
        processedPeriodKey: periodKey,
      ),
    );

    _sort();

    return true;
  }

  bool _transferLeftover(RecurringFrequency frequency, String periodKey) {
    final period = CalendarPeriod.parseKey(periodKey);

    if (period == null) {
      return false;
    }

    final periodIncome = _incomeForPeriod(frequency, periodKey);

    if (periodIncome <= 0) {
      return false;
    }

    final periodExpense = expenses
        .where((item) => period.contains(item.dateTime))
        .fold<double>(0, (sum, item) => sum + item.amount);

    final alreadySaved = _transactions
        .where(
          (item) =>
              item.isSavingsIn &&
              item.processedPeriodKey == periodKey &&
              item.transferKind == SavingsTransferKind.goalPeriodic,
        )
        .fold<double>(0, (sum, item) => sum + item.amount);

    var leftover = periodIncome - periodExpense - alreadySaved;

    if (leftover <= 0) {
      return false;
    }

    final available = balance;

    if (leftover > available) {
      leftover = available;
    }

    if (leftover <= 0) {
      return false;
    }

    _transactions.add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.savingsIn,
        amount: leftover,
        note: frequency == RecurringFrequency.weekly
            ? 'توفير نهاية الأسبوع'
            : 'توفير نهاية الشهر',
        dateTime: DateTime.now(),
        transferKind: SavingsTransferKind.periodLeftover,
        goalId: activeGoal?.id,
        processedPeriodKey: periodKey,
      ),
    );

    _sort();

    return true;
  }

  bool _completeGoalIfNeeded() {
    var changed = false;

    for (final goal in List<SavingsGoal>.from(activeGoals)) {
      final progress = goalProgress(goal);

      if (progress + 0.0001 < goal.targetAmount) {
        continue;
      }

      final index = _goals.indexWhere((item) => item.id == goal.id);

      if (index < 0) {
        continue;
      }

      _goals[index] = goal.copyWith(
        completedAt: DateTime.now(),
        completedAmount: progress > goal.targetAmount
            ? progress
            : goal.targetAmount,
        touch: true,
      );
      changed = true;
    }

    if (changed) {
      _reindexPriorities();
    }

    return changed;
  }

  bool _countsTowardGoal(WafferTransaction item, SavingsGoal goal) {
    if (!item.isSavingsIn && !item.isSavingsOut) {
      return false;
    }

    final taggedId = item.goalId;

    if (taggedId != null && taggedId.isNotEmpty) {
      return taggedId == goal.id;
    }

    return _legacyGoalIdFor(item.dateTime) == goal.id;
  }

  /// التحويلات القديمة بلا [WafferTransaction.goalId] تُنسب للهدف
  /// الأقدم الذي كان لا يزال غير مكتمل وقت التحويل.
  String? _legacyGoalIdFor(DateTime at) {
    SavingsGoal? best;

    for (final goal in _goals) {
      if (goal.createdAt.isAfter(at)) {
        continue;
      }

      if (goal.completedAt != null && !goal.completedAt!.isAfter(at)) {
        continue;
      }

      if (best == null || goal.createdAt.isBefore(best.createdAt)) {
        best = goal;
      }
    }

    return best?.id;
  }

  SavingsGoal? _goalById(String id) {
    for (final goal in _goals) {
      if (goal.id == id) {
        return goal;
      }
    }

    return null;
  }

  void _reindexPriorities() {
    for (var i = 0; i < _goals.length; i++) {
      if (_goals[i].priority != i) {
        _goals[i] = _goals[i].copyWith(priority: i);
      }
    }
  }

  /// يرتّب القائمة حسب [SavingsGoal.priority] مع الحفاظ على ترتيب
  /// التخزين عند تساوي القيمة (هدف قديم بلا حقل أولوية).
  bool _normalizeGoalPriorities() {
    if (_goals.isEmpty) {
      return false;
    }

    final original = List<SavingsGoal>.from(_goals);

    final indexed =
        [for (var i = 0; i < _goals.length; i++) (index: i, goal: _goals[i])]
          ..sort((a, b) {
            final byPriority = a.goal.priority.compareTo(b.goal.priority);
            if (byPriority != 0) return byPriority;
            return a.index.compareTo(b.index);
          });

    var changed = false;

    for (var i = 0; i < indexed.length; i++) {
      final next = indexed[i].goal.priority == i
          ? indexed[i].goal
          : indexed[i].goal.copyWith(priority: i);

      if (original[i].id != next.id || original[i].priority != next.priority) {
        changed = true;
      }

      _goals[i] = next;
    }

    return changed;
  }

  bool _encodedHasPriority(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded.containsKey('priority');
    } catch (_) {
      return false;
    }
  }

  SavingsGoal? _loadLegacySingleGoal(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(legacySavingsGoalKey);
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }

      final goal = SavingsGoal.decode(raw);
      if (goal == null) {
        return null;
      }

      return goal.copyWith(priority: 0);
    } catch (_) {
      return null;
    }
  }

  bool _markProcessed(String token) {
    return _processedPeriods.add(token);
  }

  String _leftoverToken(String periodKey) {
    return 'leftover:$periodKey';
  }

  String _goalPeriodToken(String goalId, String periodKey) {
    return 'goal:$goalId:$periodKey';
  }

  double _incomeForPeriod(RecurringFrequency frequency, String periodKey) {
    return incomes
        .where(
          (item) => item.frequency == frequency && item.periodKey == periodKey,
        )
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  double _incomeInCalendar(RecurringFrequency frequency, DateTime date) {
    final period = CalendarPeriod.ofFrequency(frequency, date);

    return incomes
        .where(
          (item) =>
              item.frequency == frequency && period.contains(item.dateTime),
        )
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setStringList(
      transactionsKey,
      _transactions.map((item) => item.encode()).toList(),
    );

    await prefs.setDouble(balanceKey, balance);

    await prefs.setDouble(maxBalanceKey, maxBalance);

    await prefs.setDouble(savingsBalanceKey, savingsBalance);

    await _persistIncomeOverrides(prefs);
    await SyncDirty.mark();
  }

  Future<void> _persistIncomeOverrides(SharedPreferences prefs) async {
    if (_monthlyIncomeOverride != null && _monthlyIncomeOverride! > 0) {
      await prefs.setDouble(monthlyIncomeKey, _monthlyIncomeOverride!);
    } else {
      await prefs.remove(monthlyIncomeKey);
    }

    if (_weeklyIncomeOverride != null && _weeklyIncomeOverride! > 0) {
      await prefs.setDouble(weeklyIncomeKey, _weeklyIncomeOverride!);
    } else {
      await prefs.remove(weeklyIncomeKey);
    }
  }

  void _setOverride(RecurringFrequency frequency, double amount) {
    if (frequency == RecurringFrequency.monthly) {
      _monthlyIncomeOverride = amount;
    } else if (frequency == RecurringFrequency.weekly) {
      _weeklyIncomeOverride = amount;
    }
  }

  double? _overrideFor(RecurringFrequency frequency) {
    return switch (frequency) {
      RecurringFrequency.monthly => _monthlyIncomeOverride,
      RecurringFrequency.weekly => _weeklyIncomeOverride,
      RecurringFrequency.none => null,
    };
  }

  Future<void> _persistGoals(SharedPreferences prefs) async {
    await prefs.setStringList(
      savingsGoalsKey,
      _goals.map((item) => item.encode()).toList(),
    );

    await prefs.setStringList(processedPeriodsKey, _processedPeriods.toList());
    await SyncDirty.mark();
  }

  Future<void> _persistAll(SharedPreferences prefs) async {
    await _persist(prefs);
    await _persistGoals(prefs);
  }

  List<WafferTransaction> _migrateLegacyExpenses(List<String>? legacy) {
    if (legacy == null || legacy.isEmpty) {
      return const [];
    }

    final migrated = <WafferTransaction>[];

    for (final entry in legacy) {
      final parts = entry.split('|');

      final amount = double.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;

      if (amount <= 0) {
        continue;
      }

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

  double _totalOf(TransactionType type) {
    return _transactions
        .where((item) => item.type == type)
        .fold<double>(0, (sum, item) => sum + item.amount);
  }
}
