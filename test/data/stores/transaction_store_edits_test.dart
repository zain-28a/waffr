// TransactionStore edits: changing an expense, an income, a manual saving
// or withdrawal and a goal after the fact, with the balance rules that keep
// the ledger valid, and the same for a recurring schedule's details.

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/sync/sync_tombstones.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/savings_goal.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';

import '../../helpers/store_harness.dart';

void main() {
  final store = TransactionStore.instance;

  setUp(() async {
    await setUpStores();
  });

  Future<WaffrTransaction> spend(double amount) async =>
      (await store.addExpense(
        amount: amount,
        category: 'طعام',
        paymentMethod: 'نقداً',
        note: 'غداء',
      ))!;

  group('updateExpense', () {
    test('changes amount, category, note, payment and time', () async {
      await store.addIncome(amount: 500);
      final expense = await spend(100);
      final when = DateTime.now().subtract(const Duration(days: 2));

      final ok = await store.updateExpense(
        expense.id,
        amount: 140,
        category: 'مواصلات',
        paymentMethod: 'بطاقة',
        note: 'تاكسي',
        dateTime: when,
      );

      expect(ok, isTrue);
      final edited = store.expenses.single;
      expect(edited.id, expense.id);
      expect(edited.amount, 140);
      expect(edited.category, 'مواصلات');
      expect(edited.paymentMethod, 'بطاقة');
      expect(edited.note, 'تاكسي');
      expect(edited.dateTime, when);
      expect(edited.updatedAt, isNotNull);
      expect(store.balance, 360);
    });

    test('a larger amount may use the old amount but not overdraw', () async {
      await store.addIncome(amount: 500);
      final expense = await spend(100);

      expect(await store.updateExpense(expense.id, amount: 500), isTrue);
      expect(store.balance, 0);
      expect(await store.updateExpense(expense.id, amount: 501), isFalse);
      expect(store.expenses.single.amount, 500);
    });

    test('rejects a bad amount or an unknown id; clears the note', () async {
      await store.addIncome(amount: 500);
      final expense = await spend(100);

      expect(await store.updateExpense(expense.id, amount: 0), isFalse);
      expect(await store.updateExpense('nope', amount: 10), isFalse);
      expect(await store.updateExpense(expense.id, clearNote: true), isTrue);
      expect(store.expenses.single.note, isNull);
    });

    test('survives a reload and notifies listeners', () async {
      await store.addIncome(amount: 500);
      final expense = await spend(100);
      var notified = 0;
      void listener() => notified++;
      store.addListener(listener);
      addTearDown(() => store.removeListener(listener));

      await store.updateExpense(expense.id, amount: 75);
      expect(notified, greaterThan(0));

      store.resetCache();
      await store.ensureLoaded();
      expect(store.expenses.single.amount, 75);
      expect(store.balance, 425);
    });
  });

  group('updateIncome', () {
    test('changes amount and source', () async {
      await store.addIncome(amount: 500, source: 'راتب');
      final income = store.incomes.single;

      expect(
        await store.updateIncome(income.id, amount: 650, note: 'مكافأة'),
        isTrue,
      );
      expect(store.incomes.single.amount, 650);
      expect(store.incomes.single.note, 'مكافأة');
      expect(store.balance, 650);
    });

    test('a smaller amount cannot leave the balance below zero', () async {
      await store.addIncome(amount: 500);
      await spend(300);
      final income = store.incomes.single;

      expect(await store.updateIncome(income.id, amount: 299), isFalse);
      expect(await store.updateIncome(income.id, amount: 300), isTrue);
      expect(store.balance, 0);
    });
  });

  group('savings transfers', () {
    test('a manual saving can be changed within both balances', () async {
      await store.addIncome(amount: 500);
      await store.saveManually(200);
      final saving = store.savingsTransfers.single;
      expect(store.isEditableTransfer(saving), isTrue);

      expect(await store.updateSavingsTransfer(saving.id, 350), isTrue);
      expect(store.balance, 150);
      expect(store.savingsBalance, 350);
      // More than the balance can cover.
      expect(await store.updateSavingsTransfer(saving.id, 501), isFalse);
      expect(store.savingsBalance, 350);
    });

    test('a withdrawal can be changed and deleted', () async {
      await store.addIncome(amount: 500);
      await store.saveManually(300);
      await store.withdrawFromSavings(100);
      final withdrawal = store.savingsTransfers.firstWhere(
        (t) => t.type == TransactionType.savingsOut,
      );

      expect(await store.updateSavingsTransfer(withdrawal.id, 300), isTrue);
      expect(store.savingsBalance, 0);
      expect(await store.updateSavingsTransfer(withdrawal.id, 301), isFalse);

      // The withdrawn 300 is spent down to 100: it can no longer go back.
      await spend(400);
      expect(await store.deleteSavingsTransfer(withdrawal.id), isFalse);

      // With enough balance the withdrawal is undone into savings.
      await store.addIncome(amount: 200);
      expect(await store.deleteSavingsTransfer(withdrawal.id), isTrue);
      expect(store.balance, 0);
      expect(store.savingsBalance, 300);
    });

    test('deleting a manual saving returns it to the balance', () async {
      await store.addIncome(amount: 500);
      await store.saveManually(200);
      final saving = store.savingsTransfers.single;

      expect(await store.deleteSavingsTransfer(saving.id), isTrue);
      expect(store.savingsTransfers, isEmpty);
      expect(store.balance, 500);
      expect(store.savingsBalance, 0);
      expect(
        SyncTombstones.instance
            .of(SyncCollection.transactions)
            .map((t) => t.clientId),
        contains(saving.id),
      );
    });
  });

  group('updateGoal', () {
    test('renames and retargets; rejects blanks and bad targets', () async {
      await store.addIncome(amount: 500);
      await store.createGoal(
        name: 'سفر',
        targetAmount: 1000,
        duration: GoalDurationPreset.month,
        allocatePercent: 10,
      );
      final goal = store.activeGoals.single;

      expect(
        await store.updateGoal(goal.id, name: ' عمرة ', targetAmount: 1500),
        isTrue,
      );
      expect(store.activeGoals.single.name, 'عمرة');
      expect(store.activeGoals.single.targetAmount, 1500);
      expect(await store.updateGoal(goal.id, name: '  '), isFalse);
      expect(await store.updateGoal(goal.id, targetAmount: 0), isFalse);
      expect(await store.updateGoal('nope', name: 'x'), isFalse);
    });

    test('a target at or below what is saved completes the goal', () async {
      await store.addIncome(amount: 500);
      await store.createGoal(
        name: 'سفر',
        targetAmount: 1000,
        duration: GoalDurationPreset.month,
        allocatePercent: 10,
      );
      await store.saveManually(200);
      final goal = store.activeGoals.single;

      expect(await store.updateGoal(goal.id, targetAmount: 150), isTrue);
      expect(store.activeGoals, isEmpty);
    });
  });

  group('RecurringExpenseStore.updateDetails', () {
    final recurring = RecurringExpenseStore.instance;

    test('changes the name, category, interval and next date', () async {
      await store.addIncome(amount: 500);
      await recurring.addExpense(
        amount: 30,
        category: 'فواتير',
        paymentMethod: 'نقداً',
        unit: RecurringUnit.month,
        intervalCount: 1,
        note: 'إنترنت',
      );
      final item = recurring.items.single;
      final next = DateTime.now().add(const Duration(days: 10));

      final ok = await recurring.updateDetails(
        item.id,
        note: 'ألياف',
        category: 'ترفيه',
        unit: RecurringUnit.week,
        intervalCount: 2,
        nextDueAt: next,
      );

      expect(ok, isTrue);
      final edited = recurring.items.single;
      expect(edited.note, 'ألياف');
      expect(edited.category, 'ترفيه');
      expect(edited.unit, RecurringUnit.week);
      expect(edited.intervalCount, 2);
      expect(edited.nextDueAt, next);
      // The first charge posted when it was added is untouched.
      expect(store.expenses, hasLength(1));
    });

    test('rejects a bad interval, a blank category and unknown ids', () async {
      await store.addIncome(amount: 500);
      await recurring.addExpense(
        amount: 30,
        category: 'فواتير',
        paymentMethod: 'نقداً',
        unit: RecurringUnit.month,
        intervalCount: 1,
      );
      final id = recurring.items.single.id;

      expect(await recurring.updateDetails(id, intervalCount: 0), isFalse);
      expect(await recurring.updateDetails(id, category: ' '), isFalse);
      expect(await recurring.updateDetails('nope', note: 'x'), isFalse);
      expect(await recurring.updateDetails(id, note: ' '), isTrue);
      expect(recurring.items.single.note, isNull);
    });
  });
}
