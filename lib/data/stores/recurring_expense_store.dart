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
  bool _processing = false;

  bool get isLoaded => _loaded;

  List<RecurringExpense> get items => List.unmodifiable(_items);

  List<RecurringExpense> itemsFor(String currencyCode) {
    final code = Currencies.normalize(currencyCode);
    return _items
        .where((item) => item.currencyCode == code)
        .toList(growable: false);
  }

  Future<void> ensureLoaded() => _loader ??= _load();

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
        nextDueAt: RecurringExpense.nextDueFrom(now, unit, intervalCount),
      ),
    );

    await _persist();
    notifyListeners();
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
  Future<void> processDue() async {
    await ensureLoaded();
    await TransactionStore.instance.ensureLoaded();

    if (_processing) return;
    _processing = true;

    try {
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

        var catchUps = 0;
        DateTime? postedDue;

        while (!item.nextDueAt.isAfter(now) && catchUps < _maxCatchUp) {
          catchUps++;

          final store = TransactionStore.instance;
          if (!store.canDeduct(item.amount, currencyCode: item.currencyCode)) {
            await NotificationService.instance.add(
              type: NotificationType.recurringExpenseBlocked,
              title: 'تعذر خصم المصروف المتكرر',
              message:
                  'رصيدك لا يكفي لخصم ${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)}'
                  ' (${item.note ?? item.category}).',
              eventKey:
                  'recurringBlocked:${item.id}:${item.nextDueAt.toIso8601String()}',
              relatedId: item.id,
            );
            break;
          }

          final sourceId =
              'recurring:${item.id}:${item.nextDueAt.millisecondsSinceEpoch}';
          final dueAt = item.nextDueAt;

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
            await NotificationService.instance.add(
              type: NotificationType.recurringExpenseBlocked,
              title: 'تعذر خصم المصروف المتكرر',
              message:
                  'رصيدك لا يكفي لخصم ${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)}'
                  ' (${item.note ?? item.category}).',
              eventKey:
                  'recurringBlocked:${item.id}:${dueAt.toIso8601String()}',
              relatedId: item.id,
            );
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
        }

        if (postedDue != null) {
          await NotificationService.instance.add(
            type: NotificationType.recurringExpenseApplied,
            title: 'تم خصم مصروف متكرر',
            message:
                'خُصم ${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)}'
                ' (${item.note ?? item.category}).',
            eventKey: 'recurringApplied:${item.id}:${postedDue.toIso8601String()}',
            relatedId: item.id,
          );
        }
      }

      if (changed) {
        await _persist();
        notifyListeners();
      }
    } finally {
      _processing = false;
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
