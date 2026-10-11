// Orchestrates cloud sync: push local changes to FastAPI /sync and merge
// the server's reply back into on-device stores without wiping offline data.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/expense_preset_store.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/shopping_list_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/security/data_key.dart';
import 'package:waffr/core/sync/api_config.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/core/sync/sync_crypto.dart';
import 'package:waffr/core/sync/sync_dirty.dart';
import 'package:waffr/core/sync/sync_mapper.dart';
import 'package:waffr/core/sync/sync_pull_policy.dart';
import 'package:waffr/core/sync/profile_photo_sync.dart';
import 'package:waffr/core/sync/profile_sync.dart';
import 'package:waffr/data/services/usage_streak_service.dart';
import 'package:waffr/core/sync/sync_tombstones.dart';

enum SyncStatus { success, offline, noAccount, failed, skipped }

// Outcome of one sync attempt, including a user-facing Arabic message.
class SyncResult {
  final SyncStatus status;
  final String userMessage;

  const SyncResult(this.status, this.userMessage);

  bool get ok => status == SyncStatus.success || status == SyncStatus.skipped;
}

// Singleton that pushes dirty local SharedPreferences data and pulls remote
// upserts/deletes. Local storage stays the offline source of truth; a failed
// HTTP call never overwrites or deletes local records.
class SyncService with WidgetsBindingObserver {
  SyncService._();

  static final SyncService instance = SyncService._();

  static const Duration _debounce = Duration(seconds: 3);
  static const Duration _timeout = Duration(seconds: 25);
  static const Duration _minPullInterval = Duration(seconds: 20);
  static const String _currencySyncedKey = 'waffer_currency_synced';

  Timer? _debounceTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;
  bool _pending = false;
  bool _listenersAttached = false;
  bool _applying = false;
  bool _wasOnline = true;
  bool _resealPending = false;
  DateTime? _lastNetworkAttemptAt;

  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  // Wire dirty/lifecycle/connectivity listeners, load tombstones, then sync.
  Future<void> initialize() async {
    _attachListeners();
    await SyncTombstones.instance.ensureLoaded();
    await syncNow();
  }

