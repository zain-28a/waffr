import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';

/// Last-write-wins merge against the in-memory local list.
bool mergeRemoteRecords<T>({
  required List<T> items,
  required List<T> upserts,
  required List<SyncTombstone> deletes,
  required SyncCollection collection,
  required String Function(T item) idOf,
  required DateTime Function(T item) updatedOf,
}) {
  var changed = false;
  final byId = <String, T>{
    for (final item in items) idOf(item): item,
  };

  for (final tombstone in deletes) {
    final existing = byId[tombstone.clientId];
    if (existing == null) continue;
    if (!newerOrEqual(tombstone.deletedAt, updatedOf(existing))) {
      continue;
    }
    items.removeWhere((item) => idOf(item) == tombstone.clientId);
    byId.remove(tombstone.clientId);
    changed = true;
  }

  for (final incoming in upserts) {
    final id = idOf(incoming);
    final localTomb = SyncTombstones.instance.find(collection, id);
    if (localTomb != null &&
        newerOrEqual(localTomb.deletedAt, updatedOf(incoming))) {
      continue;
    }

    final existing = byId[id];
    if (existing != null &&
        !newerOrEqual(updatedOf(incoming), updatedOf(existing))) {
      continue;
    }

    if (existing == null) {
      items.add(incoming);
    } else {
      final index = items.indexWhere((item) => idOf(item) == id);
      if (index >= 0) {
        items[index] = incoming;
      }
    }
    byId[id] = incoming;
    changed = true;
  }

  return changed;
}
