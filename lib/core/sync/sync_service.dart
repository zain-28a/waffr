import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:waffer/core/data/notification_service.dart';
import 'package:waffer/core/data/recurring_expense_store.dart';
import 'package:waffer/core/data/shopping_list_store.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/sync/api_config.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/sync/sync_mapper.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';

enum SyncStatus { success, offline, noAccount, failed, skipped }

class SyncResult {
  final SyncStatus status;
  final String userMessage;

  const SyncResult(this.status, this.userMessage);

  bool get ok => status == SyncStatus.success || status == SyncStatus.skipped;
}

/// Pushes local SharedPreferences data to FastAPI and merges server changes.
///
/// Local storage stays the offline source of truth. A failed request never
/// overwrites or deletes local records.
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  static const Duration _debounce = Duration(seconds: 3);
  static const Duration _timeout = Duration(seconds: 25);

  Timer? _debounceTimer;
  bool _syncing = false;
  bool _pending = false;
  bool _listenersAttached = false;
  bool _applying = false;

  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    _attachListeners();
    await SyncTombstones.instance.ensureLoaded();
    await syncNow();
  }

  void scheduleSync() {
    if (_applying) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(syncNow());
    });
  }

  Future<SyncResult> syncNow({bool force = false}) async {
    _debounceTimer?.cancel();

    if (_syncing) {
      _pending = true;
      return const SyncResult(SyncStatus.skipped, 'المزامنة قيد التنفيذ');
    }

    _syncing = true;
    isSyncing.value = true;

    try {
      final email = await AuthSession.instance.email();
      if (email == null) {
        return const SyncResult(
          SyncStatus.noAccount,
          'أضف بريداً إلكترونياً لتفعيل المزامنة',
        );
      }

      final dirty = await SyncDirty.isDirty();
      final lastSync = await AuthSession.instance.lastSyncAt();
      if (!force && !dirty && lastSync != null && _tombstoneCount() == 0) {
        return const SyncResult(SyncStatus.success, 'البيانات محدّثة');
      }

      var token = await AuthSession.instance.ensureToken();
      if (token == null) {
        return const SyncResult(
          SyncStatus.offline,
          'لا يوجد اتصال. تم حفظ التغييرات محلياً',
        );
      }

      final payload = await _buildRequest(lastSync: lastSync, sendAll: dirty || lastSync == null || force);
      final base = await ApiConfig.baseUrl();
      http.Response response;
      try {
        response = await http
            .post(
              Uri.parse('$base/sync'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(payload),
            )
            .timeout(_timeout);
      } on SocketException {
        return const SyncResult(
          SyncStatus.offline,
          'لا يوجد اتصال. تم حفظ التغييرات محلياً',
        );
      } on TimeoutException {
        return const SyncResult(
          SyncStatus.offline,
          'انتهت مهلة الاتصال. تم حفظ التغييرات محلياً',
        );
      } on http.ClientException {
        return const SyncResult(
          SyncStatus.offline,
          'لا يوجد اتصال. تم حفظ التغييرات محلياً',
        );
      }

      if (response.statusCode == 401) {
        await AuthSession.instance.clearToken();
        token = await AuthSession.instance.ensureToken();
        if (token == null) {
          return const SyncResult(
            SyncStatus.failed,
            'تعذر تسجيل الدخول للمزامنة',
          );
        }
        try {
          response = await http
              .post(
                Uri.parse('$base/sync'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token',
                },
                body: jsonEncode(payload),
              )
              .timeout(_timeout);
        } catch (_) {
          return const SyncResult(
            SyncStatus.offline,
            'لا يوجد اتصال. تم حفظ التغييرات محلياً',
          );
        }
      }

      if (response.statusCode != 200) {
        return const SyncResult(
          SyncStatus.failed,
          'تعذر المزامنة. يمكنك المحاولة لاحقاً',
        );
      }

      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          return const SyncResult(
            SyncStatus.failed,
            'تعذر المزامنة. يمكنك المحاولة لاحقاً',
          );
        }
        body = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return const SyncResult(
          SyncStatus.failed,
          'تعذر المزامنة. يمكنك المحاولة لاحقاً',
        );
      }

      final applied = await _applyResponse(body);
      if (!applied) {
        return const SyncResult(
          SyncStatus.failed,
          'تعذر دمج البيانات. بقيت النسخة المحلية',
        );
      }

      final DateTime serverTime = parseSyncDateOrNow(
        body['server_time']?.toString(),
      );
      await AuthSession.instance.saveLastSyncAt(serverTime);
      await SyncDirty.clear();
      return const SyncResult(SyncStatus.success, 'تمت المزامنة');
    } catch (_) {
      return const SyncResult(
        SyncStatus.failed,
        'تعذر المزامنة. يمكنك المحاولة لاحقاً',
      );
    } finally {
      _syncing = false;
      isSyncing.value = false;
      if (_pending) {
        _pending = false;
        scheduleSync();
      }
    }
  }

  int _tombstoneCount() {
    var total = 0;
    for (final collection in SyncCollection.values) {
      total += SyncTombstones.instance.of(collection).length;
    }
    return total;
  }

  Future<Map<String, dynamic>> _buildRequest({
    required DateTime? lastSync,
    required bool sendAll,
  }) async {
    await Future.wait<void>([
      TransactionStore.instance.ensureLoaded(),
      ShoppingListStore.instance.ensureLoaded(),
      RecurringExpenseStore.instance.ensureLoaded(),
      NotificationService.instance.ensureLoaded(),
      SyncTombstones.instance.ensureLoaded(),
    ]);

    final store = TransactionStore.instance;
    final txs = <Map<String, dynamic>>[];
    final transfers = <Map<String, dynamic>>[];
    for (final item in store.transactions) {
      if (!_shouldSend(item.syncUpdatedAt, lastSync, sendAll)) continue;
      if (item.isSavingsIn || item.isSavingsOut) {
        transfers.add(transferToSync(item));
      } else {
        txs.add(transactionToSync(item));
      }
    }

    final goals = [
      for (final goal in store.goals)
        if (_shouldSend(goal.syncUpdatedAt, lastSync, sendAll))
          goalToSync(goal),
    ];

    final items = [
      for (final item in ShoppingListStore.instance.items)
        if (_shouldSend(item.syncUpdatedAt, lastSync, sendAll))
          item.toSyncJson(),
    ];

    final lists = (sendAll || items.isNotEmpty || lastSync == null)
        ? [shoppingListToSync()]
        : <Map<String, dynamic>>[];

    final recurring = [
      for (final item in RecurringExpenseStore.instance.items)
        if (_shouldSend(item.syncUpdatedAt, lastSync, sendAll))
          recurringToSync(item),
    ];

    final notifications = [
      for (final item in NotificationService.instance.notifications)
        if (_shouldSend(item.syncUpdatedAt, lastSync, sendAll))
          notificationToSync(item),
    ];

    final settingsUpdated = await SyncDirty.settingsUpdatedAt();
    final includeSettings = sendAll ||
        lastSync == null ||
        (settingsUpdated != null && newerOrEqual(settingsUpdated, lastSync));

    return {
      'last_sync_at': lastSync == null ? null : toSyncIso(lastSync),
      'transactions': collectionPayload(
        upserts: txs,
        deletes: SyncTombstones.instance.of(SyncCollection.transactions),
      ),
      'savings_goals': collectionPayload(
        upserts: goals,
        deletes: SyncTombstones.instance.of(SyncCollection.savingsGoals),
      ),
      'savings_transfers': collectionPayload(
        upserts: transfers,
        deletes: SyncTombstones.instance.of(SyncCollection.savingsTransfers),
      ),
      'shopping_lists': collectionPayload(
        upserts: lists,
        deletes: SyncTombstones.instance.of(SyncCollection.shoppingLists),
      ),
      'shopping_items': collectionPayload(
        upserts: items,
        deletes: SyncTombstones.instance.of(SyncCollection.shoppingItems),
      ),
      'recurring_expenses': collectionPayload(
        upserts: recurring,
        deletes: SyncTombstones.instance.of(SyncCollection.recurringExpenses),
      ),
      'notifications': collectionPayload(
        upserts: notifications,
        deletes: SyncTombstones.instance.of(SyncCollection.notifications),
      ),
      'settings': includeSettings ? await _settingsPayload() : null,
    };
  }

  Future<Map<String, dynamic>> _settingsPayload() async {
    final store = TransactionStore.instance;
    return {
      'notifications_muted': NotificationService.instance.isMuted,
      'notifications_enabled': !NotificationService.instance.isMuted,
      'ai_data_enabled': null,
      'monthly_income_amount': store.monthlyIncomeOverride,
      'weekly_income_amount': store.weeklyIncomeOverride,
      'processed_period_keys': store.processedPeriodTokens.toList(),
      'updated_at': toSyncIso(await SyncDirty.settingsUpdatedAt()),
    };
  }

  bool _shouldSend(DateTime updatedAt, DateTime? lastSync, bool sendAll) {
    if (sendAll || lastSync == null) return true;
    return newerOrEqual(updatedAt, lastSync);
  }

  Future<bool> _applyResponse(Map<String, dynamic> body) async {
    try {
      _applying = true;
      SyncDirty.suppressed = true;

      await TransactionStore.instance.applyRemoteSync(
        transactions: asMapList(_collection(body, 'transactions')['upserts']),
        transactionDeletes: tombstonesFromSync(
          _collection(body, 'transactions')['deletes'],
        ),
        transfers: asMapList(
          _collection(body, 'savings_transfers')['upserts'],
        ),
        transferDeletes: tombstonesFromSync(
          _collection(body, 'savings_transfers')['deletes'],
        ),
        goals: asMapList(_collection(body, 'savings_goals')['upserts']),
        goalDeletes: tombstonesFromSync(
          _collection(body, 'savings_goals')['deletes'],
        ),
        settings: body['settings'] is Map
            ? Map<String, dynamic>.from(body['settings'] as Map)
            : null,
      );

      await ShoppingListStore.instance.applyRemoteSync(
        upserts: asMapList(_collection(body, 'shopping_items')['upserts']),
        deletes: tombstonesFromSync(
          _collection(body, 'shopping_items')['deletes'],
        ),
      );

      await RecurringExpenseStore.instance.applyRemoteSync(
        upserts: asMapList(
          _collection(body, 'recurring_expenses')['upserts'],
        ),
        deletes: tombstonesFromSync(
          _collection(body, 'recurring_expenses')['deletes'],
        ),
      );

      await NotificationService.instance.applyRemoteSync(
        upserts: asMapList(_collection(body, 'notifications')['upserts']),
        deletes: tombstonesFromSync(
          _collection(body, 'notifications')['deletes'],
        ),
        muted: _mutedFromSettings(body['settings']),
      );

      await _clearAcknowledgedTombstones(body);
      return true;
    } catch (_) {
      return false;
    } finally {
      SyncDirty.suppressed = false;
      _applying = false;
    }
  }

  Map<String, dynamic> _collection(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  bool? _mutedFromSettings(Object? raw) {
    if (raw is! Map) return null;
    if (raw.containsKey('notifications_muted')) {
      return raw['notifications_muted'] == true;
    }
    if (raw.containsKey('notifications_enabled')) {
      return raw['notifications_enabled'] != true;
    }
    return null;
  }

  Future<void> _clearAcknowledgedTombstones(Map<String, dynamic> body) async {
    Future<void> clear(String key, SyncCollection collection) async {
      final sent = SyncTombstones.instance.of(collection).map((e) => e.clientId);
      final returned = tombstonesFromSync(_collection(body, key)['deletes'])
          .map((e) => e.clientId);
      await SyncTombstones.instance.remove(collection, {...sent, ...returned});
    }

    await clear('transactions', SyncCollection.transactions);
    await clear('savings_goals', SyncCollection.savingsGoals);
    await clear('savings_transfers', SyncCollection.savingsTransfers);
    await clear('shopping_lists', SyncCollection.shoppingLists);
    await clear('shopping_items', SyncCollection.shoppingItems);
    await clear('recurring_expenses', SyncCollection.recurringExpenses);
    await clear('notifications', SyncCollection.notifications);
  }

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    SyncDirty.addListener(scheduleSync);
  }
}
