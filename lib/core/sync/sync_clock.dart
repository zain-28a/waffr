/// UTC helpers for last-write-wins comparisons.
///
/// User events use [deviceNow]. [syncNow] is only for sync metadata.
DateTime syncNow() => DateTime.now().toUtc();

/// The device's current local time. This does not wait for a network clock.
DateTime deviceNow() => DateTime.now();

DateTime? parseSyncDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toUtc();
}

DateTime parseSyncDateOrNow(Object? raw) => parseSyncDate(raw) ?? syncNow();

/// Event time in the device zone. Missing values stay missing so sync
/// cannot invent "now" when a record is received later.
DateTime? parseEventLocal(Object? raw) => parseSyncDate(raw)?.toLocal();

/// Keeps the earlier instant. A later server receive time must not replace
/// the moment the action was recorded on the device.
DateTime earlierDeviceEventTime(DateTime current, DateTime incoming) {
  if (incoming.toUtc().isAfter(current.toUtc())) {
    return current.toLocal();
  }
  return incoming.toLocal();
}

bool newerOrEqual(DateTime? incoming, DateTime? current) {
  if (incoming == null) return current == null;
  if (current == null) return true;
  return !incoming.toUtc().isBefore(current.toUtc());
}

String toSyncIso(DateTime? value) =>
    (value ?? syncNow()).toUtc().toIso8601String();
