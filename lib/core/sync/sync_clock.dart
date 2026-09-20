/// UTC helpers for last-write-wins comparisons.
DateTime syncNow() => DateTime.now().toUtc();

DateTime? parseSyncDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toUtc();
}

DateTime parseSyncDateOrNow(Object? raw) => parseSyncDate(raw) ?? syncNow();

bool newerOrEqual(DateTime? incoming, DateTime? current) {
  if (incoming == null) return current == null;
  if (current == null) return true;
  return !incoming.toUtc().isBefore(current.toUtc());
}

String toSyncIso(DateTime? value) =>
    (value ?? syncNow()).toUtc().toIso8601String();
