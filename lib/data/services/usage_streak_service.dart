// Local daily streak. Signed-in users also ship it inside settings sync.

import 'package:flutter/foundation.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/usage/streak_math.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/insights/profile_snapshot.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

/// A streak that just grew by a day on this device: [from] to [to].
class StreakIncrease {
  final int from;
  final int to;

  const StreakIncrease({required this.from, required this.to});
}

class UsageStreakService extends ChangeNotifier {
  UsageStreakService._();

  static final UsageStreakService instance = UsageStreakService._();

  static const String countKey = 'waffer_streak_count';
  static const String lastDayKey = 'waffer_streak_last_date';
  static const String startedKey = 'waffer_usage_started_at';

  StreakSnapshot _state = const StreakSnapshot();
  Future<void>? _loader;
  bool _loaded = false;
  bool _needsPush = false;
  StreakIncrease? _pendingIncrease;

  bool get isLoaded => _loaded;

  int get count => _state.count;

  DateTime? get lastDay => _state.lastDay;

  DateTime? get startedAt => _state.startedAt;

  String get label => _state.hasActivity ? _state.label : 'اليوم الأول';

  String? get lastDayKeyValue => StreakSnapshot.dayKey(_state.lastDay);

  Future<void> ensureLoaded() => _loader ??= _load();

  /// Records today once. Same calendar day does not increase the count.
  Future<StreakSnapshot> recordToday({DateTime? now}) async {
    await ensureLoaded();
    await TransactionStore.instance.ensureLoaded();

    var current = _state;
    if (current.startedAt == null) {
      current = StreakSnapshot(
        count: current.count,
        lastDay: current.lastDay,
        startedAt:
            earliestUsageDate(TransactionStore.instance) ?? now ?? DateTime.now(),
      );
    }

    final next = StreakMath.record(current, now ?? DateTime.now());
    if (!StreakMath.differs(_state, next)) return _state;

    // Opening on the next calendar day: the home screen celebrates it once.
    final previous = _state.count;
    if (previous >= 1 && next.count == previous + 1) {
      _pendingIncrease = StreakIncrease(from: previous, to: next.count);
    }

    _state = next;
    await _persist(markDirty: true);
    notifyListeners();
    return _state;
  }

  /// Merges a remote settings streak without letting an older day erase today.
  Future<void> applyRemote(Map<String, dynamic> settings) async {
    await ensureLoaded();
    final remote = StreakSnapshot(
      count: (settings['streak_count'] as num?)?.toInt() ?? 0,
      lastDay: StreakSnapshot.parseDayKey(
        settings['streak_last_date']?.toString(),
      ),
      startedAt: DateTime.tryParse(
        settings['usage_started_at']?.toString() ?? '',
      )?.toLocal(),
    );
    if (remote.lastDay == null &&
        remote.startedAt == null &&
        remote.count <= 0) {
      return;
    }

    final merged = StreakMath.merge(_state, remote);
    final changedLocal = StreakMath.differs(_state, merged);
    if (StreakMath.differs(remote, merged)) {
      _needsPush = true;
    }
    if (!changedLocal) return;

    _state = merged;
    await _persist(markDirty: false);
    notifyListeners();
  }

  Map<String, dynamic> syncFields() {
    return {
      if (_state.startedAt != null)
        'usage_started_at': _state.startedAt!.toUtc().toIso8601String(),
      if (_state.lastDay != null) ...{
        'streak_count': _state.count,
        'streak_last_date': StreakSnapshot.dayKey(_state.lastDay),
      },
    };
  }

  /// The increase recorded by the last [recordToday], handed out once.
  StreakIncrease? takeIncrease() {
    final value = _pendingIncrease;
    _pendingIncrease = null;
    return value;
  }

  /// True once when local streak should be pushed after a pull.
  bool consumePushRequest() {
    final value = _needsPush;
    _needsPush = false;
    return value;
  }

  void resetCache() {
    _state = const StreakSnapshot();
    _loaded = false;
    _loader = null;
    _needsPush = false;
    _pendingIncrease = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    final started = DateTime.tryParse(prefs.getString(startedKey) ?? '');
    _state = StreakSnapshot(
      count: prefs.getInt(countKey) ?? 0,
      lastDay: StreakSnapshot.parseDayKey(prefs.getString(lastDayKey)),
      startedAt: started?.toLocal(),
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist({required bool markDirty}) async {
    final prefs = await AppPrefs.instance;
    await prefs.setInt(countKey, _state.count);
    final day = StreakSnapshot.dayKey(_state.lastDay);
    if (day == null) {
      await prefs.remove(lastDayKey);
    } else {
      await prefs.setString(lastDayKey, day);
    }
    final started = _state.startedAt;
    if (started == null) {
      await prefs.remove(startedKey);
    } else {
      await prefs.setString(startedKey, started.toUtc().toIso8601String());
    }
    if (markDirty) {
      await SyncDirty.mark(settings: true);
    }
  }
}
