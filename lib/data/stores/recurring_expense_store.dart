// Recurring expenses: CRUD, sync, and due-date catch-up that posts real expenses.

import 'package:flutter/foundation.dart';
import 'package:waffer/data/models/app_notification.dart';
import 'package:waffer/data/services/notification_service.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/data/models/recurring_expense.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/sync/sync_mapper.dart';
import 'package:waffer/core/sync/sync_merge.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

// Schedules checked on launch/resume; posts expenses when nextDueAt is past.
class RecurringExpenseStore extends ChangeNotifier {
  RecurringExpenseStore._();

  static final RecurringExpenseStore instance = RecurringExpenseStore._();

  static const String itemsKey = 'recurring_expenses';

  static const int _maxCatchUp = 24;

  final List<RecurringExpense> _items = [];

  Future<void>? _loader;
  bool _loaded = false;
  Future<void>? _dueTail;

  bool get isLoaded => _loaded;

  List<RecurringExpense> get items => List.unmodifiable(_items);

  List<RecurringExpense> itemsFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return _items
        .where((item) => item.currencyCode == code)
        .toList(growable: false);
  }

  Future<void> ensureLoaded() => _loader ??= _load();

  RecurringExpense? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  // Requires configured monthly income for that currency before scheduling.
  Future<void> addExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    required RecurringUnit unit,
    required int intervalCount,
    String? note,
    String? currencyCode,
  }) async {
    if (amount <= 0 || intervalCount <= 0) return;

    await ensureLoaded();
    await TransactionStore.instance.ensureLoaded();
    final code = Currencies.normalize(
      currencyCode ?? CurrencyStore.instance.activeCode,
    );
    if (!TransactionStore.instance.hasConfiguredMonthlyIncomeFor(code)) {
      return;
    }

    final now = deviceNow();

    _items.insert(
      0,
      RecurringExpense(
        id: RecurringExpense.newId(),
        amount: amount,
        currencyCode: code,
        category: category,
        paymentMethod: paymentMethod,
        note: note,
        unit: unit,
        intervalCount: intervalCount,
        createdAt: now,
        // Due immediately so the first charge is written to history now.
        // Later charges wait until this date, then catch up on the next open.
        nextDueAt: now,
      ),
    );

    await _persist();
    notifyListeners();
    await processDue();
  }

  static const double _maxAmount = 999999999;

  Future<bool> updateAmount(
    String id,
    double amount, {
    String? currencyCode,
  }) async {
    if (!amount.isFinite || amount <= 0 || amount > _maxAmount) {
      return false;
    }

    await ensureLoaded();

    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return false;

    _items[index] = _items[index].copyWith(
      amount: amount,
      currencyCode: currencyCode,
    );
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await ensureLoaded();

    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;

    _items[index] = _items[index].copyWith(enabled: enabled);
    await _persist();
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    await ensureLoaded();

    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length == before) return;

    await SyncTombstones.instance.add(SyncCollection.recurringExpenses, id);
    await _persist();
    notifyListeners();
  }

  // Deducts due items when balance allows; otherwise notifies and stops catch-up.
  // Calls are queued so opening the app twice cannot post the same period twice.
  Future<void> processDue() {
    final previous = _dueTail ?? Future<void>.value();
    final run = previous.catchError((Object _) {}).then((_) => _processDue());
    _dueTail = run;
    return run;
  }

  Future<void> _processDue() async {
    await ensureLoaded();
    await TransactionStore.instance.ensureLoaded();

    final now = deviceNow();
    var changed = false;

    for (var i = 0; i < _items.length; i++) {
      var item = _items[i];
      if (!item.enabled) continue;
      if (!TransactionStore.instance.hasConfiguredMonthlyIncomeFor(
        item.currencyCode,
      )) {
        continue;
      }

      // Schedules saved before the first charge was due never reached history.
      if (item.nextDueAt.isAfter(now) && !_hasPosted(item.id)) {
        item = item.copyWith(nextDueAt: now);
        _items[i] = item;
        changed = true;
      }

      var catchUps = 0;
      DateTime? postedDue;

      while (_isDue(item.nextDueAt, now) && catchUps < _maxCatchUp) {
        catchUps++;

        final store = TransactionStore.instance;
        final dueAt = item.nextDueAt;
        final sourceId = _sourceId(item.id, dueAt);

        if (!store.canDeduct(item.amount, currencyCode: item.currencyCode) &&
            !_alreadyPosted(sourceId)) {
          await _notifyBlocked(item, dueAt);
          break;
        }

        final added = await store.addExpense(
          amount: item.amount,
          category: item.category,
          paymentMethod: item.paymentMethod,
          note: item.note ?? item.intervalDescription,
          sourceId: sourceId,
          occurredAt: dueAt.toLocal(),
          currencyCode: item.currencyCode,
        );

        if (added == null) {
          await _notifyBlocked(item, dueAt);
          break;
        }

        postedDue = dueAt;
        item = item.copyWith(
          nextDueAt: RecurringExpense.nextDueFrom(
            dueAt,
            item.unit,
            item.intervalCount,
          ),
        );
        _items[i] = item;
        changed = true;
        await _persist();
      }

      if (postedDue != null) {
        await _notifyApplied(item, postedDue);
      }
    }

    if (changed) {
      await _persist();
      notifyListeners();
    }

    await _warnUpcomingShortfalls(now);
  }

  // One heads-up per charge when the next scheduled amount, due within two
  // days, is more than the balance in that currency.
  Future<void> _warnUpcomingShortfalls(DateTime now) async {
    final store = TransactionStore.instance;
    final horizon = now.add(const Duration(days: 2));
    for (final item in _items) {
      if (!item.enabled) continue;
      final due = item.nextDueAt;
      if (!due.isAfter(now) || due.isAfter(horizon)) continue;
      if (store.canDeduct(item.amount, currencyCode: item.currencyCode)) {
        continue;
      }
      final symbol = currencyLabelFor(item.currencyCode);
      try {
        await NotificationService.instance.add(
          type: NotificationType.recurringExpenseUpcoming,
          title: 'رصيدك لا يكفي لمصروف قادم',
          message:
              '${_labelOf(item)}: يُخصم ${formatMoney(item.amount)} $symbol في ${formatDate(due)}، '
              'ورصيدك الآن ${formatMoney(store.balanceFor(item.currencyCode))} $symbol.',
          eventKey: 'recurringUpcoming:${item.id}:${due.toIso8601String()}',
          relatedId: item.id,
        );
      } catch (error, stack) {
        debugPrint('Recurring upcoming notice failed: $error\n$stack');
      }
    }
  }

  bool _isDue(DateTime due, DateTime now) => !due.toUtc().isAfter(now.toUtc());

  // Stable for a given local minute so a reload cannot mint a second source id.
  String _sourceId(String id, DateTime due) {
    final local = due.toLocal();
    final stamp =
        '${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}'
        '${local.hour.toString().padLeft(2, '0')}'
        '${local.minute.toString().padLeft(2, '0')}';
    return '${RecurringExpense.sourcePrefix}$id:$stamp';
  }

  bool _alreadyPosted(String sourceId) {
    for (final item in TransactionStore.instance.transactions) {
      if (item.isExpense && item.sourceId == sourceId) return true;
    }
    return false;
  }

  bool _hasPosted(String id) {
    final prefix = '${RecurringExpense.sourcePrefix}$id:';
    for (final item in TransactionStore.instance.transactions) {
      final source = item.sourceId;
      if (item.isExpense && source != null && source.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  // Name used in notices: the note, else the category.
  String _labelOf(RecurringExpense item) {
    final note = item.note?.trim() ?? '';
    return note.isEmpty ? item.category : note;
  }

  Future<void> _notifyBlocked(RecurringExpense item, DateTime dueAt) async {
    try {
      await NotificationService.instance.add(
        type: NotificationType.recurringExpenseBlocked,
        title: 'تعذّر خصم ${_labelOf(item)}',
        message:
            'رصيدك لا يكفي لخصم ${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)}. '
            'سيُخصم تلقائياً عندما يتوفر الرصيد.',
        eventKey: 'recurringBlocked:${item.id}:${dueAt.toIso8601String()}',
        relatedId: item.id,
      );
    } catch (error, stack) {
      debugPrint('Recurring block notice failed: $error\n$stack');
    }
  }

  Future<void> _notifyApplied(RecurringExpense item, DateTime postedDue) async {
    try {
      await NotificationService.instance.add(
        type: NotificationType.recurringExpenseApplied,
        title: 'خُصم ${_labelOf(item)}',
        message:
            'خُصم ${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)} '
            '(${item.intervalDescription}). الخصم التالي في ${formatDate(item.nextDueAt)}.',
        eventKey: 'recurringApplied:${item.id}:${postedDue.toIso8601String()}',
        relatedId: item.id,
      );
    } catch (error, stack) {
      debugPrint('Recurring applied notice failed: $error\n$stack');
    }
  }

  Future<void> applyRemoteSync({
    required List<Map<String, dynamic>> upserts,
    required List<SyncTombstone> deletes,
  }) async {
    await ensureLoaded();

    final changed = mergeRemoteRecords<RecurringExpense>(
      items: _items,
      upserts: [
        for (final raw in upserts)
          if (recurringFromSync(raw) != null) recurringFromSync(raw)!,
      ],
      deletes: deletes,
      collection: SyncCollection.recurringExpenses,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );

    if (!changed) return;

    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _persist();
    notifyListeners();
  }

  void resetCache() {
    _items.clear();
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    final stored = prefs.getStringList(itemsKey) ?? const [];

    _items
      ..clear()
      ..addAll(stored.map(RecurringExpense.decode).whereType<RecurringExpense>())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _loaded = true;
    if (stored.any((raw) => !raw.contains('currencyCode'))) {
      await _persist();
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(
      itemsKey,
      _items.map((item) => item.encode()).toList(),
    );
    await SyncDirty.mark();
  }
}
