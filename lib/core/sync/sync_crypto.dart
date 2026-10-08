// Seals private text in the /sync request and opens it in the reply.
// Amounts, dates, ids and the profile stay readable on the server.

import 'package:waffer/core/security/data_key.dart';

const Map<String, List<String>> privateSyncFields = {
  'transactions': ['category', 'payment_method', 'note'],
  'savings_transfers': ['note'],
  'savings_goals': ['name'],
  'shopping_items': ['name'],
  'recurring_expenses': ['category', 'payment_method', 'note'],
  'notifications': ['title', 'message'],
  'expense_categories': ['label'],
};

// Notification metadata can carry goal names and categories.
const String _metadataField = 'metadata';

Future<void> sealSyncRequest(
  Map<String, dynamic> request,
  DataCipher cipher,
) async {
  for (final row in _rows(request)) {
    for (final field in privateSyncFields[row.collection]!) {
      final value = row.data[field];
      if (value is String) {
        row.data[field] = await cipher.seal(value);
      }
    }
    final metadata = row.data[_metadataField];
    if (metadata is Map) {
      // A new map: the payload may share this one with the local model.
      row.data[_metadataField] = {
        for (final entry in metadata.entries)
          entry.key.toString(): await cipher.seal(entry.value?.toString() ?? ''),
      };
    }
  }
}

// Returns true when the reply held text the server stored unencrypted, so
// the caller can push it back sealed.
Future<bool> openSyncResponse(
  Map<String, dynamic> body,
  DataCipher cipher,
) async {
  var sawPlaintext = false;

  Future<String?> open(String value) {
    if (value.isNotEmpty && !DataCipher.isSealed(value)) {
      sawPlaintext = true;
    }
    return cipher.open(value);
  }

  for (final row in _rows(body)) {
    for (final field in privateSyncFields[row.collection]!) {
      final value = row.data[field];
      if (value is String) {
        row.data[field] = await open(value);
      }
    }
    final metadata = row.data[_metadataField];
    if (metadata is Map) {
      row.data[_metadataField] = {
        for (final entry in metadata.entries)
          entry.key.toString(): entry.value is String
              ? await open(entry.value as String) ?? ''
              : entry.value,
      };
    }
  }
  return sawPlaintext;
}

Iterable<({String collection, Map data})> _rows(
  Map<String, dynamic> payload,
) sync* {
  for (final collection in privateSyncFields.keys) {
    final section = payload[collection];
    if (section is! Map) continue;
    final upserts = section['upserts'];
    if (upserts is! List) continue;
    for (final row in upserts) {
      if (row is Map) yield (collection: collection, data: row);
    }
  }
}
