// Sole source of truth for transactions, operating balance, and savings goals.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/models/savings_goal.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/core/sync/profile_sync.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/core/sync/sync_dirty.dart';
import 'package:waffr/core/sync/sync_mapper.dart';
import 'package:waffr/core/sync/sync_merge.dart';
import 'package:waffr/core/sync/sync_tombstones.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

// Ledger in prefs as JSON. Operating balance is always income − expense − net savings.
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
  static const String incomeOverridesByCurrencyKey =
      'income_overrides_by_currency';

  // Pre-JSON expense rows: amount|description|isoDate.
  static const String legacyExpensesKey = 'expenses';

  final List<WaffrTransaction> _transactions = [];
  final List<SavingsGoal> _goals = [];
  final Set<String> _processedPeriods = {};
  final Map<String, Future<WaffrTransaction?>> _pendingExpenseSources = {};

  Future<void>? _loader;
  bool _loaded = false;
  bool _processingPeriods = false;
  bool _listeningToCurrency = false;
  final Map<String, double> _monthlyIncomeByCurrency = {};
  final Map<String, double> _weeklyIncomeByCurrency = {};

  // Hook after prefs hydrate, before due-period processing.
  Future<void> Function()? onHydrated;

  bool get isLoaded => _loaded;

  Set<String> get processedPeriodTokens => Set.unmodifiable(_processedPeriods);

  String get _activeCode => CurrencyStore.instance.activeCode;

  double? get monthlyIncomeOverride => monthlyIncomeOverrideFor(_activeCode);

  double? get weeklyIncomeOverride => weeklyIncomeOverrideFor(_activeCode);

  double? monthlyIncomeOverrideFor(String currencyCode) {
    return _monthlyIncomeByCurrency[Currencies.normalize(currencyCode)];
  }

  double? weeklyIncomeOverrideFor(String currencyCode) {
    return _weeklyIncomeByCurrency[Currencies.normalize(currencyCode)];
  }

  Object? get incomeOverridesByCurrencyPayload {
    final encoded = _encodeIncomeOverrides();
    if (encoded == null) return null;
    try {
      return jsonDecode(encoded);
    } catch (_) {
      return null;
    }
  }

  // Newest first.
  List<WaffrTransaction> get transactions => List.unmodifiable(_transactions);

  List<WaffrTransaction> get expenses => expensesFor(_activeCode);

  List<WaffrTransaction> get incomes => incomesFor(_activeCode);

  List<WaffrTransaction> get savingsTransfers =>
      savingsTransfersFor(_activeCode);

  List<WaffrTransaction> expensesFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return _transactions
        .where((item) => item.isExpense && item.currencyCode == code)
        .toList(growable: false);
  }

  List<WaffrTransaction> incomesFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return _transactions
        .where((item) => item.isIncome && item.currencyCode == code)
        .toList(growable: false);
  }

  List<WaffrTransaction> savingsTransfersFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return _transactions
        .where(
          (item) =>
              (item.isSavingsIn || item.isSavingsOut) &&
              item.currencyCode == code,
        )
        .toList(growable: false);
  }

  List<SavingsGoal> get goals => List.unmodifiable(_goals);

  // Incomplete goals for the active currency, priority order (0 = top).
  List<SavingsGoal> get activeGoals => activeGoalsFor(_activeCode);

  List<SavingsGoal> activeGoalsFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return _goals
        .where((goal) => !goal.isCompleted && goal.currencyCode == code)
        .toList(growable: false);
  }

  List<SavingsGoal> get _allActiveGoals =>
      _goals.where((goal) => !goal.isCompleted).toList(growable: false);

  SavingsGoal? get activeGoal {
    final current = activeGoals;
    return current.isEmpty ? null : current.first;
  }

  // Highest-priority active goal that has a periodic deduction plan.
  SavingsGoal? get activePeriodicGoal {
    for (final goal in activeGoals) {
      if (goal.isPeriodic) return goal;
    }
    return null;
  }

  bool get hasActivePeriodicPlan => activePeriodicGoal != null;

  List<SavingsGoal> get completedGoals => completedGoalsFor(_activeCode);

  List<SavingsGoal> completedGoalsFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return _goals.where((goal) => goal.isCompleted && goal.currencyCode == code)
        .toList(growable: false)
      ..sort(
        (a, b) => (b.completedAt ?? b.createdAt).compareTo(
          a.completedAt ?? a.createdAt,
        ),
      );
  }

  double get totalIncome => totalIncomeFor(_activeCode);

  double get totalExpense => totalExpenseFor(_activeCode);

  double get totalSavingsIn => totalSavingsInFor(_activeCode);

  double get totalSavingsOut => totalSavingsOutFor(_activeCode);

  double totalIncomeFor(String currencyCode) =>
      _totalOf(TransactionType.income, currencyCode);

  double totalExpenseFor(String currencyCode) =>
      _totalOf(TransactionType.expense, currencyCode);

  double totalSavingsInFor(String currencyCode) =>
      _totalOf(TransactionType.savingsIn, currencyCode);

  double totalSavingsOutFor(String currencyCode) =>
      _totalOf(TransactionType.savingsOut, currencyCode);

  // Cash currently parked in savings (in − out, floored at 0).
  double get savingsBalance => savingsBalanceFor(_activeCode);

  double savingsBalanceFor(String currencyCode) {
    final value =
        totalSavingsInFor(currencyCode) - totalSavingsOutFor(currencyCode);

    return value < 0 ? 0 : value;
  }

  // Spendable operating balance; excludes money already moved to savings.
  double get balance => balanceFor(_activeCode);

  double balanceFor(String currencyCode) {
    return totalIncomeFor(currencyCode) -
        totalExpenseFor(currencyCode) -
        savingsBalanceFor(currencyCode);
  }

  // True when [amount] fits without going negative.
  bool canDeduct(double amount, {String? currencyCode}) {
    final code = Currencies.normalize(currencyCode ?? _activeCode);
    return amount > 0 && amount <= balanceFor(code);
  }

  bool get hasMonthlyIncome => hasMonthlyIncomeFor(_activeCode);

  bool hasMonthlyIncomeFor(String currencyCode) {
    final override = monthlyIncomeOverrideFor(currencyCode);
    if (override != null && override > 0) {
      return true;
    }

    return incomesFor(currencyCode).any(
      (item) => item.frequency == RecurringFrequency.monthly,
    );
  }

  // Settings override only — independent of whether income rows exist.
  bool get hasConfiguredMonthlyIncome =>
      hasConfiguredMonthlyIncomeFor(_activeCode);

  bool hasConfiguredMonthlyIncomeFor(String currencyCode) {
    final amount = monthlyIncomeOverrideFor(currencyCode);
    return amount != null && amount > 0;
  }

  double? get configuredMonthlyIncome =>
      configuredMonthlyIncomeFor(_activeCode);

  double? configuredMonthlyIncomeFor(String currencyCode) {
    return hasConfiguredMonthlyIncomeFor(currencyCode)
        ? monthlyIncomeOverrideFor(currencyCode)
        : null;
  }

  bool get hasWeeklyIncome => hasWeeklyIncomeFor(_activeCode);

  bool hasWeeklyIncomeFor(String currencyCode) {
    final override = weeklyIncomeOverrideFor(currencyCode);
    if (override != null && override > 0) {
      return true;
    }

    return incomesFor(currencyCode).any(
      (item) => item.frequency == RecurringFrequency.weekly,
    );
  }

  bool get hasRecurringIncome => hasMonthlyIncome || hasWeeklyIncome;

  // ---------------------------------------------------------------------
  // Balance cycle: the 100% the home bar measures against. A new cycle
  // starts when leftover balance is moved to savings with a new income, and
  // at the start of every month when the income is monthly.
  // ---------------------------------------------------------------------

  /// processedPeriodKey on the transfer that moves leftover balance to
  /// savings while adding a new income.
  static const String carryOverKey = 'carry';
  static const String _carryOverNote = 'نقل الرصيد الحالي إلى التوفير';

  bool _isCarryOver(WaffrTransaction item) =>
      item.isSavingsIn &&
      (item.processedPeriodKey == carryOverKey ||
          (item.transferKind == SavingsTransferKind.manual &&
              item.note == _carryOverNote));

  // Transfers that close a cycle rather than spend from it.
  bool _closesCycle(WaffrTransaction item) =>
      _isCarryOver(item) ||
      (item.isSavingsIn &&
          item.transferKind == SavingsTransferKind.periodLeftover);

  /// Start of the current balance cycle, or null before the first reset.
  ///
  /// A new cycle starts when income arrives on an empty balance (all of it
  /// spent, or the leftover just moved to savings), and at the start of
  /// every month when the income is monthly.
  DateTime? cycleStartFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    // Monthly income also restarts the cycle on the 1st, so the month and
    // the income frequency are part of the cache key.
    final key = '$code|${preferredIncomeFrequencyFor(code).name}|'
        '${CalendarPeriod.monthStart(deviceNow()).millisecondsSinceEpoch}';
    if (_cycleStarts.containsKey(key)) return _cycleStarts[key];
    return _cycleStarts[key] = _computeCycleStart(code);
  }

  DateTime? _computeCycleStart(String code) {
    final rows = _transactions
        .where((item) => item.currencyCode == code)
        .toList()
      ..sort((a, b) {
        final byTime = a.dateTime.compareTo(b.dateTime);
        if (byTime != 0) return byTime;
        // Same moment: the carry-over transfer comes before its income.
        return (a.isIncome ? 1 : 0).compareTo(b.isIncome ? 1 : 0);
      });

    DateTime? start;
    var running = 0.0;
    var saved = 0.0;
    for (final item in rows) {
      if (item.isIncome && running <= _cycleEpsilon) start = item.dateTime;
      if (item.isIncome) running += item.amount;
      if (item.isExpense) running -= item.amount;
      if (item.isSavingsIn) {
        running -= item.amount;
        saved += item.amount;
      }
      if (item.isSavingsOut) {
        // Withdrawals return at most what is in savings, like balanceFor.
        final back = item.amount < saved ? item.amount : saved;
        running += back;
        saved -= back;
      }
      if (_isCarryOver(item) && (start == null || item.dateTime.isAfter(start))) {
        start = item.dateTime;
      }
    }

    if (preferredIncomeFrequencyFor(code) == RecurringFrequency.monthly) {
      final monthStart = CalendarPeriod.monthStart(deviceNow());
      if (start == null || monthStart.isAfter(start)) start = monthStart;
    }
    return start;
  }

  static const double _cycleEpsilon = 0.005;

  bool _inCycle(WaffrTransaction item, DateTime? start) =>
      start == null || !item.dateTime.isBefore(start);

  /// Expenses recorded in the current cycle.
  double cycleSpentFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    final start = cycleStartFor(code);
    var total = 0.0;
    for (final item in _transactions) {
      if (item.currencyCode == code && item.isExpense && _inCycle(item, start)) {
        total += item.amount;
      }
    }
    return total;
  }

  double get cycleSpent => cycleSpentFor(_activeCode);

  /// The cycle's 100%: what the balance would be now if nothing had been
  /// spent or saved since the cycle started.
  double get maxBalance => maxBalanceFor(_activeCode);

  double maxBalanceFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    final start = cycleStartFor(code);
    var used = 0.0;
    for (final item in _transactions) {
      if (item.currencyCode != code || !_inCycle(item, start)) continue;
      if (_closesCycle(item)) continue;
      if (item.isExpense || item.isSavingsIn) used += item.amount;
      if (item.isSavingsOut) used -= item.amount;
    }
    final capacity = balanceFor(code) + used;
    return capacity > 0 ? capacity : 0;
  }

  /// Stable id of the current cycle, for one-alert-per-cycle notifications.
  String get cycleKey => cycleKeyFor(_activeCode);

  String cycleKeyFor(String currencyCode) {
    final start = cycleStartFor(currencyCode);
    return '${start?.millisecondsSinceEpoch ?? 0}';
  }

  double get remainingRatio => remainingRatioFor(_activeCode);

  double remainingRatioFor(String currencyCode) {
    final max = maxBalanceFor(currencyCode);

    if (max <= 0) {
      return 0;
    }

    return (balanceFor(currencyCode) / max).clamp(0.0, 1.0);
  }

  // Expense totals by category, largest first.
  List<({String category, double amount})> expensesByCategory({
    String? currencyCode,
  }) {
    final code = Currencies.normalize(currencyCode ?? _activeCode);
    final totals = <String, double>{};

    for (final expense in expensesFor(code)) {
      final category = expense.category ?? 'أخرى';

      totals[category] = (totals[category] ?? 0) + expense.amount;
    }

    final entries = totals.entries
        .map((entry) => (category: entry.key, amount: entry.value))
        .toList();

    entries.sort((a, b) => b.amount.compareTo(a.amount));

    return entries;
  }

  // Net savings inside [start, end): in minus out, floored at 0.
  double savingsNetDuring(
    DateTime start,
    DateTime end, {
    String? currencyCode,
  }) {
    final code = Currencies.normalize(currencyCode ?? _activeCode);
    var incoming = 0.0;
    var outgoing = 0.0;

    for (final item in _transactions) {
      if (item.currencyCode != code) {
        continue;
      }
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

  double currentSaved(SavingsGoal goal) => goalProgress(goal);

  // Progress from tagged transfers plus legacy untagged ones attributed by date.
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

  // Income used for plans: settings override, else current/previous period, else calendar sum.
  double referenceIncome(
    RecurringFrequency frequency, {
    String? currencyCode,
  }) {
    final code = Currencies.normalize(currencyCode ?? _activeCode);
    final override = _overrideFor(frequency, code);
    if (override != null && override > 0) {
      return override;
    }

    if (frequency == RecurringFrequency.none) {
      return _incomeInCalendar(RecurringFrequency.monthly, deviceNow(), code);
    }

    final now = deviceNow();

    final currentKey = CalendarPeriod.keyFor(frequency, now);

    final current = _incomeForPeriod(frequency, currentKey, code);

    if (current > 0) {
      return current;
    }

    final currentPeriod = CalendarPeriod.ofFrequency(frequency, now);

    final previousStart = frequency == RecurringFrequency.weekly
        ? currentPeriod.start.subtract(const Duration(days: 7))
        : DateTime(currentPeriod.start.year, currentPeriod.start.month - 1);

    final previousKey = CalendarPeriod.keyFor(frequency, previousStart);

    final previous = _incomeForPeriod(frequency, previousKey, code);

    if (previous > 0) {
      return previous;
    }

    return _incomeInCalendar(frequency, now, code);
  }

  // Weekly vs monthly plan cadence from the latest recurring income row.
  RecurringFrequency preferredIncomeFrequencyFor(String currencyCode) {
    WaffrTransaction? latestRecurringIncome;

    for (final income in incomesFor(currencyCode)) {
      if (income.frequency == RecurringFrequency.weekly ||
          income.frequency == RecurringFrequency.monthly) {
        latestRecurringIncome = income;
        break;
      }
    }

    if (latestRecurringIncome != null) {
      return latestRecurringIncome.frequency;
    }

    final weekly = _incomeInCalendar(
      RecurringFrequency.weekly,
      deviceNow(),
      currencyCode,
    );

    final monthly = _incomeInCalendar(
      RecurringFrequency.monthly,
      deviceNow(),
      currencyCode,
    );

    if (weekly > 0 && monthly <= 0) {
      return RecurringFrequency.weekly;
    }

    return RecurringFrequency.monthly;
  }

  RecurringFrequency get preferredIncomeFrequency =>
      preferredIncomeFrequencyFor(_activeCode);

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> addIncome({
    required double amount,
    String? source,
    RecurringFrequency frequency = RecurringFrequency.none,
    bool moveBalanceToSavings = false,
    String? currencyCode,
  }) async {
    await ensureLoaded();

    final code = Currencies.normalize(currencyCode ?? _activeCode);
    final currentBalance = balanceFor(code);
    final currentGoal = activeGoalsFor(code).isEmpty
        ? null
        : activeGoalsFor(code).first;

    if (moveBalanceToSavings && currentBalance > 0) {
      await _add(
        WaffrTransaction(
          id: WaffrTransaction.newId(),
          type: TransactionType.savingsIn,
          amount: currentBalance,
          currencyCode: code,
          note: _carryOverNote,
          dateTime: deviceNow(),
          transferKind: SavingsTransferKind.manual,
          goalId: currentGoal?.id,
          processedPeriodKey: carryOverKey,
        ),
        persist: false,
        notify: false,
      );
    }

    final now = deviceNow();

    await _add(
      WaffrTransaction(
        id: WaffrTransaction.newId(),
        type: TransactionType.income,
        amount: amount,
        currencyCode: code,
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
      _setOverride(frequency, amount, code);
    }

    final prefs = await AppPrefs.instance;
    await _persistAll(prefs);
    notifyListeners();
  }

  // Updates the planned income figure without posting a new balance-changing row.
  Future<bool> setPreferredIncomeAmount({
    required RecurringFrequency frequency,
    required double amount,
    String? currencyCode,
  }) async {
    await ensureLoaded();

    if (!amount.isFinite || amount <= 0) {
      return false;
    }

    if (frequency != RecurringFrequency.monthly &&
        frequency != RecurringFrequency.weekly) {
      return false;
    }

    final code = Currencies.normalize(currencyCode ?? _activeCode);
    _setOverride(frequency, amount, code);
    await SyncDirty.mark(settings: true);
    final goalsChanged = _syncPeriodicGoalAmounts(frequency, amount, code);

    final prefs = await AppPrefs.instance;
    await _persistIncomeOverrides(prefs);
    if (goalsChanged) {
      await _persistGoals(prefs);
    }

    // Yield so Home/Report/Savings keep-alive tabs settle after the dialog closes.
    await Future<void>.delayed(Duration.zero);
    notifyListeners();

    return true;
  }

  // Clears the settings override without deleting historical income rows.
  Future<bool> clearPreferredIncomeAmount({
    required RecurringFrequency frequency,
    String? currencyCode,
  }) async {
    await ensureLoaded();

    if (frequency != RecurringFrequency.monthly &&
        frequency != RecurringFrequency.weekly) {
      return false;
    }

    _clearOverride(frequency, Currencies.normalize(currencyCode ?? _activeCode));
    await SyncDirty.mark(settings: true);

    final prefs = await AppPrefs.instance;
    await _persistIncomeOverrides(prefs);
    await Future<void>.delayed(Duration.zero);
    notifyListeners();
    return true;
  }

  // Keeps a periodic contribution from exceeding the reference salary.
  double _capToIncome(double amount, double income) {
    if (!amount.isFinite || amount <= 0) return 0;
    if (income > 0 && amount > income) return income;
    return amount;
  }

  // Recomputes allocateAmount on percent-based periodic goals for this income.
  bool _syncPeriodicGoalAmounts(
    RecurringFrequency frequency,
    double income,
    String currencyCode,
  ) {
    var changed = false;
    final code = Currencies.normalize(currencyCode);

    for (var i = 0; i < _goals.length; i++) {
      final goal = _goals[i];
      if (goal.isCompleted || !goal.isPeriodic) continue;
      if (goal.currencyCode != code) continue;
      if (goal.deductFrequency != frequency) continue;

      final percent = goal.allocatePercent;
      if (percent == null || percent <= 0) continue;

      final cappedPercent = percent.clamp(0, 100).toDouble();
      final perPeriod = _capToIncome(income * cappedPercent / 100, income);
      if (!perPeriod.isFinite || perPeriod <= 0) continue;
      if (perPeriod == goal.allocateAmount && cappedPercent == percent) {
        continue;
      }

      _goals[i] = goal.copyWith(
        allocatePercent: cappedPercent,
        allocateAmount: perPeriod,
        touch: true,
      );
      changed = true;
    }

    return changed;
  }

  // Returns the expense on success, or null when amount exceeds balance.
  Future<WaffrTransaction?> addExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? note,
    String? sourceId,
    DateTime? occurredAt,
    String? currencyCode,
  }) async {
    await ensureLoaded();

    final code = Currencies.normalize(currencyCode ?? _activeCode);

    if (sourceId != null) {
      for (final item in _transactions) {
        if (item.isExpense && item.sourceId == sourceId) {
          return item;
        }
      }

      final pending = _pendingExpenseSources[sourceId];
      if (pending != null) {
        return pending;
      }
    }

    if (!canDeduct(amount, currencyCode: code)) {
      return null;
    }

    final future = _createExpense(
      amount: amount,
      category: category,
      paymentMethod: paymentMethod,
      note: note,
      sourceId: sourceId,
      occurredAt: occurredAt,
      currencyCode: code,
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

  // Removes an expense so its amount returns to the operating balance.
  Future<bool> undoExpense(String id) async {
    await ensureLoaded();

    final index = _transactions.indexWhere(
      (item) => item.id == id && item.isExpense,
    );
    if (index < 0) return false;

    _transactions.removeAt(index);
    _touch();
    await SyncTombstones.instance.add(SyncCollection.transactions, id);

    final prefs = await AppPrefs.instance;
    await _persist(prefs);
    notifyListeners();
    return true;
  }

  // Removes an income row and drops that amount from the balance.
  Future<bool> undoIncome(String id) async {
    await ensureLoaded();

    final index = _transactions.indexWhere(
      (item) => item.id == id && item.isIncome,
    );
    if (index < 0) return false;

    _transactions.removeAt(index);
    _touch();
    await SyncTombstones.instance.add(SyncCollection.transactions, id);

    final prefs = await AppPrefs.instance;
    await _persist(prefs);
    notifyListeners();
    return true;
  }

  // Manual move from operating balance into savings (tags top active goal).
  Future<bool> saveManually(double amount, {String? currencyCode}) async {
    await ensureLoaded();

    final code = Currencies.normalize(currencyCode ?? _activeCode);
    if (amount <= 0 || amount > balanceFor(code)) {
      return false;
    }

    final currentGoal = activeGoalsFor(code).isEmpty
        ? null
        : activeGoalsFor(code).first;

    await _add(
      WaffrTransaction(
        id: WaffrTransaction.newId(),
        type: TransactionType.savingsIn,
        amount: amount,
        currencyCode: code,
        note: 'توفير يدوي',
        dateTime: deviceNow(),
        transferKind: SavingsTransferKind.manual,
        goalId: currentGoal?.id,
      ),
    );

    return true;
  }

  // Moves money from savings back to operating balance.
  Future<bool> withdrawFromSavings(double amount, {String? currencyCode}) async {
    await ensureLoaded();

    final code = Currencies.normalize(currencyCode ?? _activeCode);
    if (amount <= 0 || amount > savingsBalanceFor(code)) {
      return false;
    }

    await _add(
      WaffrTransaction(
        id: WaffrTransaction.newId(),
        type: TransactionType.savingsOut,
        amount: amount,
        currencyCode: code,
        note: 'سحب إلى الرصيد',
        dateTime: deviceNow(),
        transferKind: SavingsTransferKind.withdraw,
      ),
    );

    return true;
  }

  // Appends a new goal at the end of the list (lowest priority).
  Future<bool> createGoal({
    required String name,
    required double targetAmount,
    required GoalDurationPreset duration,
    double? allocatePercent,
    double? allocateAmount,
    RecurringFrequency deductFrequency = RecurringFrequency.monthly,
    bool isPeriodic = false,
    int? durationCount,
    String? currencyCode,
  }) async {
    await ensureLoaded();

    if (name.trim().isEmpty || targetAmount <= 0) {
      return false;
    }

    final now = deviceNow();
    final code = Currencies.normalize(currencyCode ?? _activeCode);
    final reference = deductFrequency == RecurringFrequency.none
        ? 0.0
        : referenceIncome(deductFrequency, currencyCode: code);
    final cappedPercent = allocatePercent?.clamp(0, 100).toDouble();
    final periodicAmount = _capToIncome(allocateAmount ?? 0, reference);

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

    _goals.add(
      SavingsGoal(
        id: SavingsGoal.newId(),
        name: name.trim(),
        targetAmount: targetAmount,
        currencyCode: code,
        createdAt: now,
        duration: duration,
        allocatePercent: cappedPercent,
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

    final prefs = await AppPrefs.instance;

    await _persistGoals(prefs);

    notifyListeners();

    return true;
  }

  // Creates or updates the top active periodic plan from the plans screen.
  Future<bool> applyPeriodicPlan({
    required double percent,
    required GoalDurationPreset duration,
    required RecurringFrequency frequency,
    required double income,
    String? currencyCode,
  }) async {
    await ensureLoaded();

    if (percent <= 0 || income <= 0) {
      return false;
    }

    final code = Currencies.normalize(currencyCode ?? _activeCode);
    final cycles = duration.cycleCount(frequency);

    final cappedPercent = percent.clamp(0, 100).toDouble();
    final perPeriod = _capToIncome(income * cappedPercent / 100, income);

    if (perPeriod <= 0 || cycles <= 0) {
      return false;
    }

    final target = perPeriod * cycles;

    final existing = activeGoalsFor(code).isEmpty
        ? null
        : activeGoalsFor(code).first;

    if (existing != null) {
      final index = _goals.indexWhere((goal) => goal.id == existing.id);

      if (index < 0) {
        return false;
      }

      _goals[index] = existing.copyWith(
        allocatePercent: cappedPercent,
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
          name: 'توفير ${cappedPercent.round()}٪',
          targetAmount: target,
          currencyCode: code,
          createdAt: deviceNow(),
          duration: duration,
          allocatePercent: cappedPercent,
          allocateAmount: perPeriod,
          deductFrequency: frequency,
          isPeriodic: true,
          durationCount: cycles,
          priority: _goals.length,
        ),
      );
    }

    _reindexPriorities();

    final prefs = await AppPrefs.instance;

    await _persistGoals(prefs);

    notifyListeners();

    return true;
  }

  // Deletes the goal record only; savings cash stays in the savings balance.
  Future<bool> deleteGoal(String id) async {
    await ensureLoaded();

    final index = _goals.indexWhere((goal) => goal.id == id);

    if (index < 0) {
      return false;
    }

    _goals.removeAt(index);
    await SyncTombstones.instance.add(SyncCollection.savingsGoals, id);
    _reindexPriorities();

    final prefs = await AppPrefs.instance;

    await _persistGoals(prefs);

    notifyListeners();

    return true;
  }

  // Reorders active goals; [newIndex] is the final slot after removal.
  Future<void> reorderActiveGoals(int oldIndex, int newIndex) async {
    await ensureLoaded();

    final code = _activeCode;
    final active = activeGoalsFor(code).toList();

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
      if (_goals[i].currencyCode != code) {
        continue;
      }

      _goals[i] = active[activeIndex++];
    }

    _reindexPriorities();

    // Notify before the write so a dragged goal does not snap back while
    // the list rebuilds from the old order.
    notifyListeners();

    final prefs = await AppPrefs.instance;

    await _persistGoals(prefs);
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

    var changed = mergeRemoteRecords<WaffrTransaction>(
      items: _transactions,
      upserts: [
        for (final raw in transactions)
          if (transactionFromSync(raw) != null)
            _preserveEventTime(transactionFromSync(raw)!),
      ],
      deletes: transactionDeletes,
      collection: SyncCollection.transactions,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );

    changed |= mergeRemoteRecords<WaffrTransaction>(
      items: _transactions,
      upserts: [
        for (final raw in transfers)
          if (transferFromSync(raw) != null)
            _preserveEventTime(transferFromSync(raw)!),
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
          final amount = parseMoney(settings['monthly_income_amount']);
          if (amount != null && amount > 0) {
            _monthlyIncomeByCurrency[defaultCurrencyCode] = amount;
          } else {
            _monthlyIncomeByCurrency.remove(defaultCurrencyCode);
          }
        }
        if (settings.containsKey('weekly_income_amount')) {
          final amount = parseMoney(settings['weekly_income_amount']);
          if (amount != null && amount > 0) {
            _weeklyIncomeByCurrency[defaultCurrencyCode] = amount;
          } else {
            _weeklyIncomeByCurrency.remove(defaultCurrencyCode);
          }
        }
        if (settings.containsKey('income_overrides_by_currency')) {
          _replaceNonDefaultIncomeOverrides(
            settings['income_overrides_by_currency'],
          );
        }
        await CurrencyStore.instance.applyRemote(
          enabled: settings['enabled_currencies'] is List
              ? settings['enabled_currencies'] as List
              : null,
          active: settings['active_currency']?.toString(),
        );
        if (remoteUpdated != null) {
          await SyncDirty.setSettingsUpdatedAt(remoteUpdated);
        }
        changed = true;
        await ProfileSync.apply(settings);
      }
    }

    if (!changed) return;

    _sort();
    _completeGoalIfNeeded();
    final prefs = await AppPrefs.instance;
    await _persistAll(prefs);
    notifyListeners();
  }

  // Drops in-memory state so the next ensureLoaded re-reads prefs.
  void resetCache() {
    _transactions.clear();
    _touch();
    _goals.clear();
    _processedPeriods.clear();
    _pendingExpenseSources.clear();
    _monthlyIncomeByCurrency.clear();
    _weeklyIncomeByCurrency.clear();

    _loaded = false;
    _loader = null;

    notifyListeners();
  }

  Future<WaffrTransaction?> _createExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? note,
    String? sourceId,
    DateTime? occurredAt,
    String? currencyCode,
  }) async {
    final code = Currencies.normalize(currencyCode ?? _activeCode);
    if (!canDeduct(amount, currencyCode: code)) {
      return null;
    }

    final transaction = WaffrTransaction(
      id: WaffrTransaction.newId(),
      type: TransactionType.expense,
      amount: amount,
      currencyCode: code,
      category: category,
      paymentMethod: paymentMethod,
      note: note,
      sourceId: sourceId,
      dateTime: (occurredAt ?? deviceNow()).toLocal(),
    );

    await _add(transaction);
    return transaction;
  }

  Future<void> processDuePeriods() async {
    await ensureLoaded();

    final prefs = await AppPrefs.instance;

    final changed = await _processDuePeriods(prefs);

    if (changed) {
      notifyListeners();
    }
  }

  Future<void> _add(
    WaffrTransaction transaction, {
    bool persist = true,
    bool notify = true,
  }) async {
    await ensureLoaded();

    _transactions.add(transaction);

    _sort();

    _completeGoalIfNeeded();

    // Screens update first; the disk write follows. Waiting for the write
    // before notifying kept sheets open and balances stale until it ended.
    if (notify) {
      notifyListeners();
    }

    if (persist) {
      final prefs = await AppPrefs.instance;

      await _persistAll(prefs);
    }
  }

  Future<void> _load() async {
    await CurrencyStore.instance.ensureLoaded();
    if (!_listeningToCurrency) {
      _listeningToCurrency = true;
      CurrencyStore.instance.addListener(notifyListeners);
    }

    final prefs = await AppPrefs.instance;

    final stored = prefs.getStringList(transactionsKey);

    _transactions.clear();
    _touch();
    _goals.clear();
    _processedPeriods.clear();

    var stampCurrency = false;

    if (stored != null) {
      _transactions.addAll(
        stored.map(WaffrTransaction.decode).whereType<WaffrTransaction>(),
      );

      _sort();
      stampCurrency = stored.any((raw) => !raw.contains('currencyCode'));
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
        if (!_encodedHasPriority(raw) || !raw.contains('currencyCode')) {
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

    if (stampCurrency && _transactions.isNotEmpty) {
      await _persist(prefs);
    }

    final storedPeriods = prefs.getStringList(processedPeriodsKey) ?? const [];

    _processedPeriods.addAll(storedPeriods);

    _monthlyIncomeByCurrency.clear();
    _weeklyIncomeByCurrency.clear();
    final monthly = prefs.getDouble(monthlyIncomeKey);
    if (monthly != null && monthly > 0) {
      _monthlyIncomeByCurrency[defaultCurrencyCode] = monthly;
    }
    final weekly = prefs.getDouble(weeklyIncomeKey);
    if (weekly != null && weekly > 0) {
      _weeklyIncomeByCurrency[defaultCurrencyCode] = weekly;
    }
    _applyIncomeOverridesJson(prefs.getString(incomeOverridesByCurrencyKey));

    _loaded = true;

    if (onHydrated != null) {
      await onHydrated!();
    }

    await _processDuePeriods(prefs);

    notifyListeners();
  }

  // Periodic goal deductions plus leftover savings for completed income periods.
  Future<bool> _processDuePeriods(SharedPreferences prefs) async {
    if (_processingPeriods) {
      return false;
    }

    _processingPeriods = true;

    try {
      var changed = false;

      final now = deviceNow();

      final periodicIds = [
        for (final goal in _allActiveGoals)
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

        if (_percentPlanNeedsIncome(initialGoal)) {
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

      final leftoverKeys = <(RecurringFrequency, String, String)>{};

      for (final income in _transactions) {
        if (!income.isIncome) {
          continue;
        }

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

        leftoverKeys.add((income.frequency, key, income.currencyCode));
      }

      final leftovers = leftoverKeys.toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));

      for (final entry in leftovers) {
        final token = _leftoverToken(entry.$2, entry.$3);

        if (_markProcessed(token)) {
          changed = true;

          changed |= _transferLeftover(entry.$1, entry.$2, entry.$3);
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

  // Percent monthly plans wait until configured monthly income exists.
  bool _percentPlanNeedsIncome(SavingsGoal goal) {
    if (goal.deductFrequency != RecurringFrequency.monthly) return false;
    final percent = goal.allocatePercent;
    if (percent == null || percent <= 0) return false;
    return !hasConfiguredMonthlyIncomeFor(goal.currencyCode);
  }

  bool _deductGoalForPeriod(SavingsGoal goal, String periodKey) {
    if (goal.isCompleted) {
      return true;
    }

    final amount = goal.allocateAmount ?? 0;

    if (amount <= 0) {
      return true;
    }

    if (!canDeduct(amount, currencyCode: goal.currencyCode)) {
      return false;
    }

    _transactions.add(
      WaffrTransaction(
        id: WaffrTransaction.newId(),
        type: TransactionType.savingsIn,
        amount: amount,
        currencyCode: goal.currencyCode,
        note: 'توفير دوري: ${goal.name}',
        dateTime: deviceNow(),
        transferKind: SavingsTransferKind.goalPeriodic,
        goalId: goal.id,
        processedPeriodKey: periodKey,
      ),
    );

    _sort();

    return true;
  }

  // Moves leftover period income into savings after expenses and goal deductions.
  bool _transferLeftover(
    RecurringFrequency frequency,
    String periodKey,
    String currencyCode,
  ) {
    final period = CalendarPeriod.parseKey(periodKey);

    if (period == null) {
      return false;
    }

    final code = Currencies.normalize(currencyCode);
    final periodIncome = _incomeForPeriod(frequency, periodKey, code);

    if (periodIncome <= 0) {
      return false;
    }

    final periodExpense = expensesFor(code)
        .where((item) => period.contains(item.dateTime))
        .fold<double>(0, (sum, item) => sum + item.amount);

    final alreadySaved = _transactions
        .where(
          (item) =>
              item.currencyCode == code &&
              item.isSavingsIn &&
              item.processedPeriodKey == periodKey &&
              item.transferKind == SavingsTransferKind.goalPeriodic,
        )
        .fold<double>(0, (sum, item) => sum + item.amount);

    var leftover = periodIncome - periodExpense - alreadySaved;

    if (leftover <= 0) {
      return false;
    }

    final available = balanceFor(code);

    if (leftover > available) {
      leftover = available;
    }

    if (leftover <= 0) {
      return false;
    }

    final leftoverGoal = activeGoalsFor(code).isEmpty
        ? null
        : activeGoalsFor(code).first;

    _transactions.add(
      WaffrTransaction(
        id: WaffrTransaction.newId(),
        type: TransactionType.savingsIn,
        amount: leftover,
        currencyCode: code,
        note: frequency == RecurringFrequency.weekly
            ? 'توفير نهاية الأسبوع'
            : 'توفير نهاية الشهر',
        dateTime: deviceNow(),
        transferKind: SavingsTransferKind.periodLeftover,
        goalId: leftoverGoal?.id,
        processedPeriodKey: periodKey,
      ),
    );

    _sort();

    return true;
  }

  bool _completeGoalIfNeeded() {
    var changed = false;

    for (final goal in List<SavingsGoal>.from(_allActiveGoals)) {
      final progress = goalProgress(goal);

      if (progress + 0.0001 < goal.targetAmount) {
        continue;
      }

      final index = _goals.indexWhere((item) => item.id == goal.id);

      if (index < 0) {
        continue;
      }

      _goals[index] = goal.copyWith(
        completedAt: deviceNow(),
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

  bool _countsTowardGoal(WaffrTransaction item, SavingsGoal goal) {
    if (!item.isSavingsIn && !item.isSavingsOut) {
      return false;
    }

    if (item.currencyCode != goal.currencyCode) {
      return false;
    }

    final taggedId = item.goalId;

    if (taggedId != null && taggedId.isNotEmpty) {
      return taggedId == goal.id;
    }

    return _legacyGoalIdFor(item.dateTime) == goal.id;
  }

  // Untagged old transfers attach to the oldest goal still open at that time.
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

  // Sorts by priority, keeping storage order when priority values tie.
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

  String _leftoverToken(String periodKey, String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    if (code == defaultCurrencyCode) {
      return 'leftover:$periodKey';
    }
    return 'leftover:$code:$periodKey';
  }

  String _goalPeriodToken(String goalId, String periodKey) {
    return 'goal:$goalId:$periodKey';
  }

  double _incomeForPeriod(
    RecurringFrequency frequency,
    String periodKey,
    String currencyCode,
  ) {
    return incomesFor(currencyCode)
        .where(
          (item) => item.frequency == frequency && item.periodKey == periodKey,
        )
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  double _incomeInCalendar(
    RecurringFrequency frequency,
    DateTime date,
    String currencyCode,
  ) {
    final period = CalendarPeriod.ofFrequency(frequency, date);

    return incomesFor(currencyCode)
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
    final sypMonthly = _monthlyIncomeByCurrency[defaultCurrencyCode];
    if (sypMonthly != null && sypMonthly > 0) {
      await prefs.setDouble(monthlyIncomeKey, sypMonthly);
    } else {
      await prefs.remove(monthlyIncomeKey);
    }

    final sypWeekly = _weeklyIncomeByCurrency[defaultCurrencyCode];
    if (sypWeekly != null && sypWeekly > 0) {
      await prefs.setDouble(weeklyIncomeKey, sypWeekly);
    } else {
      await prefs.remove(weeklyIncomeKey);
    }

    final encoded = _encodeIncomeOverrides();
    if (encoded == null) {
      await prefs.remove(incomeOverridesByCurrencyKey);
    } else {
      await prefs.setString(incomeOverridesByCurrencyKey, encoded);
    }
  }

  void _setOverride(
    RecurringFrequency frequency,
    double amount,
    String currencyCode,
  ) {
    final code = Currencies.normalize(currencyCode);
    if (frequency == RecurringFrequency.monthly) {
      _monthlyIncomeByCurrency[code] = amount;
    } else if (frequency == RecurringFrequency.weekly) {
      _weeklyIncomeByCurrency[code] = amount;
    }
  }

  // Keeps the earlier local event time when merging a remote duplicate id.
  WaffrTransaction _preserveEventTime(WaffrTransaction incoming) {
    for (final local in _transactions) {
      if (local.id != incoming.id) continue;
      return incoming.copyWith(
        dateTime: earlierDeviceEventTime(local.dateTime, incoming.dateTime),
      );
    }
    return incoming;
  }

  void _clearOverride(RecurringFrequency frequency, String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    if (frequency == RecurringFrequency.monthly) {
      _monthlyIncomeByCurrency.remove(code);
    } else if (frequency == RecurringFrequency.weekly) {
      _weeklyIncomeByCurrency.remove(code);
    }
  }

  double? _overrideFor(RecurringFrequency frequency, String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return switch (frequency) {
      RecurringFrequency.monthly => _monthlyIncomeByCurrency[code],
      RecurringFrequency.weekly => _weeklyIncomeByCurrency[code],
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

  String? _encodeIncomeOverrides() {
    final codes = {
      ..._monthlyIncomeByCurrency.keys,
      ..._weeklyIncomeByCurrency.keys,
    }..remove(defaultCurrencyCode);

    if (codes.isEmpty) return null;

    final payload = <String, Map<String, double>>{};
    for (final code in codes) {
      final monthly = _monthlyIncomeByCurrency[code];
      final weekly = _weeklyIncomeByCurrency[code];
      final entry = <String, double>{};
      if (monthly != null && monthly > 0) entry['monthly'] = monthly;
      if (weekly != null && weekly > 0) entry['weekly'] = weekly;
      if (entry.isNotEmpty) payload[code] = entry;
    }

    if (payload.isEmpty) return null;
    return jsonEncode(payload);
  }

  void _replaceNonDefaultIncomeOverrides(Object? raw) {
    final monthly = _monthlyIncomeByCurrency[defaultCurrencyCode];
    final weekly = _weeklyIncomeByCurrency[defaultCurrencyCode];
    _monthlyIncomeByCurrency.removeWhere(
      (code, _) => code != defaultCurrencyCode,
    );
    _weeklyIncomeByCurrency.removeWhere(
      (code, _) => code != defaultCurrencyCode,
    );
    if (monthly != null) _monthlyIncomeByCurrency[defaultCurrencyCode] = monthly;
    if (weekly != null) _weeklyIncomeByCurrency[defaultCurrencyCode] = weekly;
    _applyIncomeOverridesJson(raw);
  }

  void _applyIncomeOverridesJson(Object? raw) {
    Map<String, dynamic>? decoded;
    if (raw is Map) {
      decoded = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final value = jsonDecode(raw);
        if (value is Map) {
          decoded = Map<String, dynamic>.from(value);
        }
      } catch (_) {
        return;
      }
    }
    if (decoded == null) return;

    decoded.forEach((code, value) {
      if (value is! Map) return;
      final normalized = Currencies.normalize(code);
      if (normalized == defaultCurrencyCode) return;
      final monthly = parseMoney(value['monthly']);
      final weekly = parseMoney(value['weekly']);
      if (monthly != null && monthly > 0) {
        _monthlyIncomeByCurrency[normalized] = monthly;
      }
      if (weekly != null && weekly > 0) {
        _weeklyIncomeByCurrency[normalized] = weekly;
      }
    });
  }

  List<WaffrTransaction> _migrateLegacyExpenses(List<String>? legacy) {
    if (legacy == null || legacy.isEmpty) {
      return const [];
    }

    final migrated = <WaffrTransaction>[];

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
        WaffrTransaction(
          id: WaffrTransaction.newId() + migrated.length.toString(),
          type: TransactionType.expense,
          amount: amount,
          category: 'أخرى',
          note: note,
          dateTime: (date ?? deviceNow()).toLocal(),
        ),
      );
    }

    return migrated;
  }

  void _sort() {
    _touch();
    _transactions.sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  double _totalOf(TransactionType type, String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return _totals.putIfAbsent(
      (type, code),
      () => _transactions
          .where((item) => item.type == type && item.currencyCode == code)
          .fold<double>(0, (sum, item) => sum + item.amount),
    );
  }

  // ---------------------------------------------------------------------
  // Derived-value caches. Screens read balances and the cycle start many
  // times per build; these are computed once per ledger change instead of
  // rescanning (and re-sorting) every transaction on every read.
  // ---------------------------------------------------------------------

  final Map<(TransactionType, String), double> _totals = {};
  final Map<String, DateTime?> _cycleStarts = {};

  /// Drops the caches. Called whenever the ledger changes.
  void _touch() {
    _totals.clear();
    _cycleStarts.clear();
  }

  @override
  void notifyListeners() {
    _touch();
    super.notifyListeners();
  }
}
