import 'package:flutter_test/flutter_test.dart';
import 'package:waffer/data/models/app_notification.dart';
import 'package:waffer/data/stores/category_store.dart';
import 'package:waffer/data/models/recurring_expense.dart';
import 'package:waffer/data/models/savings_goal.dart';
import 'package:waffer/data/models/transaction.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_mapper.dart';
import 'package:waffer/core/sync/sync_merge.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';

void main() {
  test('income and expense stay transactions; savings become transfers', () {
    final income = WafferTransaction(
      id: 'tx_income',
      type: TransactionType.income,
      amount: 100,
      dateTime: DateTime.utc(2026, 1, 1),
      frequency: RecurringFrequency.monthly,
    );
    final expense = WafferTransaction(
      id: 'tx_expense',
      type: TransactionType.expense,
      amount: 20,
      dateTime: DateTime.utc(2026, 1, 2),
      category: 'طعام',
    );
    final saved = WafferTransaction(
      id: 'tx_save',
      type: TransactionType.savingsIn,
      amount: 15,
      dateTime: DateTime.utc(2026, 1, 3),
      transferKind: SavingsTransferKind.manual,
      goalId: 'g1',
    );

    expect(transactionToSync(income)['type'], 'income');
    expect(transactionToSync(expense)['type'], 'expense');
    expect(transferToSync(saved)['direction'], 'to_savings');
    expect(transferToSync(saved)['goal_client_id'], 'g1');
  });

  test('round-trip keeps client ids', () {
    final goal = SavingsGoal(
      id: 'g99',
      name: 'سيارة',
      targetAmount: 500,
      createdAt: DateTime.utc(2026, 2, 1),
      duration: GoalDurationPreset.month,
    );
    final decoded = goalFromSync(goalToSync(goal));
    expect(decoded?.id, 'g99');
    expect(decoded?.targetAmount, 500);

    final recurring = RecurringExpense(
      id: 'r1',
      amount: 12.5,
      category: 'فواتير',
      paymentMethod: 'نقد',
      unit: RecurringUnit.month,
      intervalCount: 1,
      createdAt: DateTime.utc(2026, 3, 1),
      nextDueAt: DateTime.utc(2026, 4, 1),
    );
    final recurringDecoded = recurringFromSync(recurringToSync(recurring));
    expect(recurringDecoded?.id, 'r1');
    expect(recurringDecoded?.amount, 12.5);

    final note = AppNotification(
      id: 'n1',
      type: NotificationType.goalReached,
      title: 'تم',
      message: 'وصل الهدف',
      createdAt: DateTime.utc(2026, 5, 1),
      eventKey: 'goalReached:g99',
    );
    final noteDecoded = notificationFromSync(notificationToSync(note));
    expect(noteDecoded?.id, 'n1');
    expect(noteDecoded?.eventKey, 'goalReached:g99');
  });

  test('last-write-wins keeps the newer local record', () {
    final older = WafferTransaction(
      id: 'same',
      type: TransactionType.expense,
      amount: 10,
      dateTime: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final newer = WafferTransaction(
      id: 'same',
      type: TransactionType.expense,
      amount: 11,
      dateTime: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    final items = [newer];
    final changed = mergeRemoteRecords<WafferTransaction>(
      items: items,
      upserts: [older],
      deletes: const [],
      collection: SyncCollection.transactions,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );
    expect(changed, isFalse);
    expect(items.single.amount, 11);
  });

  test('newer remote delete removes the local record', () {
    final local = WafferTransaction(
      id: 'gone',
      type: TransactionType.expense,
      amount: 8,
      dateTime: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final items = [local];
    final changed = mergeRemoteRecords<WafferTransaction>(
      items: items,
      upserts: const [],
      deletes: [
        SyncTombstone(
          clientId: 'gone',
          deletedAt: DateTime.utc(2026, 1, 3),
        ),
      ],
      collection: SyncCollection.transactions,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );
    expect(changed, isTrue);
    expect(items, isEmpty);
  });

  test('newerOrEqual treats equal timestamps as incoming wins', () {
    final stamp = DateTime.utc(2026, 6, 1, 12);
    expect(newerOrEqual(stamp, stamp), isTrue);
    expect(newerOrEqual(stamp.add(const Duration(seconds: 1)), stamp), isTrue);
    expect(newerOrEqual(stamp, stamp.add(const Duration(seconds: 1))), isFalse);
  });

  test('custom categories round-trip client ids and icons', () {
    final entry = CustomCategoryEntry(
      id: 'cat_1',
      label: 'قهوة',
      iconIndex: 2,
      updatedAt: DateTime.utc(2026, 3, 1),
    );
    final payload = categoryToSync(entry);
    expect(payload['client_id'], 'cat_1');
    expect(payload['icon_index'], 2);
    final restored = categoryFromSync(payload);
    expect(restored?.id, 'cat_1');
    expect(restored?.label, 'قهوة');
    expect(restored?.iconIndex, 2);
  });
}
