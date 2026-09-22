import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/app_notification.dart';
import 'package:waffer/core/data/notification_service.dart';
import 'package:waffer/core/data/recurring_expense.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/sync/sync_mapper.dart';
import 'package:waffer/core/sync/sync_merge.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';
import 'package:waffer/core/utils/money.dart';

/// مخزن المصروفات المتكررة. يُفحص عند فتح التطبيق وفي كل استئناف.
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

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> addExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    required RecurringUnit unit,
    required int intervalCount,
    String? note,
  }) async {
    if (amount <= 0 || intervalCount <= 0) return;

    await ensureLoaded();
    await TransactionStore.instance.ensureLoaded();
    if (!TransactionStore.instance.hasConfiguredMonthlyIncome) return;

    final now = deviceNow();

    _items.insert(
      0,
      RecurringExpense(
        id: RecurringExpense.newId(),
        amount: amount,
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

  Future<bool> updateAmount(String id, double amount) async {
    if (!amount.isFinite || amount <= 0 || amount > _maxAmount) {
      return false;
    }

    await ensureLoaded();

    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return false;

    _items[index] = _items[index].copyWith(amount: amount);
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

  /// يخصم المستحق إن وُجد رصيد كافٍ. إن لم يكفِ الرصيد يُحظر الخصم ويُنبَّه المستخدم.
  Future<void> processDue() async {
    await ensureLoaded();
    await TransactionStore.instance.ensureLoaded();

    if (_processing) return;
    _processing = true;

    try {
      final now = deviceNow();
      var changed = false;
      final incomeReady = TransactionStore.instance.hasConfiguredMonthlyIncome;

      for (var i = 0; i < _items.length; i++) {
        var item = _items[i];
        if (!item.enabled) continue;
        if (!incomeReady) continue;

        var catchUps = 0;

        while (!item.nextDueAt.isAfter(now) && catchUps < _maxCatchUp) {
          catchUps++;

          final store = TransactionStore.instance;
          if (!store.canDeduct(item.amount)) {
            await NotificationService.instance.add(
              type: NotificationType.recurringExpenseBlocked,
              title: 'تعذر خصم المصروف المتكرر',
              message:
                  'رصيدك لا يكفي لخصم ${formatMoney(item.amount)} $currencyLabel'
                  ' (${item.note ?? item.category}).',
              eventKey:
                  'recurringBlocked:${item.id}:${item.nextDueAt.toIso8601String()}',
              relatedId: item.id,
            );
            break;
          }

          final sourceId =
              'recurring:${item.id}:${item.nextDueAt.millisecondsSinceEpoch}';

          final added = await store.addExpense(
            amount: item.amount,
            category: item.category,
            paymentMethod: item.paymentMethod,
            note: item.note ?? item.intervalDescription,
            sourceId: sourceId,
            occurredAt: item.nextDueAt.toLocal(),
          );

          if (added == null) {
            await NotificationService.instance.add(
              type: NotificationType.recurringExpenseBlocked,
              title: 'تعذر خصم المصروف المتكرر',
              message:
                  'رصيدك لا يكفي لخصم ${formatMoney(item.amount)} $currencyLabel'
                  ' (${item.note ?? item.category}).',
              eventKey:
                  'recurringBlocked:${item.id}:${item.nextDueAt.toIso8601String()}',
              relatedId: item.id,
            );
            break;
          }

          item = item.copyWith(
            nextDueAt: RecurringExpense.nextDueFrom(
              item.nextDueAt,
              item.unit,
              item.intervalCount,
            ),
          );
          _items[i] = item;
          changed = true;
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
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(itemsKey) ?? const [];

    _items
      ..clear()
      ..addAll(stored.map(RecurringExpense.decode).whereType<RecurringExpense>())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      itemsKey,
      _items.map((item) => item.encode()).toList(),
    );
    await SyncDirty.mark();
  }
}
