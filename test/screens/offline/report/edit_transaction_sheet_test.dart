// Edit sheets: the transaction editor (expense and income), the savings log
// and the obligation editor open and render cleanly, and saving an edit
// changes the ledger.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/screens/offline/obligations/obligations_sheet.dart';
import 'package:waffr/screens/offline/report/edit_transaction_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/savings_log_sheet.dart';

import '../../../helpers/store_harness.dart';
import '../../../helpers/widget_harness.dart';

void main() {
  final store = TransactionStore.instance;

  smokeTestScreen(
    'edit expense sheet',
    () => SheetLauncher(
      open: (context) =>
          showEditTransactionSheet(context, store.expenses.first),
    ),
    interact: openSheet,
    withSampleData: false,
    seed: () async {
      await store.addIncome(amount: 500, source: 'راتب');
      await store.addExpense(
        amount: 120,
        category: expenseCategories[0].label,
        paymentMethod: paymentMethods.first,
        note: 'غداء',
      );
    },
  );

  smokeTestScreen(
    'edit income sheet',
    () => SheetLauncher(
      open: (context) => showEditTransactionSheet(context, store.incomes.first),
    ),
    interact: openSheet,
    withSampleData: false,
    seed: () => store.addIncome(amount: 500, source: 'راتب'),
  );

  smokeTestScreen(
    'savings log sheet',
    () => SheetLauncher(open: showSavingsLogSheet),
    interact: openSheet,
    withSampleData: false,
    seed: () async {
      await store.addIncome(amount: 500);
      await store.saveManually(200);
      await store.withdrawFromSavings(50);
    },
  );

  smokeTestScreen(
    'edit obligation sheet',
    () => SheetLauncher(
      open: (context) => showEditObligationSheet(
        context,
        RecurringExpenseStore.instance.items.first.id,
      ),
    ),
    interact: openSheet,
    withSampleData: false,
    seed: () async {
      await store.addIncome(amount: 500);
      await RecurringExpenseStore.instance.addExpense(
        amount: 30,
        category: expenseCategories[3].label,
        paymentMethod: paymentMethods.first,
        unit: RecurringUnit.month,
        intervalCount: 1,
        note: 'إنترنت',
      );
    },
  );

  testWidgets('saving an edited amount updates the expense', (tester) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    late WaffrTransaction expense;
    await tester.runAsync(() async {
      await setUpStores();
      await store.addIncome(amount: 500);
      expense = (await store.addExpense(
        amount: 120,
        category: expenseCategories[0].label,
        paymentMethod: paymentMethods.first,
      ))!;
    });

    await tester.pumpWidget(
      wrapInApp(
        SheetLauncher(
          open: (context) => showEditTransactionSheet(context, expense),
        ),
      ),
    );
    await openSheet(tester);
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.enterText(find.byType(TextField).first, '80');
    await tester.pump();
    await tester.ensureVisible(find.text('حفظ التعديلات'));
    await tester.tap(find.text('حفظ التعديلات'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await pumpFor(tester, const Duration(seconds: 1));

    expect(store.expenses.single.amount, 80);
    expect(store.balance, 420);
    await unmountApp(tester);
  });
}
