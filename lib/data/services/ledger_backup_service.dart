// Encrypted backup files of the on-device ledger, made and restored by the
// user. The only recovery path that works for guests, works offline, and
// moves between Android and iOS.
//
// What goes in is exactly what a full sync push carries (sync_request.dart):
// every row of every store plus the settings and profile. Restoring merges
// it the way a second device merges its first sync (sync_apply.dart), so a
// backup restores the same things signing in on a new phone does.

import 'package:flutter/foundation.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/security/ledger_backup_codec.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/sync/sync_apply.dart';
import 'package:waffr/core/sync/sync_dirty.dart';
import 'package:waffr/core/sync/sync_request.dart';

/// The synced collections a snapshot holds, as sync names them.
const List<String> backupCollections = [
  'transactions',
  'savings_goals',
  'savings_transfers',
  'shopping_lists',
  'shopping_items',
  'recurring_expenses',
  'notifications',
  'expense_categories',
  'expense_presets',
];

/// An opened backup, ready to restore.
@immutable
class LedgerBackupPreview {
  /// When the backup was made (device time of the phone that made it).
  final DateTime createdAt;

  /// The account the backup came from, or null for a guest's data.
  final String? accountEmail;

  /// Rows per collection, for the confirmation dialog.
  final Map<String, int> counts;

  /// The snapshot itself.
  final Map<String, dynamic> snapshot;

  /// An opened backup.
  const LedgerBackupPreview({
    required this.createdAt,
    required this.accountEmail,
    required this.counts,
    required this.snapshot,
  });

  /// Incomes, expenses and savings moves together.
  int get ledgerEntries =>
      (counts['transactions'] ?? 0) + (counts['savings_transfers'] ?? 0);
}

/// Makes and restores encrypted backup files.
class LedgerBackupService {
  LedgerBackupService._();

  /// The app-wide service.
  static final LedgerBackupService instance = LedgerBackupService._();

  /// Iterations for new files; tests lower it to keep them fast.
  @visibleForTesting
  static int iterations = LedgerBackupCodec.defaultIterations;

  /// A file name for a backup made at [now], e.g. `waffr-backup-2026-11-26.waffr`.
  static String fileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'waffr-backup-${now.year}-${two(now.month)}-${two(now.day)}.waffr';
  }

  /// The encrypted backup file of everything on this device.
  Future<Uint8List> export(String passphrase) async {
    final snapshot = await buildSyncRequest(lastSync: null, everyRow: true);
    final prefs = await AppPrefs.instance;
    return LedgerBackupCodec.seal(
      body: {
        'snapshot': snapshot,
        'account_email': prefs.getString(AuthSession.accountEmailKey),
      },
      passphrase: passphrase,
      iterations: iterations,
    );
  }

  /// Opens [file] with [passphrase]. Throws [BackupFormatException] or
  /// [BackupPassphraseException] from [LedgerBackupCodec.open].
  Future<LedgerBackupPreview> open(Uint8List file, String passphrase) async {
    final header = LedgerBackupCodec.parseHeader(file);
    final body = await LedgerBackupCodec.open(
      file: file,
      passphrase: passphrase,
    );
    final snapshot = body['snapshot'];
    if (snapshot is! Map) {
      throw const BackupFormatException('no snapshot');
    }
    final data = Map<String, dynamic>.from(snapshot);
    final counts = <String, int>{
      for (final name in backupCollections)
        name: switch (data[name]) {
          final Map section => switch (section['upserts']) {
            final List rows => rows.length,
            _ => 0,
          },
          _ => 0,
        },
    };
    final email = body['account_email'];
    return LedgerBackupPreview(
      createdAt: header.createdAtLocal,
      accountEmail: email is String && email.trim().isNotEmpty
          ? email.trim()
          : null,
      counts: counts,
      snapshot: data,
    );
  }

  /// Merges [preview] into this device. True when every store took it.
  ///
  /// Only adds and updates: a row on this device that is newer than its copy
  /// in the backup stays, and nothing is deleted. That includes deletes the
  /// backup recorded, so restoring can never lose a row. The restored rows
  /// are marked as local changes, so a signed-in device uploads them.
  Future<bool> restore(LedgerBackupPreview preview) async {
    final body = <String, dynamic>{
      for (final name in backupCollections)
        name: {
          'upserts': switch (preview.snapshot[name]) {
            final Map section =>
              section['upserts'] is List
                  ? section['upserts'] as List
                  : const <Object>[],
            _ => const <Object>[],
          },
          'deletes': const <Object>[],
        },
      'settings': preview.snapshot['settings'],
    };
    final applied = await applySyncResponse(body);
    if (applied) {
      await SyncDirty.mark();
    }
    return applied;
  }
}
