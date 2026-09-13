import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/calendar_period.dart';
import 'package:waffer/core/data/savings_goal.dart';
import 'package:waffer/core/data/transaction.dart';

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
  static const String processedPeriodsKey = 'processed_periods';
  static const String savingsBalanceKey = 'savings_balance';

  /// التنسيق القديم:
  /// `amount|description|isoDate`.
  static const String legacyExpensesKey = 'expenses';

  final List<WafferTransaction> _transactions = [];
  final List<SavingsGoal> _goals = [];
  final Set<String> _processedPeriods = {};

  Future<void>? _loader;
  bool _loaded = false;
  bool _processingPeriods = false;

  /// بعد قراءة البيانات المحفوظة وقبل معالجة
  /// الفترات المستحقة.
  Future<void> Function()? onHydrated;

  bool get isLoaded => _loaded;

  Set<String> get processedPeriodTokens =>
      Set.unmodifiable(_processedPeriods);

  /// من الأحدث إلى الأقدم.
  List<WafferTransaction> get transactions =>
      List.unmodifiable(_transactions);

  List<WafferTransaction> get expenses => _transactions
      .where((item) => item.isExpense)
      .toList(growable: false);

  List<WafferTransaction> get incomes => _transactions
      .where((item) => item.isIncome)
      .toList(growable: false);

  List<WafferTransaction> get savingsTransfers => _transactions
      .where(
        (item) => item.isSavingsIn || item.isSavingsOut,
      )
      .toList(growable: false);

  List<SavingsGoal> get goals =>
      List.unmodifiable(_goals);

  SavingsGoal? get activeGoal {
    for (final goal in _goals) {
      if (!goal.isCompleted) {
        return goal;
      }
    }

    return null;
  }

  List<SavingsGoal> get completedGoals => _goals
      .where((goal) => goal.isCompleted)
      .toList(growable: false)
    ..sort(
      (a, b) => (b.completedAt ?? b.createdAt)
          .compareTo(a.completedAt ?? a.createdAt),
    );

  double get totalIncome =>
      _totalOf(TransactionType.income);

  double get totalExpense =>
      _totalOf(TransactionType.expense);

  double get totalSavingsIn =>
      _totalOf(TransactionType.savingsIn);

  double get totalSavingsOut =>
      _totalOf(TransactionType.savingsOut);

  /// المال الموجود حالياً في قسم الادخار.
  double get savingsBalance {
    final value =
        totalSavingsIn - totalSavingsOut;

    return value < 0 ? 0 : value;
  }

  /// الرصيد التشغيلي المتاح للصرف.
  /// لا يشمل المدخرات.
  double get balance {
    return totalIncome -
        totalExpense -
        savingsBalance;
  }

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
  List<({String category, double amount})>
      expensesByCategory() {
    final totals = <String, double>{};

    for (final expense in expenses) {
      final category =
          expense.category ?? 'أخرى';

      totals[category] =
          (totals[category] ?? 0) +
              expense.amount;
    }

    final entries = totals.entries
        .map(
          (entry) => (
            category: entry.key,
            amount: entry.value,
          ),
        )
        .toList();

    entries.sort(
      (a, b) => b.amount.compareTo(a.amount),
    );

    return entries;
  }

  /// صافي الادخار داخل فترة [start, end):
  /// ما دخل الادخار ناقص ما سُحب.
  double savingsNetDuring(
    DateTime start,
    DateTime end,
  ) {
    var incoming = 0.0;
    var outgoing = 0.0;

    for (final item in _transactions) {
      if (item.dateTime.isBefore(start) ||
          !item.dateTime.isBefore(end)) {
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

  /// تقدّم الهدف:
  /// فقط ما أُضيف إلى الادخار بعد إنشاء الهدف،
  /// ناقص ما سُحب بعد إنشائه.
  double goalProgress(SavingsGoal goal) {
    if (goal.isCompleted) {
      return goal.completedAmount ??
          goal.targetAmount;
    }

    var saved = 0.0;
    var withdrawn = 0.0;

    for (final item in _transactions) {
      if (item.dateTime.isBefore(
        goal.createdAt,
      )) {
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

    return (
      goalProgress(goal) /
          goal.targetAmount
    ).clamp(0.0, 1.0);
  }

  /// دخل الفترة الحالية أو السابقة حسب التردد.
  double referenceIncome(
    RecurringFrequency frequency,
  ) {
    if (frequency == RecurringFrequency.none) {
      return _incomeInCalendar(
        RecurringFrequency.monthly,
        DateTime.now(),
      );
    }

    final now = DateTime.now();

    final currentKey =
        CalendarPeriod.keyFor(
      frequency,
      now,
    );

    final current =
        _incomeForPeriod(
      frequency,
      currentKey,
    );

    if (current > 0) {
      return current;
    }

    final currentPeriod =
        CalendarPeriod.ofFrequency(
      frequency,
      now,
    );

    final previousStart =
        frequency == RecurringFrequency.weekly
            ? currentPeriod.start.subtract(
                const Duration(days: 7),
              )
            : DateTime(
                currentPeriod.start.year,
                currentPeriod.start.month - 1,
              );

    final previousKey =
        CalendarPeriod.keyFor(
      frequency,
      previousStart,
    );

    final previous =
        _incomeForPeriod(
      frequency,
      previousKey,
    );

    if (previous > 0) {
      return previous;
    }

    return _incomeInCalendar(
      frequency,
      now,
    );
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
      if (income.frequency ==
              RecurringFrequency.weekly ||
          income.frequency ==
              RecurringFrequency.monthly) {
        latestRecurringIncome = income;
        break;
      }
    }

    if (latestRecurringIncome != null) {
      return latestRecurringIncome.frequency;
    }

    final weekly =
        _incomeInCalendar(
      RecurringFrequency.weekly,
      DateTime.now(),
    );

    final monthly =
        _incomeInCalendar(
      RecurringFrequency.monthly,
      DateTime.now(),
    );

    if (weekly > 0 && monthly <= 0) {
      return RecurringFrequency.weekly;
    }

    return RecurringFrequency.monthly;
  }

  Future<void> ensureLoaded() =>
      _loader ??= _load();

  Future<void> addIncome({
    required double amount,
    String? source,
    RecurringFrequency frequency =
        RecurringFrequency.none,
    bool moveBalanceToSavings = false,
  }) async {
    await ensureLoaded();

    final currentBalance = balance;

    if (moveBalanceToSavings &&
        currentBalance > 0) {
      await _add(
        WafferTransaction(
          id: WafferTransaction.newId(),
          type: TransactionType.savingsIn,
          amount: currentBalance,
          note: 'نقل الرصيد الحالي إلى التوفير',
          dateTime: DateTime.now(),
          transferKind:
              SavingsTransferKind.manual,
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
        periodKey:
            frequency == RecurringFrequency.none
                ? null
                : CalendarPeriod.keyFor(
                    frequency,
                    now,
                  ),
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

  /// ادخار يدوي من الرصيد التشغيلي.
  Future<bool> saveManually(
    double amount,
  ) async {
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
        transferKind:
            SavingsTransferKind.manual,
        goalId: activeGoal?.id,
      ),
    );

    return true;
  }

  /// سحب جزء أو كل المدخرات.
  Future<bool> withdrawFromSavings(
    double amount,
  ) async {
    await ensureLoaded();

    if (amount <= 0 ||
        amount > savingsBalance) {
      return false;
    }

    await _add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.savingsOut,
        amount: amount,
        note: 'سحب إلى الرصيد',
        dateTime: DateTime.now(),
        transferKind:
            SavingsTransferKind.withdraw,
      ),
    );

    return true;
  }

  /// إنشاء هدف ادخار دوري.
  ///
  /// الهدف يستخدم نوع دخل المستخدم:
  /// Weekly أو Monthly.
  Future<bool> createGoal({
    required String name,
    required double targetAmount,
    required GoalDurationPreset duration,
    double? allocatePercent,
    double? allocateAmount,
    RecurringFrequency deductFrequency =
        RecurringFrequency.monthly,
    bool isPeriodic = false,
    int? durationCount,
  }) async {
    await ensureLoaded();

    /// لا يسمح بأكثر من هدف نشط.
    if (activeGoal != null) {
      return false;
    }

    if (name.trim().isEmpty ||
        targetAmount <= 0) {
      return false;
    }

    final periodicAmount =
        allocateAmount ?? 0;

    if (isPeriodic) {
      if (periodicAmount <= 0) {
        return false;
      }

      if (deductFrequency ==
          RecurringFrequency.none) {
        return false;
      }

      if (durationCount == null ||
          durationCount <= 0) {
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
        allocateAmount:
            isPeriodic
                ? periodicAmount
                : null,
        deductFrequency:
            deductFrequency,
        isPeriodic:
            isPeriodic &&
            periodicAmount > 0,
        durationCount:
            durationCount != null &&
                    durationCount > 0
                ? durationCount
                : null,
      ),
    );

    final prefs =
        await SharedPreferences.getInstance();

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

    final cycles =
        duration.cycleCount(frequency);

    final perPeriod =
        income * percent / 100;

    if (perPeriod <= 0 ||
        cycles <= 0) {
      return false;
    }

    final target =
        perPeriod * cycles;

    final existing = activeGoal;

    if (existing != null) {
      final index =
          _goals.indexWhere(
        (goal) => goal.id == existing.id,
      );

      if (index < 0) {
        return false;
      }

      _goals[index] =
          existing.copyWith(
        allocatePercent: percent,
        allocateAmount: perPeriod,
        deductFrequency: frequency,
        isPeriodic: true,
        durationCount: cycles,
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
        ),
      );
    }

    final prefs =
        await SharedPreferences.getInstance();

    await _persistGoals(prefs);

    notifyListeners();

    return true;
  }

  /// إعادة تحميل البيانات من SharedPreferences.
  void resetCache() {
    _transactions.clear();
    _goals.clear();
    _processedPeriods.clear();

    _loaded = false;
    _loader = null;

    notifyListeners();
  }

  Future<void> processDuePeriods() async {
    await ensureLoaded();

    final prefs =
        await SharedPreferences.getInstance();

    final changed =
        await _processDuePeriods(prefs);

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
      final prefs =
          await SharedPreferences.getInstance();

      await _persistAll(prefs);
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _load() async {
    final prefs =
        await SharedPreferences.getInstance();

    final stored =
        prefs.getStringList(
      transactionsKey,
    );

    _transactions.clear();
    _goals.clear();
    _processedPeriods.clear();

    if (stored != null) {
      _transactions.addAll(
        stored
            .map(WafferTransaction.decode)
            .whereType<WafferTransaction>(),
      );

      _sort();
    } else {
      _transactions.addAll(
        _migrateLegacyExpenses(
          prefs.getStringList(
            legacyExpensesKey,
          ),
        ),
      );

      _sort();

      if (_transactions.isNotEmpty) {
        await _persist(prefs);
      }
    }

    final storedGoals =
        prefs.getStringList(
          savingsGoalsKey,
        ) ??
        const [];

    _goals.addAll(
      storedGoals
          .map(SavingsGoal.decode)
          .whereType<SavingsGoal>(),
    );

    final storedPeriods =
        prefs.getStringList(
          processedPeriodsKey,
        ) ??
        const [];

    _processedPeriods.addAll(
      storedPeriods,
    );

    _loaded = true;

    if (onHydrated != null) {
      await onHydrated!();
    }

    await _processDuePeriods(prefs);

    notifyListeners();
  }

  Future<bool> _processDuePeriods(
    SharedPreferences prefs,
  ) async {
    if (_processingPeriods) {
      return false;
    }

    _processingPeriods = true;

    try {
      var changed = false;

      final now = DateTime.now();

      final initialGoal = activeGoal;

      // ==========================================
      // الاقتطاع الدوري للهدف
      // ==========================================

      if (initialGoal != null &&
          initialGoal.isPeriodic &&
          initialGoal.allocateAmount != null &&
          initialGoal.allocateAmount! > 0 &&
          initialGoal.deductFrequency !=
              RecurringFrequency.none) {
        final keys =
            CalendarPeriod.completedKeysSince(
          initialGoal.deductFrequency,
          initialGoal.createdAt,
          now,
        );

        final maxCycles =
            initialGoal.cyclesFor(
          initialGoal.deductFrequency,
        );

        var processedGoalCycles = 0;

        for (final key in keys) {
          final goal = activeGoal;

          if (goal == null ||
              goal.id != initialGoal.id ||
              goal.isCompleted) {
            break;
          }

          if (processedGoalCycles >=
              maxCycles) {
            break;
          }

          final token =
              _goalPeriodToken(
            goal.id,
            key,
          );

          if (_processedPeriods
              .contains(token)) {
            processedGoalCycles++;
            continue;
          }

          _processedPeriods.add(token);

          changed = true;

          changed |=
              _deductGoalForPeriod(
            goal,
            key,
          );

          changed |=
              _completeGoalIfNeeded();

          processedGoalCycles++;
        }
      }

      // ==========================================
      // معالجة المتبقي من الفترات
      // ==========================================

      final leftoverKeys =
          <(RecurringFrequency, String)>{};

      for (final income in incomes) {
        if (income.frequency ==
            RecurringFrequency.none) {
          continue;
        }

        final key = income.periodKey;

        if (key == null ||
            key.isEmpty) {
          continue;
        }

        final period =
            CalendarPeriod.parseKey(key);

        if (period == null ||
            !period.isComplete) {
          continue;
        }

        leftoverKeys.add(
          (income.frequency, key),
        );
      }

      final leftovers =
          leftoverKeys.toList()
            ..sort(
              (a, b) =>
                  a.$2.compareTo(b.$2),
            );

      for (final entry in leftovers) {
        final token =
            _leftoverToken(entry.$2);

        if (_markProcessed(token)) {
          changed = true;

          changed |=
              _transferLeftover(
            entry.$1,
            entry.$2,
          );
        }
      }

      changed |=
          _completeGoalIfNeeded();

      if (changed) {
        await _persistAll(prefs);
      }

      return changed;
    } finally {
      _processingPeriods = false;
    }
  }

  bool _deductGoalForPeriod(
    SavingsGoal goal,
    String periodKey,
  ) {
    if (goal.isCompleted) {
      return false;
    }

    final amount =
        goal.allocateAmount ?? 0;

    if (amount <= 0) {
      return false;
    }

    final available = balance;

    final transfer =
        amount < available
            ? amount
            : available;

    if (transfer <= 0) {
      return false;
    }

    _transactions.add(
      WafferTransaction(
        id: WafferTransaction.newId(),
        type: TransactionType.savingsIn,
        amount: transfer,
        note: 'ادخار دوري: ${goal.name}',
        dateTime: DateTime.now(),
        transferKind:
            SavingsTransferKind.goalPeriodic,
        goalId: goal.id,
        processedPeriodKey: periodKey,
      ),
    );

    _sort();

    return true;
  }

  bool _transferLeftover(
    RecurringFrequency frequency,
    String periodKey,
  ) {
    final period =
        CalendarPeriod.parseKey(
      periodKey,
    );

    if (period == null) {
      return false;
    }

    final periodIncome =
        _incomeForPeriod(
      frequency,
      periodKey,
    );

    if (periodIncome <= 0) {
      return false;
    }

    final periodExpense = expenses
        .where(
          (item) =>
              period.contains(
            item.dateTime,
          ),
        )
        .fold<double>(
          0,
          (sum, item) =>
              sum + item.amount,
        );

    final alreadySaved =
        _transactions
            .where(
              (item) =>
                  item.isSavingsIn &&
                  item.processedPeriodKey ==
                      periodKey &&
                  item.transferKind ==
                      SavingsTransferKind
                          .goalPeriodic,
            )
            .fold<double>(
              0,
              (sum, item) =>
                  sum + item.amount,
            );

    var leftover =
        periodIncome -
            periodExpense -
            alreadySaved;

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
        note:
            frequency ==
                    RecurringFrequency.weekly
                ? 'توفير نهاية الأسبوع'
                : 'توفير نهاية الشهر',
        dateTime: DateTime.now(),
        transferKind:
            SavingsTransferKind.periodLeftover,
        goalId: activeGoal?.id,
        processedPeriodKey: periodKey,
      ),
    );

    _sort();

    return true;
  }

  bool _completeGoalIfNeeded() {
    final goal = activeGoal;

    if (goal == null) {
      return false;
    }

    final progress =
        goalProgress(goal);

    if (progress + 0.0001 <
        goal.targetAmount) {
      return false;
    }

    final index =
        _goals.indexWhere(
      (item) => item.id == goal.id,
    );

    if (index < 0) {
      return false;
    }

    _goals[index] =
        goal.copyWith(
      completedAt: DateTime.now(),
      completedAmount:
          progress > goal.targetAmount
              ? progress
              : goal.targetAmount,
    );

    return true;
  }

  bool _markProcessed(String token) {
    return _processedPeriods.add(token);
  }

  String _leftoverToken(
    String periodKey,
  ) {
    return 'leftover:$periodKey';
  }

  String _goalPeriodToken(
    String goalId,
    String periodKey,
  ) {
    return 'goal:$goalId:$periodKey';
  }

  double _incomeForPeriod(
    RecurringFrequency frequency,
    String periodKey,
  ) {
    return incomes
        .where(
          (item) =>
              item.frequency == frequency &&
              item.periodKey == periodKey,
        )
        .fold<double>(
          0,
          (sum, item) =>
              sum + item.amount,
        );
  }

  double _incomeInCalendar(
    RecurringFrequency frequency,
    DateTime date,
  ) {
    final period =
        CalendarPeriod.ofFrequency(
      frequency,
      date,
    );

    return incomes
        .where(
          (item) =>
              item.frequency == frequency &&
              period.contains(
                item.dateTime,
              ),
        )
        .fold<double>(
          0,
          (sum, item) =>
              sum + item.amount,
        );
  }

  Future<void> _persist(
    SharedPreferences prefs,
  ) async {
    await prefs.setStringList(
      transactionsKey,
      _transactions
          .map((item) => item.encode())
          .toList(),
    );

    await prefs.setDouble(
      balanceKey,
      balance,
    );

    await prefs.setDouble(
      maxBalanceKey,
      maxBalance,
    );

    await prefs.setDouble(
      savingsBalanceKey,
      savingsBalance,
    );
  }

  Future<void> _persistGoals(
    SharedPreferences prefs,
  ) async {
    await prefs.setStringList(
      savingsGoalsKey,
      _goals
          .map((item) => item.encode())
          .toList(),
    );

    await prefs.setStringList(
      processedPeriodsKey,
      _processedPeriods.toList(),
    );
  }

  Future<void> _persistAll(
    SharedPreferences prefs,
  ) async {
    await _persist(prefs);
    await _persistGoals(prefs);
  }

  List<WafferTransaction>
      _migrateLegacyExpenses(
    List<String>? legacy,
  ) {
    if (legacy == null ||
        legacy.isEmpty) {
      return const [];
    }

    final migrated =
        <WafferTransaction>[];

    for (final entry in legacy) {
      final parts = entry.split('|');

      final amount =
          double.tryParse(
                parts.isNotEmpty
                    ? parts[0]
                    : '',
              ) ??
              0;

      if (amount <= 0) {
        continue;
      }

      final note =
          parts.length > 1 &&
                  parts[1].trim().isNotEmpty
              ? parts[1].trim()
              : null;

      final date =
          parts.length > 2
              ? DateTime.tryParse(parts[2])
              : null;

      migrated.add(
        WafferTransaction(
          id:
              WafferTransaction.newId() +
                  migrated.length.toString(),
          type: TransactionType.expense,
          amount: amount,
          category: 'أخرى',
          note: note,
          dateTime:
              date ?? DateTime.now(),
        ),
      );
    }

    return migrated;
  }

  void _sort() {
    _transactions.sort(
      (a, b) =>
          b.dateTime.compareTo(
        a.dateTime,
      ),
    );
  }

  double _totalOf(
    TransactionType type,
  ) {
    return _transactions
        .where(
          (item) => item.type == type,
        )
        .fold<double>(
          0,
          (sum, item) =>
              sum + item.amount,
        );
  }
}