// UTC clock helpers for last-write-wins sync comparisons and ISO timestamps.

// Sync metadata timestamps (updated_at, deleted_at, server_time).
DateTime syncNow() => DateTime.now().toUtc();

// Device-local "now" for user-facing event times; does not wait on the network.
DateTime deviceNow() => DateTime.now();

DateTime? parseSyncDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toUtc();
}

DateTime parseSyncDateOrNow(Object? raw) => parseSyncDate(raw) ?? syncNow();

// Event time in the device zone. Missing values stay missing so sync
// cannot invent "now" when a record arrives later.
DateTime? parseEventLocal(Object? raw) => parseSyncDate(raw)?.toLocal();

// Keep the earlier instant so a later server receive time cannot replace
// when the action was actually recorded on the device.
DateTime earlierDeviceEventTime(DateTime current, DateTime incoming) {
  if (incoming.toUtc().isAfter(current.toUtc())) {
    return current.toLocal();
  }
  return incoming.toLocal();
}

// True when [incoming] should win over [current] (equal counts as newer).
bool newerOrEqual(DateTime? incoming, DateTime? current) {
  if (incoming == null) return current == null;
  if (current == null) return true;
  return !incoming.toUtc().isBefore(current.toUtc());
}

String toSyncIso(DateTime? value) =>
    (value ?? syncNow()).toUtc().toIso8601String();
