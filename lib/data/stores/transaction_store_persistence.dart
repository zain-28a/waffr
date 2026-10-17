// Loading the ledger from SharedPreferences, migrating older formats,
// and writing it back.

part of 'transaction_store.dart';

/// Loading the ledger from prefs (with migrations) and saving it back.
extension _LedgerPersistence on TransactionStore {
  Future<void> _load() async {
    // Currency changes change every per-currency figure, so listen once.
    await CurrencyStore.instance.ensureLoaded();
    if (!_listeningToCurrency) {
      _listeningToCurrency = true;
      CurrencyStore.instance.addListener(notifyListeners);
    }

    final prefs = await AppPrefs.instance;

    // Rows: the JSON list, or the pre-JSON expense list migrated once.
    // Rows saved before currencies existed are stamped SYP and re-saved.
    final stored = prefs.getStringList(TransactionStore.transactionsKey);
    final decoded = stored == null ? null : await _decodeRows(stored);

    _transactions.clear();
    _touch();
    _goals.clear();
    _processedPeriods.clear();

    var stampCurrency = false;

    if (stored != null && decoded != null) {
      _transactions.addAll(decoded);

      _sort();
      stampCurrency = stored.any((raw) => !raw.contains('currencyCode'));
    } else {
      _transactions.addAll(
        _migrateLegacyExpenses(
          prefs.getStringList(TransactionStore.legacyExpensesKey),
        ),
      );

      _sort();

      if (_transactions.isNotEmpty) {
        await _persist(prefs);
      }
    }

    // Goals: the list, or the single goal older versions kept. Missing
    // priorities or currencies are written back in the new shape.
    final storedGoals =
        prefs.getStringList(TransactionStore.savingsGoalsKey) ?? const [];

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

    // Processed period tokens and the configured incomes.
    final storedPeriods =
        prefs.getStringList(TransactionStore.processedPeriodsKey) ?? const [];

    _processedPeriods.addAll(storedPeriods);

    _monthlyIncomeByCurrency.clear();
    _weeklyIncomeByCurrency.clear();
    final monthly = prefs.getDouble(TransactionStore.monthlyIncomeKey);
    if (monthly != null && monthly > 0) {
      _monthlyIncomeByCurrency[defaultCurrencyCode] = monthly;
    }
    final weekly = prefs.getDouble(TransactionStore.weeklyIncomeKey);
    if (weekly != null && weekly > 0) {
      _weeklyIncomeByCurrency[defaultCurrencyCode] = weekly;
    }
    _applyIncomeOverridesJson(
      prefs.getString(TransactionStore.incomeOverridesByCurrencyKey),
    );

    // Loaded: let the app adjust (e.g. migrations elsewhere), then run any
    // end-of-period work that came due while the app was closed.
    _loaded = true;

    if (onHydrated != null) {
      await onHydrated!();
    }

    await _processDuePeriods(prefs);

    notifyListeners();
  }

  /// Stored rows in order, without unreadable ones. A large ledger is
  /// decoded in a background isolate, which also encodes each row back so
  /// the first save after launch does not re-encode the whole ledger.
  Future<List<WaffrTransaction>> _decodeRows(List<String> stored) async {
    if (stored.length < TransactionStore.backgroundDecodeRows) {
      return stored
          .map(WaffrTransaction.decode)
          .whereType<WaffrTransaction>()
          .toList();
    }
    final rows = await compute(
      _decodeLedgerRows,
      stored,
      debugLabel: 'decode ledger',
    );
    for (final (row, text) in rows) {
      _rowText[row] = text;
    }
    return [for (final (row, _) in rows) row];
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
      final raw = prefs.getString(TransactionStore.legacySavingsGoalKey);
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

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setStringList(
      TransactionStore.transactionsKey,
      _transactions.map(_encodeRow).toList(),
    );

    await prefs.setDouble(TransactionStore.balanceKey, balance);

    await prefs.setDouble(TransactionStore.maxBalanceKey, maxBalance);

    await prefs.setDouble(TransactionStore.savingsBalanceKey, savingsBalance);

    await _persistIncomeOverrides(prefs);
    await SyncDirty.mark();
  }

  /// [WaffrTransaction.encode], once per row.
  String _encodeRow(WaffrTransaction row) => _rowText[row] ??= row.encode();

  Future<void> _persistIncomeOverrides(SharedPreferences prefs) async {
    final sypMonthly = _monthlyIncomeByCurrency[defaultCurrencyCode];
    if (sypMonthly != null && sypMonthly > 0) {
      await prefs.setDouble(TransactionStore.monthlyIncomeKey, sypMonthly);
    } else {
      await prefs.remove(TransactionStore.monthlyIncomeKey);
    }

    final sypWeekly = _weeklyIncomeByCurrency[defaultCurrencyCode];
    if (sypWeekly != null && sypWeekly > 0) {
      await prefs.setDouble(TransactionStore.weeklyIncomeKey, sypWeekly);
    } else {
      await prefs.remove(TransactionStore.weeklyIncomeKey);
    }

    final encoded = _encodeIncomeOverrides();
    if (encoded == null) {
      await prefs.remove(TransactionStore.incomeOverridesByCurrencyKey);
    } else {
      await prefs.setString(
        TransactionStore.incomeOverridesByCurrencyKey,
        encoded,
      );
    }
  }

  Future<void> _persistGoals(SharedPreferences prefs) async {
    await prefs.setStringList(
      TransactionStore.savingsGoalsKey,
      _goals.map((item) => item.encode()).toList(),
    );

    await prefs.setStringList(
      TransactionStore.processedPeriodsKey,
      _processedPeriods.toList(),
    );
    await SyncDirty.mark();
  }

  Future<void> _persistAll(SharedPreferences prefs) async {
    await _persist(prefs);
    await _persistGoals(prefs);
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
}

/// Background half of [_LedgerPersistence._decodeRows]: each readable row
/// with its encoded text, in stored order.
List<(WaffrTransaction, String)> _decodeLedgerRows(List<String> stored) {
  return [
    for (final raw in stored)
      if (WaffrTransaction.decode(raw) case final row?) (row, row.encode()),
  ];
}
