// Builds an offline PDF or plain-text export of selected expenses and opens
// the system share sheet. Event times stay the ones stored on each record.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/data/models/expense_categories.dart';
import 'package:waffer/data/models/transaction.dart';

const List<String> _months = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

class ExpenseShareDay {
  final DateTime date;
  final List<WafferTransaction> expenses;

  const ExpenseShareDay(this.date, this.expenses);
}

List<ExpenseShareDay> groupExpensesForShare(List<WafferTransaction> expenses) {
  final grouped = <DateTime, List<WafferTransaction>>{};
  for (final expense in expenses) {
    final local = expense.dateTime.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    grouped.putIfAbsent(date, () => []).add(expense);
  }
  final days = grouped.entries
      .map((entry) => ExpenseShareDay(entry.key, entry.value))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  for (final day in days) {
    day.expenses.sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }
  return days;
}

String expenseShareDayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(date).inDays;
  if (difference == 0) return 'اليوم';
  if (difference == 1) return 'أمس';
  if (date.year == today.year) {
    return '${date.day} ${_months[date.month - 1]}';
  }
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

String buildExpenseHistoryText(List<WafferTransaction> expenses) {
  final days = groupExpensesForShare(expenses);
  final buffer = StringBuffer('سجل المصاريف\n');
  for (final day in days) {
    buffer.writeln();
    buffer.writeln(expenseShareDayLabel(day.date));
    for (final expense in day.expenses) {
      buffer.writeln(_expenseLine(expense));
      final note = expense.note?.trim();
      if (note != null && note.isNotEmpty) {
        buffer.writeln(note);
      }
    }
    buffer.writeln(_totalsLine('مجموع اليوم', day.expenses));
  }
  buffer.writeln();
  buffer.writeln(_totalsLine('المجموع', expenses));
  return buffer.toString().trimRight();
}

Future<void> shareExpenseHistoryText(List<WafferTransaction> expenses) {
  return SharePlus.instance.share(
    ShareParams(text: buildExpenseHistoryText(expenses)),
  );
}

Future<void> shareExpenseHistoryPdf(List<WafferTransaction> expenses) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('fonts/Tajawal-Regular.ttf'),
  );
  final bold = pw.Font.ttf(await rootBundle.load('fonts/Tajawal-Bold.ttf'));
  final brand = pw.Font.ttf(await rootBundle.load('fonts/Outfit-Regular.ttf'));
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/brand/waffer_logo.png')).buffer.asUint8List(),
  );
  final days = groupExpensesForShare(expenses);
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (context) => pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Align(
          alignment: pw.Alignment.topLeft,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Image(logo, width: 64, height: 64),
              pw.SizedBox(height: 2),
              pw.Transform(
                alignment: pw.Alignment.center,
                adjustLayout: true,
                transform: Matrix4.skewX(-0.22),
                child: pw.Text(
                  'waffr',
                  style: pw.TextStyle(
                    font: brand,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF254A23),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      build: (context) => [
        pw.Text(
          'سجل المصاريف',
          style: pw.TextStyle(font: bold, fontSize: 22),
        ),
        pw.SizedBox(height: 16),
        for (final day in days) ...[
          pw.Text(
            expenseShareDayLabel(day.date),
            style: pw.TextStyle(font: bold, fontSize: 14),
          ),
          pw.SizedBox(height: 6),
          for (final expense in day.expenses) ...[
            pw.Text(_expenseLine(expense), style: const pw.TextStyle(fontSize: 12)),
            if (expense.note?.trim().isNotEmpty == true)
              pw.Text(
                expense.note!.trim(),
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
              ),
            pw.SizedBox(height: 4),
          ],
          pw.Text(
            _totalsLine('مجموع اليوم', day.expenses),
            style: pw.TextStyle(font: bold, fontSize: 12),
          ),
          pw.SizedBox(height: 14),
        ],
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text(
          _totalsLine('المجموع', expenses),
          style: pw.TextStyle(font: bold, fontSize: 14),
        ),
      ],
    ),
  );

  final bytes = await document.save();
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    throw StateError('PDF was not written');
  }
  final folder = Directory('${(await getApplicationSupportDirectory()).path}/shared_pdfs');
  await folder.create(recursive: true);
  final file = File(
    '${folder.path}/waffer-expenses-${DateTime.now().millisecondsSinceEpoch}.pdf',
  );
  await file.writeAsBytes(bytes, flush: true);
  if (!await file.exists() || await file.length() != bytes.length) {
    throw StateError('PDF was not saved');
  }
  if (Platform.isAndroid) {
    const channel = MethodChannel('waffer/share_pdf');
    await channel.invokeMethod<void>('share', {'path': file.path});
    return;
  }
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(
          file.path,
          mimeType: 'application/pdf',
          name: 'waffer-expenses.pdf',
        ),
      ],
      fileNameOverrides: const ['waffer-expenses.pdf'],
    ),
  );
}

String _expenseLine(WafferTransaction expense) {
  final category = categoryFor(expense.category).label;
  final amount = formatMoney(expense.amount);
  final currency = currencyLabelFor(expense.currencyCode);
  final time = formatTime(expense.dateTime);
  return '$category  •  $time  •  $amount $currency';
}

String _totalsLine(String label, List<WafferTransaction> expenses) {
  final totals = <String, double>{};
  for (final expense in expenses) {
    totals.update(
      expense.currencyCode,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
  }
  final parts = totals.entries
      .map(
        (entry) =>
            '${formatMoney(entry.value)} ${currencyLabelFor(entry.key)}',
      )
      .join('  •  ');
  return '$label: $parts';
}
