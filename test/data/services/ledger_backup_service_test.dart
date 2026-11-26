// LedgerBackupService: a backup restores the ledger on an empty device,
// merges without deleting on a used one, and marks restored rows for upload.

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/security/ledger_backup_codec.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/sync/sync_dirty.dart';
import 'package:waffr/core/sync/sync_tombstones.dart';
import 'package:waffr/data/models/savings_goal.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/services/ledger_backup_service.dart';
import 'package:waffr/data/stores/shopping_list_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';

import '../../helpers/store_harness.dart';

const _passphrase = 'a long backup passphrase';

void main() {
  setUp(() async {
    await setUpStores();
    LedgerBackupService.iterations = LedgerBackupCodec.minIterations;
  });

  Future<void> fill() async {
    final ledger = TransactionStore.instance;
    await ledger.addIncome(amount: 1000, frequency: RecurringFrequency.monthly);
    await ledger.addExpense(
      amount: 50,
      category: 'طعام',
      paymentMethod: 'نقداً',
      note: 'غداء',
    );
    await ledger.createGoal(
      name: 'سفر',
      targetAmount: 5000,
      duration: GoalDurationPreset.year,
    );
    await ShoppingListStore.instance.addItem('خبز');
  }

  test('a backup restores everything on an empty device', () async {
    await fill();
    final before = TransactionStore.instance.transactions
        .map((t) => t.id)
        .toSet();
    final file = await LedgerBackupService.instance.export(_passphrase);

    // A new phone.
    await setUpStores();
    expect(TransactionStore.instance.transactions, isEmpty);

    final preview = await LedgerBackupService.instance.open(file, _passphrase);
    expect(preview.counts['transactions'], 2);
    expect(preview.counts['savings_goals'], 1);
    expect(preview.counts['shopping_items'], 1);
    expect(preview.accountEmail, isNull);

    expect(await LedgerBackupService.instance.restore(preview), isTrue);
    await TransactionStore.instance.ensureLoaded();
    expect(
      TransactionStore.instance.transactions.map((t) => t.id).toSet(),
      before,
    );
    final lunch = TransactionStore.instance.transactions.firstWhere(
      (t) => t.note == 'غداء',
    );
    expect(lunch.amount, 50);
    expect(TransactionStore.instance.goals.single.name, 'سفر');
    await ShoppingListStore.instance.ensureLoaded();
    expect(ShoppingListStore.instance.items.single.name, 'خبز');
  });

  test('the account email travels inside the sealed part', () async {
    final prefs = await setUpStores();
    await prefs.setString(AuthSession.accountEmailKey, 'owner@example.com');
    final file = await LedgerBackupService.instance.export(_passphrase);
    final preview = await LedgerBackupService.instance.open(file, _passphrase);
    expect(preview.accountEmail, 'owner@example.com');
  });

  test('restoring merges and never deletes', () async {
    await fill();
    final file = await LedgerBackupService.instance.export(_passphrase);

    // After the backup: one expense is undone, a new one is added.
    final ledger = TransactionStore.instance;
    final lunch = ledger.transactions.firstWhere((t) => t.note == 'غداء');
    await ledger.undoExpense(lunch.id);
    await ledger.addExpense(
      amount: 20,
      category: 'نقل',
      paymentMethod: 'نقداً',
      note: 'تاكسي',
    );

    final preview = await LedgerBackupService.instance.open(file, _passphrase);
    expect(await LedgerBackupService.instance.restore(preview), isTrue);

    final notes = ledger.transactions.map((t) => t.note).toSet();
    expect(notes, contains('تاكسي')); // newer local row kept
    expect(notes, isNot(contains('غداء'))); // the newer local undo wins
    // The local undo left a tombstone, which is newer than the backup's copy.
    expect(
      SyncTombstones.instance.find(SyncCollection.transactions, lunch.id),
      isNotNull,
    );
  });

  test('deletes recorded in the backup are not applied', () async {
    await fill();
    final first = await LedgerBackupService.instance.export(_passphrase);
    final ledger = TransactionStore.instance;
    final lunch = ledger.transactions.firstWhere((t) => t.note == 'غداء');
    await ledger.undoExpense(
      lunch.id,
    ); // a tombstone, carried in the next backup
    final second = await LedgerBackupService.instance.export(_passphrase);
    final secondPreview = await LedgerBackupService.instance.open(
      second,
      _passphrase,
    );
    expect(secondPreview.snapshot['transactions']['deletes'], isNotEmpty);

    // Another phone holds the expense (from the first backup), then restores
    // the second one: the expense stays. A restore only adds and updates.
    await setUpStores();
    await LedgerBackupService.instance.restore(
      await LedgerBackupService.instance.open(first, _passphrase),
    );
    expect(
      TransactionStore.instance.transactions.any((t) => t.id == lunch.id),
      isTrue,
    );
    await LedgerBackupService.instance.restore(secondPreview);
    expect(
      TransactionStore.instance.transactions.any((t) => t.id == lunch.id),
      isTrue,
    );
  });

  test('restored rows are marked for upload', () async {
    await fill();
    final file = await LedgerBackupService.instance.export(_passphrase);
    await setUpStores();
    await SyncDirty.clear();
    final preview = await LedgerBackupService.instance.open(file, _passphrase);
    await LedgerBackupService.instance.restore(preview);
    expect(await SyncDirty.isDirty(), isTrue);
  });

  test('a wrong passphrase changes nothing', () async {
    await fill();
    final file = await LedgerBackupService.instance.export(_passphrase);
    await setUpStores();
    await expectLater(
      LedgerBackupService.instance.open(file, 'not the passphrase'),
      throwsA(isA<BackupPassphraseException>()),
    );
    expect(TransactionStore.instance.transactions, isEmpty);
  });

  test('file names carry the date', () {
    expect(
      LedgerBackupService.fileName(DateTime(2026, 3, 7)),
      'waffr-backup-2026-03-07.waffr',
    );
  });
}
