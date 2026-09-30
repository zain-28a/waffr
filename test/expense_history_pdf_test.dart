import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waffer/data/models/transaction.dart';
import 'package:waffer/screens/offline/report/expense_history_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a non-empty Arabic PDF', () async {
    final bytes = await buildExpenseHistoryPdfBytes([
      WafferTransaction(
        id: 'e1',
        type: TransactionType.expense,
        amount: 1500,
        category: 'طعام',
        paymentMethod: 'نقداً',
        note: 'غداء مع العائلة',
        dateTime: DateTime(2026, 9, 30, 14, 5),
      ),
    ]);

    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    final file = File(
      '${Directory.systemTemp.path}/waffer-expenses-test.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    expect(await file.exists(), isTrue);
    expect(await file.length(), bytes.length);
    addTearDown(() => file.delete());
  });
}