  // Debounce rapid local edits so we batch them into one network round-trip.
  void scheduleSync() {
    if (_applying) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(syncNow());
    });
  }

  // Run push+pull now: require a logged-in session, flush pending photo work,
  // optionally skip a clean pull, POST /sync, then merge the response.
  Future<SyncResult> syncNow({bool force = false}) async {
    _debounceTimer?.cancel();

    if (_syncing) {
      _pending = true;
      return const SyncResult(SyncStatus.skipped, 'جارٍ المزامنة');
    }

    _syncing = true;
    isSyncing.value = true;

    try {
      if (!await AuthSession.instance.isLoggedIn()) {
        return const SyncResult(
          SyncStatus.noAccount,
          'في وضع الضيف تبقى بياناتك على جهازك فقط. سجّل الدخول للمزامنة',
        );
      }

      await ProfilePhotoSync.flush();

      // A streak change that no successful sync carried yet (marked while
      // another sync was in flight, or before the app was closed) still
      // has to reach the server.
      final streak = UsageStreakService.instance;
      await streak.ensureLoaded();
      final dirty = await SyncDirty.isDirty() || streak.hasUnsyncedChange;
      final lastSync = await AuthSession.instance.lastSyncAt();
      if (shouldSkipCleanPull(
        force: force,
        dirty: dirty,
        tombstoneCount: _tombstoneCount(),
        lastAttemptAt: _lastNetworkAttemptAt,
        now: DateTime.now(),
        minInterval: _minPullInterval,
      )) {
        return const SyncResult(SyncStatus.success, 'البيانات محدّثة');
      }

      var token = await AuthSession.instance.ensureToken();
      if (token == null) {
        return const SyncResult(
          SyncStatus.noAccount,
          'انتهت الجلسة. سجّل الدخول للمزامنة',
        );
      }

      // Sessions from before encryption have no data key. Signing in again
      // with the password creates or unlocks it.
      final cipher = await DataKeyStore.instance.cipher();
      if (cipher == null) {
        await AuthSession.instance.clearSession();
        return const SyncResult(
          SyncStatus.noAccount,
          'سجّل الدخول مجدداً لحماية بياناتك',
        );
      }

      final prefs = await AppPrefs.instance;
      final currencySynced = prefs.getBool(_currencySyncedKey) ?? false;
      final streakRevision = streak.revision;
      final payload = await _buildRequest(
        lastSync: lastSync,
        sendAll: dirty || lastSync == null || force || !currencySynced,
      );
      await sealSyncRequest(payload, cipher);
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
            .timeout(ApiConfig.timeoutFor(base, local: _timeout));
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

      _lastNetworkAttemptAt = DateTime.now();

      if (response.statusCode == 401) {
        await AuthSession.instance.clearSession();
        return const SyncResult(
          SyncStatus.failed,
          'انتهت الجلسة. سجّل الدخول مجدداً',
        );
      }

      if (response.statusCode != 200) {
        return const SyncResult(
          SyncStatus.failed,
          'تعذّر المزامنة. يمكنك المحاولة لاحقاً',
        );
      }

      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          return const SyncResult(
            SyncStatus.failed,
            'تعذّر المزامنة. يمكنك المحاولة لاحقاً',
          );
        }
        body = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return const SyncResult(
          SyncStatus.failed,
          'تعذّر المزامنة. يمكنك المحاولة لاحقاً',
        );
      }

      final sawPlaintext = await openSyncResponse(body, cipher);
      final applied = await _applyResponse(body);
      if (!applied) {
        return const SyncResult(
          SyncStatus.failed,
          'تعذّر تحديث بياناتك من الحساب، فبقيت النسخة المحفوظة على جهازك',
        );
      }

      await ProfilePhotoSync.applyFromSettings(
        body['settings'] is Map
            ? Map<String, dynamic>.from(body['settings'] as Map)
            : null,
      );

      final DateTime serverTime = parseSyncDateOrNow(
        body['server_time']?.toString(),
      );
      await AuthSession.instance.saveLastSyncAt(serverTime);
      await SyncDirty.clear();
      if (!currencySynced) {
        await prefs.setBool(_currencySyncedKey, true);
      }
      // A streak recorded during this round trip goes out next time.
      if (await streak.markSynced(streakRevision)) {
        await SyncDirty.mark(settings: true);
      }
      // Rows saved before encryption came back readable; push everything
      // once more so the server copy is replaced with sealed text.
      _resealPending = sawPlaintext && !force;
      return const SyncResult(SyncStatus.success, 'تمت المزامنة');
    } catch (_) {
      return const SyncResult(
        SyncStatus.failed,
        'تعذّر المزامنة. يمكنك المحاولة لاحقاً',
      );
    } finally {
      _syncing = false;
      isSyncing.value = false;
      if (_resealPending) {
        _resealPending = false;
        _pending = false;
        unawaited(syncNow(force: true));
      } else if (_pending) {
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

  // Build the push body: changed rows since lastSync (or everything when
  // sendAll), plus delete tombstones so offline removals reach the server.
  Future<Map<String, dynamic>> _buildRequest({
    required DateTime? lastSync,
    required bool sendAll,
  }) async {
    await Future.wait<void>([
      TransactionStore.instance.ensureLoaded(),
      ShoppingListStore.instance.ensureLoaded(),
      RecurringExpenseStore.instance.ensureLoaded(),
      NotificationService.instance.ensureLoaded(),
      CategoryStore.instance.ensureLoaded(),
      ExpensePresetStore.instance.ensureLoaded(),
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

    final categories = [
      for (final item in CategoryStore.instance.entries)
        if (_shouldSend(item.syncUpdatedAt, lastSync, sendAll))
          categoryToSync(item),
    ];

    final presets = [
      for (final item in ExpensePresetStore.instance.items)
        if (_shouldSend(item.syncUpdatedAt, lastSync, sendAll))
          item.toSyncJson(),
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
      'expense_categories': collectionPayload(
        upserts: categories,
        deletes: SyncTombstones.instance.of(SyncCollection.expenseCategories),
      ),
      'expense_presets': collectionPayload(
        upserts: presets,
        deletes: SyncTombstones.instance.of(SyncCollection.expensePresets),
      ),
      'settings': includeSettings ? await _settingsPayload() : null,
    };
  }

  // Snapshot prefs-backed settings (income, currencies, profile) for push.
  Future<Map<String, dynamic>> _settingsPayload() async {
    final store = TransactionStore.instance;
    return {
      'notifications_muted': NotificationService.instance.isMuted,
      'notifications_enabled': !NotificationService.instance.isMuted,
      'monthly_income_amount': store.monthlyIncomeOverrideFor(
        defaultCurrencyCode,
      ),
      'weekly_income_amount': store.weeklyIncomeOverrideFor(
        defaultCurrencyCode,
      ),
      'income_overrides_by_currency': store.incomeOverridesByCurrencyPayload,
      'enabled_currencies': CurrencyStore.instance.enabledCodes,
      'active_currency': CurrencyStore.instance.activeCode,
      'processed_period_keys': store.processedPeriodTokens.toList(),
      'hidden_categories': CategoryStore.instance.hiddenBuiltIns,
      ...await ProfileSync.fields(),
      'updated_at': toSyncIso(await SyncDirty.settingsUpdatedAt()),
    };
  }

  bool _shouldSend(DateTime updatedAt, DateTime? lastSync, bool sendAll) {
    if (sendAll || lastSync == null) return true;
    return newerOrEqual(updatedAt, lastSync);
  }

  // Pull path: apply remote upserts/deletes into each store, then drop
  // tombstones the server has acknowledged. Suppresses dirty marks while applying.
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

      await CategoryStore.instance.applyRemoteSync(
        upserts: asMapList(_collection(body, 'expense_categories')['upserts']),
        deletes: tombstonesFromSync(
          _collection(body, 'expense_categories')['deletes'],
        ),
      );

      await ExpensePresetStore.instance.applyRemoteSync(
        upserts: asMapList(_collection(body, 'expense_presets')['upserts']),
        deletes: tombstonesFromSync(
          _collection(body, 'expense_presets')['deletes'],
        ),
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

  // After a successful pull, remove local delete logs that the server echoed.
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
    await clear('expense_categories', SyncCollection.expenseCategories);
    await clear('expense_presets', SyncCollection.expensePresets);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow());
    }
  }

  // Subscribe to dirty marks, app resume, and reconnect-to-online events.
  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    SyncDirty.addListener(scheduleSync);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_listenForConnectivity());
  }

  // When the device comes back online, flush whatever is still dirty.
  Future<void> _listenForConnectivity() async {
    final connectivity = Connectivity();
    try {
      _wasOnline = _isOnline(await connectivity.checkConnectivity());
    } catch (_) {
      _wasOnline = false;
    }

    _connectivitySub ??= connectivity.onConnectivityChanged.listen((results) {
      final online = _isOnline(results);
      final cameOnline = online && !_wasOnline;
      _wasOnline = online;
      if (cameOnline) {
        unawaited(syncNow());
      }
    });
  }

  static bool _isOnline(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }
}
