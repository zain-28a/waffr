import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:waffr/data/models/app_notification.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/core/sync/sync_dirty.dart';
import 'package:waffr/core/sync/sync_mapper.dart';
import 'package:waffr/core/sync/sync_merge.dart';
import 'package:waffr/core/sync/sync_tombstones.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/data/services/system_notifications.dart';
import 'package:waffr/data/services/usage_streak_service.dart';

/// In-app notification engine for balance, spending, goals, savings, and periods.
///
/// Storage (AppPrefs): encoded [AppNotification] list, mute flag, dedupe
/// [eventKey] set, and a [_NotificationSnapshot] of last-known ratios and IDs.
/// Evaluation runs after [TransactionStore] changes ([listen] → [evaluate]), or
/// via [seedIfNeeded] / [evaluate]; screens only display the feed—do not call
/// from `build()`. Alerts fire when values cross thresholds vs the snapshot,
/// not on every load. Thresholds ([NotificationThresholds]): remaining balance
/// 25/10%; spending 50%; goals 50/75%; large expense = 2× prior average once
/// there are more than four expenses (scheduled bills excluded). Every message
/// names the amount or goal it is about.
class NotificationService extends ChangeNotifier {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _itemsKey = 'waffer_notifications';
  static const String _mutedKey = 'waffer_notifications_muted';
  static const String _eventKeysKey = 'waffer_notification_event_keys';
  static const String _snapshotKey = 'waffer_notification_snapshot';

  final List<AppNotification> _items = [];
  final Set<String> _eventKeys = {};

  _NotificationSnapshot _snapshot = _NotificationSnapshot.empty();

  Future<void>? _loader;
  bool _loaded = false;
  bool _muted = false;
  bool _listening = false;
  bool _evaluating = false;

  bool get isLoaded => _loaded;

  bool get isMuted => _muted;

  int get unreadCount =>
      _items.where((item) => !item.isRead).length;

  List<AppNotification> get notifications => List.unmodifiable(_items);

  Future<void> ensureLoaded() => _loader ??= _load();

  /// Subscribes to [TransactionStore] so each change schedules [evaluate].
  void listen() {
    if (_listening) return;
    _listening = true;
    TransactionStore.instance.addListener(_onStoreChanged);
  }

  /// Captures the first store baseline before due periods are processed.
  Future<void> seedIfNeeded() async {
    await ensureLoaded();
    if (_snapshot.initialized) return;

    _applyBaseline(TransactionStore.instance);
    await _persist();
    notifyListeners();
  }

  /// Compares current store state to the snapshot and emits new alerts.
  Future<void> evaluate() async {
    if (_evaluating) return;
    _evaluating = true;

    try {
      await ensureLoaded();
      final store = TransactionStore.instance;
      await store.ensureLoaded();

      if (!_snapshot.initialized) {
        _applyBaseline(store);
        await _persist();
        notifyListeners();
        return;
      }

      var changed = false;
      changed |= _evaluateBalance(store);
      changed |= _evaluateSpending(store);
      changed |= _evaluateGoals(store);
      changed |= _evaluateTransfers(store);
      changed |= _evaluatePeriods(store);
      changed |= _evaluateLargeExpenses(store);

      final previous = _snapshot;
      _refreshSnapshot(store);

      if (changed) {
        await _persist();
        notifyListeners();
      } else if (!_snapshot.sameAs(previous)) {
        await _persistSnapshot();
      }
    } finally {
      _evaluating = false;
    }
  }

  /// Public entry for future features; respects mute and event-key dedupe.
  Future<bool> add({
    required NotificationType type,
    required String title,
    required String message,
    required String eventKey,
    String? relatedId,
    Map<String, String> metadata = const {},
    DateTime? createdAt,
  }) async {
    await ensureLoaded();
    final created = _tryAdd(
      type: type,
      title: title,
      message: message,
      eventKey: eventKey,
      relatedId: relatedId,
      metadata: metadata,
      createdAt: createdAt,
    );
    if (!created) return false;
    await _persist();
    notifyListeners();
    return true;
  }

