import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/sync/sync_clock.dart';

enum SyncCollection {
  transactions,
  savingsGoals,
  savingsTransfers,
  shoppingLists,
  shoppingItems,
  recurringExpenses,
  notifications,
  expenseCategories,
}

class SyncTombstone {
  final String clientId;
  final DateTime deletedAt;

  const SyncTombstone({
    required this.clientId,
    required this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'deleted_at': toSyncIso(deletedAt),
      };

  static SyncTombstone? decode(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['client_id']?.toString().trim() ??
        raw['clientId']?.toString().trim() ??
        '';
    if (id.isEmpty) return null;
    return SyncTombstone(
      clientId: id,
      deletedAt: parseSyncDateOrNow(raw['deleted_at'] ?? raw['deletedAt']),
    );
  }
}

/// Local delete log so offline removals can reach the server later.
class SyncTombstones {
  SyncTombstones._();

  static final SyncTombstones instance = SyncTombstones._();

  static const String _key = 'waffer_sync_tombstones';

  final Map<SyncCollection, Map<String, SyncTombstone>> _items = {
    for (final collection in SyncCollection.values) collection: {},
  };

  Future<void>? _loader;
  bool _loaded = false;

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> add(SyncCollection collection, String clientId) async {
    await ensureLoaded();
    final id = clientId.trim();
    if (id.isEmpty) return;
    _items[collection]![id] = SyncTombstone(
      clientId: id,
      deletedAt: syncNow(),
    );
    await _persist();
  }

  Future<void> addMany(SyncCollection collection, Iterable<String> ids) async {
    await ensureLoaded();
    final now = syncNow();
    var changed = false;
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      _items[collection]![id] = SyncTombstone(clientId: id, deletedAt: now);
      changed = true;
    }
    if (changed) await _persist();
  }

  List<SyncTombstone> of(SyncCollection collection) {
    return List<SyncTombstone>.unmodifiable(
      _items[collection]?.values ?? const [],
    );
  }

  SyncTombstone? find(SyncCollection collection, String clientId) {
    return _items[collection]?[clientId];
  }

  Future<void> remove(SyncCollection collection, Iterable<String> ids) async {
    await ensureLoaded();
    var changed = false;
    final bucket = _items[collection]!;
    for (final id in ids) {
      if (bucket.remove(id) != null) changed = true;
    }
    if (changed) await _persist();
  }

  Future<void> clearAll() async {
    await ensureLoaded();
    for (final bucket in _items.values) {
      bucket.clear();
    }
    await _persist();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final collection in SyncCollection.values) {
            final list = decoded[collection.name];
            if (list is! List) continue;
            for (final item in list) {
              final tombstone = SyncTombstone.decode(item);
              if (tombstone == null) continue;
              _items[collection]![tombstone.clientId] = tombstone;
            }
          }
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        for (final collection in SyncCollection.values)
          collection.name: _items[collection]!
              .values
              .map((item) => item.toJson())
              .toList(),
      }),
    );
  }
}
