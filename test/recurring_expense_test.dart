import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await AppPrefs.instance;
    await prefs.clear();
    TransactionStore.instance.resetCache();
    RecurringExpenseStore.instance.resetCache();
    NotificationService.instance.resetCache();
    CurrencyStore.instance.resetCache();
  });

  Future<void> seedIncome(double amount) {
    return TransactionStore.instance.addIncome(
      amount: amount,
      frequency: RecurringFrequency.monthly,
      source: 'راتب',
    );
  }

  test('posts a due recurring expense once per open', () async {
    await seedIncome(1000);
    await RecurringExpenseStore.instance.addExpense(
      amount: 25,
      category: 'طعام',
      paymentMethod: 'نقداً',
      unit: RecurringUnit.day,
      intervalCount: 1,
      note: 'قهوة',
    );

    expect(TransactionStore.instance.expenses, hasLength(1));
    expect(TransactionStore.instance.expenses.single.amount, 25);
    expect(TransactionStore.instance.expenses.single.note, 'قهوة');

    final nextDue = RecurringExpenseStore.instance.items.single.nextDueAt;
    expect(nextDue.isAfter(DateTime.now()), isTrue);

    await RecurringExpenseStore.instance.processDue();
    expect(TransactionStore.instance.expenses, hasLength(1));
  });

  test('catches up missed periods without duplicating them', () async {
    await seedIncome(5000);
    final past = DateTime.now().subtract(const Duration(days: 3));
    final scheduled = RecurringExpense(
      id: 'rent-1',
      amount: 100,
      category: 'طعام',
      paymentMethod: 'نقداً',
      unit: RecurringUnit.day,
      intervalCount: 1,
      createdAt: past,
      nextDueAt: past,
    );
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(RecurringExpenseStore.itemsKey, [
      scheduled.encode(),
    ]);
    RecurringExpenseStore.instance.resetCache();

    await RecurringExpenseStore.instance.processDue();
    final posted = TransactionStore.instance.expenses.length;
    expect(posted, greaterThanOrEqualTo(3));
    expect(posted, lessThanOrEqualTo(5));
    expect(
      RecurringExpenseStore.instance.items.single.nextDueAt.isAfter(
        DateTime.now(),
      ),
      isTrue,
    );

    await RecurringExpenseStore.instance.processDue();
    expect(TransactionStore.instance.expenses, hasLength(posted));
  });

  test('does not post or advance when the balance is too low', () async {
    await seedIncome(40);
    await RecurringExpenseStore.instance.addExpense(
      amount: 80,
      category: 'طعام',
      paymentMethod: 'نقداً',
      unit: RecurringUnit.month,
      intervalCount: 1,
    );

    expect(TransactionStore.instance.expenses, isEmpty);
    final due = RecurringExpenseStore.instance.items.single.nextDueAt;
    expect(due.isAfter(DateTime.now()), isFalse);

    await RecurringExpenseStore.instance.processDue();
    expect(TransactionStore.instance.expenses, isEmpty);
    expect(RecurringExpenseStore.instance.items.single.nextDueAt, due);
  });

  Future<void> seedPastConfirmed({required int daysAgo}) async {
    final past = DateTime.now().subtract(Duration(days: daysAgo, minutes: 1));
    final scheduled = RecurringExpense(
      id: 'rent-c',
      amount: 50,
      category: 'سكن',
      paymentMethod: 'نقداً',
      unit: RecurringUnit.day,
      intervalCount: 1,
      createdAt: past,
      nextDueAt: past,
      requiresConfirmation: true,
    );
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(RecurringExpenseStore.itemsKey, [
      scheduled.encode(),
    ]);
    RecurringExpenseStore.instance.resetCache();
  }

  test('works without a configured monthly income', () async {
    await TransactionStore.instance.addIncome(
      amount: 300,
      frequency: RecurringFrequency.none,
      source: 'عمل حر',
    );
    await RecurringExpenseStore.instance.addExpense(
      amount: 20,
      category: 'طعام',
      paymentMethod: 'نقداً',
      unit: RecurringUnit.month,
      intervalCount: 1,
    );

    expect(RecurringExpenseStore.instance.items, hasLength(1));
    expect(TransactionStore.instance.expenses, hasLength(1));
  });

  test('confirmation charges wait and accumulate until approved', () async {
    await seedIncome(1000);
    await seedPastConfirmed(daysAgo: 2);

    final store = RecurringExpenseStore.instance;
    await store.processDue();
    expect(TransactionStore.instance.expenses, isEmpty);

    final code = store.items.single.currencyCode;
    expect(store.awaitingConfirmation(code), hasLength(1));
    expect(store.items.single.dueDates(DateTime.now()), hasLength(3));

    expect(await store.confirmDue('rent-c'), 1);
    expect(TransactionStore.instance.expenses, hasLength(1));
    expect(store.items.single.dueDates(DateTime.now()), hasLength(2));

    expect(await store.confirmDue('rent-c', all: true), 2);
    expect(TransactionStore.instance.expenses, hasLength(3));
    expect(store.awaitingConfirmation(code), isEmpty);
  });

  test('confirming stops when the balance runs out', () async {
    await seedIncome(70);
    await seedPastConfirmed(daysAgo: 2);

    final store = RecurringExpenseStore.instance;
    expect(await store.confirmDue('rent-c', all: true), 1);
    expect(store.items.single.dueDates(DateTime.now()), hasLength(2));
  });

  test('postponing until income keeps the charge pending', () async {
    await seedIncome(1000);
    await seedPastConfirmed(daysAgo: 0);

    final store = RecurringExpenseStore.instance;
    await store.postpone('rent-c', untilIncome: true);
    expect(store.items.single.remindOnIncome, isTrue);
    expect(
      store.awaitingConfirmation(store.items.single.currencyCode),
      hasLength(1),
    );

    await store.releaseIncomeReminders(store.items.single.currencyCode);
    expect(store.items.single.remindOnIncome, isFalse);
    expect(TransactionStore.instance.expenses, isEmpty);
  });
}