  /// Persists mute state and marks settings dirty for sync.
  Future<void> setMuted(bool muted) async {
    await ensureLoaded();
    if (_muted == muted) return;
    _muted = muted;
    final prefs = await AppPrefs.instance;
    await prefs.setBool(_mutedKey, muted);
    await SyncDirty.mark(settings: true);
    notifyListeners();
    unawaited(
      SystemNotifications.instance.syncStreakReminder(
        enabled: !muted && UsageStreakService.instance.count >= 2,
        streakCount: UsageStreakService.instance.count,
      ),
    );
  }

  Future<void> toggleMuted() => setMuted(!_muted);

  /// Marks a single notification read and saves the list.
  Future<void> markRead(String id) async {
    await ensureLoaded();
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || _items[index].isRead) return;
    _items[index] = _items[index].copyWith(isRead: true);
    await _persistItems();
    notifyListeners();
  }

  /// Marks every unread item read in one persist.
  Future<void> markAllRead() async {
    await ensureLoaded();
    if (_items.every((item) => item.isRead)) return;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].isRead) {
        _items[i] = _items[i].copyWith(isRead: true);
      }
    }
    await _persistItems();
    notifyListeners();
  }

  /// Clears the feed only; leaves balance, savings, goals, and mute untouched.
  Future<void> clearHistory() async {
    await ensureLoaded();
    if (_items.isEmpty) return;
    await SyncTombstones.instance.addMany(
      SyncCollection.notifications,
      _items.map((item) => item.id),
    );
    _items.clear();
    await _persistItems();
    notifyListeners();
  }

  /// Merges remote notification upserts/deletes and optional mute into local state.
  Future<void> applyRemoteSync({
    required List<Map<String, dynamic>> upserts,
    required List<SyncTombstone> deletes,
    bool? muted,
  }) async {
    await ensureLoaded();

    var changed = mergeRemoteRecords<AppNotification>(
      items: _items,
      upserts: [
        for (final raw in upserts)
          if (notificationFromSync(raw) != null) notificationFromSync(raw)!,
      ],
      deletes: deletes,
      collection: SyncCollection.notifications,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );

    for (final item in _items) {
      _eventKeys.add(item.eventKey);
    }

    if (muted != null && muted != _muted) {
      _muted = muted;
      changed = true;
    }

    if (!changed) return;

    _sort();
    await _persist();
    notifyListeners();
  }

  /// Drops in-memory state after a full local data wipe.
  void resetCache() {
    _items.clear();
    _eventKeys.clear();
    _snapshot = _NotificationSnapshot.empty();
    _muted = false;
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  void _onStoreChanged() {
    scheduleMicrotask(() {
      unawaited(evaluate());
    });
  }

  /// Loads items, event keys, mute, and snapshot from AppPrefs.
  Future<void> _load() async {
    final prefs = await AppPrefs.instance;

    _items
      ..clear()
      ..addAll(
        (prefs.getStringList(_itemsKey) ?? const [])
            .map(AppNotification.decode)
            .whereType<AppNotification>(),
      );
    _sort();

    _eventKeys
      ..clear()
      ..addAll(prefs.getStringList(_eventKeysKey) ?? const []);

    for (final item in _items) {
      _eventKeys.add(item.eventKey);
    }

    _muted = prefs.getBool(_mutedKey) ?? false;
    _snapshot = _NotificationSnapshot.decode(prefs.getString(_snapshotKey));
    _loaded = true;
    notifyListeners();
  }

  /// Seeds snapshot from the store and pretends completed goals already notified.
  void _applyBaseline(TransactionStore store) {
    _snapshot = _NotificationSnapshot.fromStore(store);

    for (final goal in store.goals) {
      if (!goal.isCompleted) continue;
      _eventKeys.add(_goalReachedKey(goal.id));
      for (final percent in NotificationThresholds.goalPercents) {
        _eventKeys.add(_goalProgressKey(goal.id, percent));
      }
    }
  }

  void _refreshSnapshot(TransactionStore store) {
    _snapshot = _NotificationSnapshot.fromStore(store);
  }

  /// Fires when remaining balance drops through 30%, 20%, or 10%.
  bool _evaluateBalance(TransactionStore store) {
    if (store.maxBalance <= 0) return false;

    final current = store.remainingRatio;
    final previous = _snapshot.remainingRatio;
    if (previous == null) return false;

    final crossed = <int>[];
    for (final percent in NotificationThresholds.remainingPercents) {
      final threshold = percent / 100;
      if (previous > threshold && current <= threshold) {
        crossed.add(percent);
      }
    }
    if (crossed.isEmpty) return false;

    final percent = crossed.reduce((a, b) => a < b ? a : b);
    final cycle = _incomeCycle(store);
    final left = '${formatMoney(store.balance)} $currencyLabel';
    final income = '${formatMoney(store.maxBalance)} $currencyLabel';
    return _tryAdd(
      type: NotificationType.balanceWarning,
      title: percent <= 10 ? 'رصيدك على وشك النفاد' : 'بقي ربع رصيدك',
      message: percent <= 10
          ? 'بقي $left فقط من أصل $income.'
          : 'المتاح الآن $left من أصل $income. راجع مصروفاتك حتى الدخل القادم.',
      eventKey: 'balanceWarning:$percent:$cycle',
      metadata: {
        'percent': '$percent',
        'cycle': cycle,
      },
    );
  }

  /// Fires when spending climbs through 50%, 70%, 80%, or 90% of max balance.
  bool _evaluateSpending(TransactionStore store) {
    if (store.maxBalance <= 0) return false;

    final current = store.totalExpense / store.maxBalance;
    final previous = _snapshot.spentRatio;
    if (previous == null) return false;

    final crossed = <int>[];
    for (final percent in NotificationThresholds.spendingPercents) {
      final threshold = percent / 100;
      if (previous < threshold && current >= threshold) {
        crossed.add(percent);
      }
    }
    if (crossed.isEmpty) return false;

    final percent = crossed.reduce((a, b) => a > b ? a : b);
    final cycle = _incomeCycle(store);
    return _tryAdd(
      type: NotificationType.highSpending,
      title: 'صرفت $percent% من دخلك',
      message: 'صرفت ${formatMoney(store.totalExpense)} من '
          '${formatMoney(store.maxBalance)} $currencyLabel، '
          'والمتاح الآن ${formatMoney(store.balance)} $currencyLabel.',
      eventKey: 'highSpending:$percent:$cycle',
      metadata: {
        'percent': '$percent',
        'cycle': cycle,
      },
    );
  }

  /// Goal reached at 100%, or progress at 25%/50%/75% crossings.
  bool _evaluateGoals(TransactionStore store) {
    var changed = false;

    for (final goal in store.goals) {
      final current = store.goalRatio(goal);
      final previous = _snapshot.goalRatios[goal.id];

      if (goal.isCompleted) {
        changed |= _tryAdd(
          type: NotificationType.goalReached,
          title: 'اكتمل هدف ${goal.name}',
          message: 'جمعت ${formatMoney(goal.targetAmount)} '
              '${currencyLabelFor(goal.currencyCode)} المطلوبة لهذا الهدف.',
          eventKey: _goalReachedKey(goal.id),
          relatedId: goal.id,
          metadata: {
            'goalName': goal.name,
            'percent': '100',
          },
          createdAt: goal.completedAt,
        );
        continue;
      }

      if (previous == null) continue;

      final crossed = <int>[];
      for (final percent in NotificationThresholds.goalPercents) {
        final threshold = percent / 100;
        if (previous < threshold && current >= threshold) {
          crossed.add(percent);
        }
      }
      if (crossed.isEmpty) continue;

      final percent = crossed.reduce((a, b) => a > b ? a : b);
      final symbol = currencyLabelFor(goal.currencyCode);
      changed |= _tryAdd(
        type: NotificationType.goalProgress,
        title: 'هدف ${goal.name}: $percent%',
        message: 'وفّرت ${formatMoney(store.currentSaved(goal))} من '
            '${formatMoney(goal.targetAmount)} $symbol.',
        eventKey: _goalProgressKey(goal.id, percent),
        relatedId: goal.id,
        metadata: {
          'goalName': goal.name,
          'percent': '$percent',
        },
      );
    }

    return changed;
  }

  /// Notifies for new period-leftover or goal-periodic savings transfers.
  bool _evaluateTransfers(TransactionStore store) {
    var changed = false;

    for (final item in store.savingsTransfers) {
      if (!item.isSavingsIn) continue;
      if (_snapshot.knownTransactionIds.contains(item.id)) continue;

      final kind = item.transferKind;
      if (kind != SavingsTransferKind.periodLeftover &&
          kind != SavingsTransferKind.goalPeriodic) {
        continue;
      }

      final periodLabel = _periodAdjective(item);
      final goalName = _goalName(store, item.goalId);
      final amount =
          '${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)}';
      final weekly = periodLabel == 'الأسبوعية';

      changed |= _tryAdd(
        type: NotificationType.savingsTransferred,
        title: 'أُضيف $amount إلى التوفير',
        message: kind == SavingsTransferKind.goalPeriodic
            ? 'الدفعة الدورية${goalName == null ? '' : ' لهدف $goalName'}.'
            : 'المتبقي من دخل ${weekly ? 'الأسبوع' : 'الشهر'} الماضي'
                '${goalName == null ? '' : '، ضمن هدف $goalName'}.',
        eventKey: 'savingsTransfer:${item.id}',
        relatedId: item.id,
        metadata: {
          'amount': '${item.amount}',
          'periodType': kind == SavingsTransferKind.goalPeriodic
              ? 'goalPeriodic'
              : (item.processedPeriodKey?.startsWith('w:') == true
                  ? 'weekly'
                  : 'monthly'),
          'periodKey': ?item.processedPeriodKey,
          'goalName': ?goalName,
        },
        createdAt: item.dateTime,
      );
    }

    return changed;
  }

  /// Period-completed alerts when leftover was processed without a transfer row.
  bool _evaluatePeriods(TransactionStore store) {
    var changed = false;

    for (final token in store.processedPeriodTokens) {
      if (!token.startsWith('leftover:')) continue;
      if (_snapshot.knownProcessedTokens.contains(token)) continue;

      final periodKey = token.substring('leftover:'.length);
      if (periodKey.isEmpty) continue;

      final alreadyTransferred = _items.any(
        (item) =>
            item.type == NotificationType.savingsTransferred &&
            item.metadata['periodKey'] == periodKey,
      );
      if (alreadyTransferred) continue;

      final hasTransfer = store.savingsTransfers.any(
        (item) =>
            item.isSavingsIn &&
            item.transferKind == SavingsTransferKind.periodLeftover &&
            item.processedPeriodKey == periodKey,
      );
      if (hasTransfer) continue;

      final weekly = periodKey.contains('w:');
      final span = weekly ? 'الأسبوع' : 'الشهر';
      changed |= _tryAdd(
        type: NotificationType.recurringPeriodCompleted,
        title: 'انتهى $span دون توفير',
        message: 'لم يتبقَّ من دخل $span الماضي مبلغ يُنقل إلى التوفير.',
        eventKey: 'periodCompleted:$periodKey',
        relatedId: periodKey,
        metadata: {
          'periodKey': periodKey,
          'periodType': weekly ? 'weekly' : 'monthly',
        },
      );
    }

    return changed;
  }

  /// Flags expenses ≥ 2× the average of earlier ones (needs >4 expenses).
  bool _evaluateLargeExpenses(TransactionStore store) {
    final expenses = store.expenses;
    if (expenses.length <= NotificationThresholds.minExpensesForLarge) {
      return false;
    }

    var changed = false;
    final chronological = [...expenses]
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    for (var i = 0; i < chronological.length; i++) {
      final expense = chronological[i];
      if (_snapshot.knownTransactionIds.contains(expense.id)) continue;
      if (i < NotificationThresholds.minExpensesForLarge) continue;
      // Scheduled bills have their own notice and are expected amounts.
      if (RecurringExpense.isRecurringSource(expense.sourceId)) continue;

      final prior = chronological.sublist(0, i);
      final average =
          prior.fold<double>(0, (sum, item) => sum + item.amount) / prior.length;
      if (average <= 0) continue;
      if (expense.amount < average * NotificationThresholds.largeExpenseMultiplier) {
        continue;
      }

      changed |= _tryAdd(
        type: NotificationType.largeExpense,
        title: 'مصروف أعلى من المعتاد',
        message: '${formatMoney(expense.amount)} '
            '${currencyLabelFor(expense.currencyCode)} على '
            '${categoryFor(expense.category).label}، أي ضعف متوسط مصروفاتك أو أكثر.',
        eventKey: 'largeExpense:${expense.id}',
        relatedId: expense.id,
        metadata: {
          'amount': '${expense.amount}',
          'category': ?expense.category,
        },
        createdAt: expense.dateTime,
      );
    }

    return changed;
  }

  /// Dedupes by [eventKey]; when muted, keys are still claimed so events stay quiet.
  bool _tryAdd({
    required NotificationType type,
    required String title,
    required String message,
    required String eventKey,
    String? relatedId,
    Map<String, String> metadata = const {},
    DateTime? createdAt,
  }) {
    if (_eventKeys.contains(eventKey)) return false;
    _eventKeys.add(eventKey);

    if (_muted) return false;

    _items.add(
      AppNotification(
        id: AppNotification.newId(),
        type: type,
        title: title,
        message: message,
        createdAt: (createdAt ?? deviceNow()).toLocal(),
        eventKey: eventKey,
        relatedId: relatedId,
        metadata: metadata,
      ),
    );
    _sort();
    unawaited(
      SystemNotifications.instance.present(
        eventKey: eventKey,
        title: title,
        body: message,
      ),
    );
    return true;
  }

  void _sort() {
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  String _incomeCycle(TransactionStore store) =>
      'income:${store.maxBalance.round()}';

  String _goalReachedKey(String goalId) => 'goalReached:$goalId';

  String _goalProgressKey(String goalId, int percent) =>
      'goalProgress:$goalId:$percent';

  String? _goalName(TransactionStore store, String? goalId) {
    if (goalId == null) return null;
    for (final goal in store.goals) {
      if (goal.id == goalId) return goal.name;
    }
    return null;
  }

  /// Arabic weekly/monthly adjective from period key or recurring frequency.
  String? _periodAdjective(WaffrTransaction item) {
    final key = item.processedPeriodKey;
    if (key != null) {
      if (key.startsWith('w:')) return 'الأسبوعية';
      if (key.startsWith('m:')) return 'الشهرية';
    }
    return switch (item.frequency) {
      RecurringFrequency.weekly => 'الأسبوعية',
      RecurringFrequency.monthly => 'الشهرية',
      RecurringFrequency.none => null,
    };
  }

  /// Writes items, event keys, mute, and snapshot; marks sync dirty.
  Future<void> _persist() async {
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(
      _itemsKey,
      _items.map((item) => item.encode()).toList(),
    );
    await prefs.setStringList(_eventKeysKey, _eventKeys.toList());
    await prefs.setBool(_mutedKey, _muted);
    await prefs.setString(_snapshotKey, _snapshot.encode());
    await SyncDirty.mark();
  }

  Future<void> _persistItems() async {
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(
      _itemsKey,
      _items.map((item) => item.encode()).toList(),
    );
    await SyncDirty.mark();
  }

  Future<void> _persistSnapshot() async {
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(_eventKeysKey, _eventKeys.toList());
    await prefs.setString(_snapshotKey, _snapshot.encode());
  }
}

/// Last-seen balances, goal ratios, and known IDs used to detect crossings.
class _NotificationSnapshot {
  final bool initialized;
  final double? remainingRatio;
  final double? spentRatio;
  final Map<String, double> goalRatios;
  final Set<String> knownTransactionIds;
  final Set<String> knownProcessedTokens;

  const _NotificationSnapshot({
    required this.initialized,
    required this.remainingRatio,
    required this.spentRatio,
    required this.goalRatios,
    required this.knownTransactionIds,
    required this.knownProcessedTokens,
  });

  bool sameAs(_NotificationSnapshot other) {
    if (identical(this, other)) return true;
    if (initialized != other.initialized) return false;
    if (remainingRatio != other.remainingRatio) return false;
    if (spentRatio != other.spentRatio) return false;
    if (goalRatios.length != other.goalRatios.length) return false;
    if (knownTransactionIds.length != other.knownTransactionIds.length) {
      return false;
    }
    if (knownProcessedTokens.length != other.knownProcessedTokens.length) {
      return false;
    }
    for (final entry in goalRatios.entries) {
      if (other.goalRatios[entry.key] != entry.value) return false;
    }
    return knownTransactionIds.containsAll(other.knownTransactionIds) &&
        knownProcessedTokens.containsAll(other.knownProcessedTokens);
  }

  factory _NotificationSnapshot.empty() {
    return const _NotificationSnapshot(
      initialized: false,
      remainingRatio: null,
      spentRatio: null,
      goalRatios: {},
      knownTransactionIds: {},
      knownProcessedTokens: {},
    );
  }

  /// Builds a snapshot from the live [TransactionStore].
  factory _NotificationSnapshot.fromStore(TransactionStore store) {
    final spent =
        store.maxBalance <= 0 ? 0.0 : store.totalExpense / store.maxBalance;
    return _NotificationSnapshot(
      initialized: true,
      remainingRatio: store.remainingRatio,
      spentRatio: spent,
      goalRatios: {
        for (final goal in store.goals) goal.id: store.goalRatio(goal),
      },
      knownTransactionIds: {
        for (final item in store.transactions) item.id,
      },
      knownProcessedTokens: Set<String>.of(store.processedPeriodTokens),
    );
  }

  String encode() => jsonEncode({
        'initialized': initialized,
        'remainingRatio': remainingRatio,
        'spentRatio': spentRatio,
        'goalRatios': goalRatios,
        'knownTransactionIds': knownTransactionIds.toList(),
        'knownProcessedTokens': knownProcessedTokens.toList(),
      });

  /// Restores a snapshot from prefs JSON; empty on missing or corrupt input.
  static _NotificationSnapshot decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return _NotificationSnapshot.empty();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _NotificationSnapshot.empty();

      final ratios = <String, double>{};
      final rawRatios = decoded['goalRatios'];
      if (rawRatios is Map) {
        rawRatios.forEach((key, value) {
          final amount = (value as num?)?.toDouble();
          if (amount == null) return;
          ratios[key.toString()] = amount;
        });
      }

      return _NotificationSnapshot(
        initialized: decoded['initialized'] == true,
        remainingRatio: (decoded['remainingRatio'] as num?)?.toDouble(),
        spentRatio: (decoded['spentRatio'] as num?)?.toDouble(),
        goalRatios: ratios,
        knownTransactionIds: {
          for (final item in decoded['knownTransactionIds'] as List? ?? const [])
            item.toString(),
        },
        knownProcessedTokens: {
          for (final item in decoded['knownProcessedTokens'] as List? ?? const [])
            item.toString(),
        },
      );
    } catch (_) {
      return _NotificationSnapshot.empty();
    }
  }
}

