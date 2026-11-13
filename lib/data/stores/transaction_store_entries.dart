// Recording and undoing expenses, and manual moves between the balance
// and savings.

part of 'transaction_store.dart';

/// Recording and undoing expenses and moves between balance and savings.
extension LedgerEntries on TransactionStore {
  /// Returns the expense on success, or null when amount exceeds balance.
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

    // An automatic expense (bill, purchase) is posted once per source id:
    // return the one already saved, or the one being saved right now.
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

    // Remember the in-flight save so a second call with the same source
    // waits for it instead of posting twice.
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

  /// Removes an expense so its amount returns to the operating balance.
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

  /// Removes an income row and drops that amount from the balance.
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

  /// Largest amount a ledger row may hold.
  static const double _maxAmount = 999999999;

  /// Changes an expense the user logged: its amount, category, payment
  /// method, note or time. False when the row is missing, the amount is
  /// not valid, or a larger amount would overdraw the balance.
  Future<bool> updateExpense(
    String id, {
    double? amount,
    String? category,
    String? paymentMethod,
    String? note,
    bool clearNote = false,
    DateTime? dateTime,
  }) async {
    await ensureLoaded();

    final index = _transactions.indexWhere(
      (item) => item.id == id && item.isExpense,
    );
    if (index < 0) return false;

    final old = _transactions[index];
    final next = amount ?? old.amount;
    if (!next.isFinite || next <= 0 || next > _maxAmount) return false;
    // The old amount returns to the balance before the new one is taken.
    if (next > balanceFor(old.currencyCode) + old.amount) return false;

    _transactions[index] = old.edited(
      amount: next,
      category: category,
      paymentMethod: paymentMethod,
      note: note,
      clearNote: clearNote,
      dateTime: dateTime,
    );
    return _commitEdit();
  }

  /// Changes an income: its amount, source note or (for one-off incomes)
  /// its time. False when the row is missing, the amount is not valid, or
  /// a smaller amount would leave the balance below zero.
  Future<bool> updateIncome(
    String id, {
    double? amount,
    String? note,
    bool clearNote = false,
    DateTime? dateTime,
  }) async {
    await ensureLoaded();

    final index = _transactions.indexWhere(
      (item) => item.id == id && item.isIncome,
    );
    if (index < 0) return false;

    final old = _transactions[index];
    final next = amount ?? old.amount;
    if (!next.isFinite || next <= 0 || next > _maxAmount) return false;
    if (balanceFor(old.currencyCode) - old.amount + next < 0) return false;

    _transactions[index] = old.edited(
      amount: next,
      note: note,
      clearNote: clearNote,
      // A recurring income belongs to its period; its date stays put.
      dateTime: old.frequency == RecurringFrequency.none ? dateTime : null,
    );
    return _commitEdit();
  }

  /// True for savings moves the user made by hand; automatic transfers
  /// (period leftovers, plan deductions) cannot be edited or deleted.
  bool isEditableTransfer(WaffrTransaction item) =>
      (item.type == TransactionType.savingsIn &&
          item.transferKind == SavingsTransferKind.manual) ||
      (item.type == TransactionType.savingsOut &&
          item.transferKind == SavingsTransferKind.withdraw);

  /// Changes the amount of a manual saving or a withdrawal. False when the
  /// row is not editable, or the new amount needs more balance (or more
  /// savings) than there is.
  Future<bool> updateSavingsTransfer(String id, double amount) async {
    await ensureLoaded();

    final index = _transactions.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    final old = _transactions[index];
    if (!isEditableTransfer(old)) return false;
    if (!amount.isFinite || amount <= 0 || amount > _maxAmount) return false;

    final code = old.currencyCode;
    final delta = amount - old.amount;
    final saving = old.type == TransactionType.savingsIn;
    // A saving takes from the balance and adds to savings; a withdrawal
    // does the reverse. Neither side may go below zero.
    final balanceAfter = balanceFor(code) + (saving ? -delta : delta);
    final savingsAfter = savingsBalanceFor(code) + (saving ? delta : -delta);
    if (balanceAfter < 0 || savingsAfter < 0) return false;

    _transactions[index] = old.edited(amount: amount);
    return _commitEdit();
  }

  /// Deletes a manual saving or a withdrawal, returning the money to where
  /// it came from. False when that would leave either side below zero.
  Future<bool> deleteSavingsTransfer(String id) async {
    await ensureLoaded();

    final index = _transactions.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    final old = _transactions[index];
    if (!isEditableTransfer(old)) return false;

    final code = old.currencyCode;
    final saving = old.type == TransactionType.savingsIn;
    if (saving && savingsBalanceFor(code) - old.amount < 0) return false;
    if (!saving && balanceFor(code) - old.amount < 0) return false;

    _transactions.removeAt(index);
    _touch();
    await SyncTombstones.instance.add(SyncCollection.transactions, id);
    final prefs = await AppPrefs.instance;
    await _persist(prefs);
    notifyListeners();
    return true;
  }

  /// Re-sorts, re-checks goals, saves and notifies after an edit.
  Future<bool> _commitEdit() async {
    _sort();
    _touch();
    _completeGoalIfNeeded();
    notifyListeners();
    final prefs = await AppPrefs.instance;
    await _persistAll(prefs);
    return true;
  }

  /// Manual move from operating balance into savings (tags top active goal).
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

  /// Moves money from savings back to operating balance.
  Future<bool> withdrawFromSavings(
    double amount, {
    String? currencyCode,
  }) async {
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
}
