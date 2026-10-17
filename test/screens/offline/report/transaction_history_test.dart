// The expense history screen: multi-select counts and totals, and that the
// day groups it keeps between selection taps follow ledger changes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/screens/offline/report/reportscreen.dart';

import '../../../helpers/store_harness.dart';
import '../../../helpers/widget_harness.dart';

void main() {
  final store = TransactionStore.instance;

  Future<void> addExpense(double amount, String note, DateTime at) async {
    await store.addExpense(
      amount: amount,
      category: expenseCategories.first.label,
      paymentMethod: paymentMethods.first,
      note: note,
      occurredAt: at,
    );
  }

  /// The selected count in the selection bar.
  Finder count(int value) => find.text('$value');

  testWidgets('selection taps and ledger changes keep the list right', (
    tester,
  ) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    final today = DateTime.now();
    await tester.runAsync(() async {
      await setUpStores();
      await store.addIncome(amount: 100000);
      await addExpense(100, 'first', today.subtract(const Duration(days: 2)));
      await addExpense(200, 'second', today.subtract(const Duration(days: 1)));
      await addExpense(300, 'third', today);
    });

    await tester.pumpWidget(
      wrapInApp(const TransactionHistoryScreen.expenses()),
    );
    await pumpFor(tester);
    expect(find.text('${formatMoney(600)} $currencyLabel'), findsOneWidget);

    // The share button starts selecting; taps on rows pick them.
    await tester.tap(find.byIcon(Icons.share_rounded));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(count(0), findsOneWidget);

    await tester.tap(find.text('first'));
    await tester.pump();
    expect(count(1), findsOneWidget);
    await tester.tap(find.text('third'));
    await tester.pump();
    expect(count(2), findsOneWidget);
    await tester.tap(find.text('first'));
    await tester.pump();
    expect(count(1), findsOneWidget);

    // A new row while selecting shows up with the new total, unselected.
    await tester.runAsync(() => addExpense(400, 'fourth', today));
    await tester.pump();
    expect(find.text('fourth'), findsOneWidget);
    expect(find.text('${formatMoney(1000)} $currencyLabel'), findsOneWidget);
    expect(count(1), findsOneWidget);

    // An undone row leaves the selection count.
    final third = store.expenses.firstWhere((item) => item.note == 'third');
    await tester.runAsync(() => store.undoExpense(third.id));
    await tester.pump();
    expect(find.text('third'), findsNothing);
    expect(count(0), findsOneWidget);
    expect(find.text('${formatMoney(700)} $currencyLabel'), findsOneWidget);

    await unmountApp(tester);
  });
}
