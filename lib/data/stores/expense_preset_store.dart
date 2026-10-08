// Saved expense presets: local prefs, sync merge, and tombstones on delete.

import 'package:flutter/foundation.dart';
import 'package:waffer/core/prefs/app_prefs.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/sync/sync_merge.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';
import 'package:waffer/data/models/expense_preset.dart';

class ExpensePresetStore extends ChangeNotifier {
  ExpensePresetStore._();

  static final ExpensePresetStore instance = ExpensePresetStore._();

  static const String itemsKey = 'expense_presets';

  final List<ExpensePreset> _items = [];
  Future<void>? _loader;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Newest first.
  List<ExpensePreset> get items => List.unmodifiable(_items);

  Future<void> ensureLoaded() => _loader ??= _load();

  /// Saves [preset] unless one with the same details already exists.
  /// Returns the stored preset (the existing one for a duplicate).
  Future<ExpensePreset> add(ExpensePreset preset) async {
    await ensureLoaded();
    for (final item in _items) {
      if (item.sameDetailsAs(preset)) return item;
    }
    _items.insert(0, preset);
    await _persist();
    notifyListeners();
    return preset;
  }

  Future<bool> remove(String id) async {
    await ensureLoaded();
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length == before) return false;
    await SyncTombstones.instance.add(SyncCollection.expensePresets, id);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> applyRemoteSync({
    required List<Map<String, dynamic>> upserts,
    required List<SyncTombstone> deletes,
  }) async {
    await ensureLoaded();

    final changed = mergeRemoteRecords<ExpensePreset>(
      items: _items,
      upserts: [
        for (final raw in upserts)
          if (ExpensePreset.fromSync(raw) != null) ExpensePreset.fromSync(raw)!,
      ],
      deletes: deletes,
      collection: SyncCollection.expensePresets,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );
    if (!changed) return;

    _sort();
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
    _items
      ..clear()
      ..addAll(
        (prefs.getStringList(itemsKey) ?? const [])
            .map(ExpensePreset.decode)
            .whereType<ExpensePreset>(),
      );
    _sort();
    _loaded = true;
    notifyListeners();
  }

  void _sort() {
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