/// Groups notifications into today / yesterday / this week / month buckets.
class NotificationTimeGroup {
  final String label;
  final List<AppNotification> items;

  const NotificationTimeGroup({
    required this.label,
    required this.items,
  });

  /// Buckets by calendar day relative to [now] (Arabic section labels).
  static List<NotificationTimeGroup> from(
    List<AppNotification> notifications, {
    DateTime? now,
  }) {
    if (notifications.isEmpty) return const [];

    final moment = now ?? DateTime.now();
    final today = DateTime(moment.year, moment.month, moment.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = CalendarPeriod.weekStart(today);

    final todayItems = <AppNotification>[];
    final yesterdayItems = <AppNotification>[];
    final weekItems = <AppNotification>[];
    final older = <String, List<AppNotification>>{};

    for (final item in notifications) {
      final day = DateTime(
        item.createdAt.year,
        item.createdAt.month,
        item.createdAt.day,
      );

      if (day == today) {
        todayItems.add(item);
      } else if (day == yesterday) {
        yesterdayItems.add(item);
      } else if (!day.isBefore(weekStart) && day.isBefore(yesterday)) {
        weekItems.add(item);
      } else {
        final key = '${day.year}-${day.month.toString().padLeft(2, '0')}';
        older.putIfAbsent(key, () => []).add(item);
      }
    }

    final groups = <NotificationTimeGroup>[];
    if (todayItems.isNotEmpty) {
      groups.add(NotificationTimeGroup(label: 'اليوم', items: todayItems));
    }
    if (yesterdayItems.isNotEmpty) {
      groups.add(NotificationTimeGroup(label: 'أمس', items: yesterdayItems));
    }
    if (weekItems.isNotEmpty) {
      groups.add(NotificationTimeGroup(label: 'هذا الأسبوع', items: weekItems));
    }

    final monthKeys = older.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final key in monthKeys) {
      final parts = key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final label = year == today.year
          ? CalendarPeriod.monthName(month)
          : '${CalendarPeriod.monthName(month)} $year';
      groups.add(NotificationTimeGroup(label: label, items: older[key]!));
    }

    return groups;
  }
}
