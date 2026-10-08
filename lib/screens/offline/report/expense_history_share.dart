// Builds an offline PDF or plain-text export of selected expenses and opens
// the system share sheet. Event times stay the ones stored on each record.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/data/models/expense_categories.dart';
import 'package:waffer/data/models/recurring_expense.dart';
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

// Brand and table colors for the PDF (Waffer light theme tokens).
final PdfColor _brandGreen = PdfColor.fromInt(0xFF254A23);
final PdfColor _rowTint = PdfColor.fromInt(0xFFF6F8F4);
final PdfColor _headerTint = PdfColor.fromInt(0xFFE9EFE6);
final PdfColor _rule = PdfColor.fromInt(0xFFDCE3D8);
final PdfColor _muted = PdfColor.fromInt(0xFF6F6F6F);

// Column order is left to right on paper: amount, time, category. The
// document reads right to left, so category is the first column the eye meets.
const Map<int, pw.TableColumnWidth> _columnWidths = {
  0: pw.FlexColumnWidth(3),
  1: pw.FlexColumnWidth(1.6),
  2: pw.FlexColumnWidth(5),
};

Future<Uint8List> buildExpenseHistoryPdfBytes(
  List<WafferTransaction> expenses,
) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('fonts/Tajawal-Regular.ttf'),
  );
  final bold = pw.Font.ttf(await rootBundle.load('fonts/Tajawal-Bold.ttf'));
  // Same face as the app's "WAFFR" title in the header bar.
  final brand = pw.Font.ttf(
    await rootBundle.load('fonts/BebasNeue-Regular.ttf'),
  );
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/brand/waffer_logo.png')).buffer.asUint8List(),
  );
  final days = groupExpensesForShare(expenses);
  final generatedAt = DateTime.now();
  final document = pw.Document(title: 'سجل المصاريف', author: 'WAFFR');

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      maxPages: 500,
      header: (context) => _pdfHeader(
        logo: logo,
        brand: brand,
        bold: bold,
        regular: regular,
        days: days,
        count: expenses.length,
      ),
      footer: (context) => _pdfFooter(
        context,
        regular: regular,
        generatedAt: generatedAt,
      ),
      build: (context) => [
        for (final day in days) ...[
          _pdfDayCaption(day, bold: bold, regular: regular),
          pw.SizedBox(height: 6),
          _pdfDayTable(day, bold: bold, regular: regular),
          pw.SizedBox(height: 16),
        ],
        _pdfGrandTotal(expenses, bold: bold, regular: regular),
      ],
    ),
  );

  final bytes = await document.save();
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    throw StateError('PDF bytes are empty or not a PDF');
  }
  return bytes;
}

pw.Widget _pdfHeader({
  required pw.ImageProvider logo,
  required pw.Font brand,
  required pw.Font bold,
  required pw.Font regular,
  required List<ExpenseShareDay> days,
  required int count,
}) {
  final range = days.isEmpty
      ? ''
      : days.length == 1
          ? formatDate(days.first.date)
          : 'من ${formatDate(days.last.date)} إلى ${formatDate(days.first.date)}';

  return pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'سجل المصاريف',
                  style: pw.TextStyle(font: bold, fontSize: 20),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  [
                    if (range.isNotEmpty) range,
                    '$count ${count == 1 ? 'مصروف' : 'مصاريف'}',
                  ].join('  ·  '),
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 10.5,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(logo, width: 34, height: 34),
                pw.SizedBox(width: 6),
                // The app draws the title as a slanted Bebas Neue.
                pw.Transform(
                  transform: Matrix4.skewX(0.21),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'WAFFR',
                    textDirection: pw.TextDirection.ltr,
                    style: pw.TextStyle(
                      font: brand,
                      fontSize: 30,
                      color: _brandGreen,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Container(height: 1.4, color: _brandGreen),
      pw.SizedBox(height: 14),
    ],
  );
}

pw.Widget _pdfFooter(
  pw.Context context, {
  required pw.Font regular,
  required DateTime generatedAt,
}) {
  final style = pw.TextStyle(font: regular, fontSize: 9, color: _muted);
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            'أُنشئ في ${formatDate(generatedAt)} ${formatTime(generatedAt)}',
            style: style,
          ),
        ),
        pw.Text(
          'صفحة ${context.pageNumber} من ${context.pagesCount}',
          style: style,
        ),
      ],
    ),
  );
}

pw.Widget _pdfDayCaption(
  ExpenseShareDay day, {
  required pw.Font bold,
  required pw.Font regular,
}) {
  final label = expenseShareDayLabel(day.date);
  final date = formatDate(day.date);
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Expanded(
        child: pw.Text(
          label,
          style: pw.TextStyle(font: bold, fontSize: 13, color: _brandGreen),
        ),
      ),
      if (!label.contains('${day.date.year}') || label == date)
        pw.Text(
          date,
          style: pw.TextStyle(font: regular, fontSize: 10, color: _muted),
        ),
    ],
  );
}

pw.Widget _pdfDayTable(
  ExpenseShareDay day, {
  required pw.Font bold,
  required pw.Font regular,
}) {
  pw.Widget cell(
    pw.Widget child, {
    pw.Alignment alignment = pw.Alignment.centerRight,
  }) {
    return pw.Container(
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: child,
    );
  }

  final headStyle = pw.TextStyle(font: bold, fontSize: 9.5, color: _muted);
  final bodyStyle = pw.TextStyle(font: regular, fontSize: 10.5);
  final amountStyle = pw.TextStyle(font: bold, fontSize: 10.5);

  return pw.Table(
    columnWidths: _columnWidths,
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _rule, width: 0.6),
      bottom: pw.BorderSide(color: _rule, width: 0.6),
    ),
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: _headerTint),
        children: [
          cell(
            pw.Text('المبلغ', style: headStyle),
            alignment: pw.Alignment.centerLeft,
          ),
          cell(
            pw.Text('الوقت', style: headStyle),
            alignment: pw.Alignment.center,
          ),
          cell(pw.Text('التصنيف', style: headStyle)),
        ],
      ),
      for (var i = 0; i < day.expenses.length; i++)
        pw.TableRow(
          decoration: i.isOdd ? pw.BoxDecoration(color: _rowTint) : null,
          children: [
            cell(
              pw.Text(_amountText(day.expenses[i]), style: amountStyle),
              alignment: pw.Alignment.centerLeft,
            ),
            cell(
              pw.Text(
                formatTime(day.expenses[i].dateTime),
                textDirection: pw.TextDirection.ltr,
                style: bodyStyle,
              ),
              alignment: pw.Alignment.center,
            ),
            cell(_pdfCategoryCell(day.expenses[i], bold: bold, regular: regular)),
          ],
        ),
      pw.TableRow(
        children: [
          cell(
            pw.Text(
              _totalsAmount(day.expenses),
              style: pw.TextStyle(font: bold, fontSize: 11, color: _brandGreen),
            ),
            alignment: pw.Alignment.centerLeft,
          ),
          cell(pw.SizedBox()),
          cell(
            pw.Text(
              'مجموع اليوم',
              style: pw.TextStyle(font: bold, fontSize: 10.5),
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _pdfCategoryCell(
  WafferTransaction expense, {
  required pw.Font bold,
  required pw.Font regular,
}) {
  final note = expense.note?.trim() ?? '';
  final recurring = RecurringExpense.isRecurringSource(expense.sourceId);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            categoryFor(expense.category).label,
            style: pw.TextStyle(font: bold, fontSize: 10.5),
          ),
          if (recurring) ...[
            pw.SizedBox(width: 6),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: pw.BoxDecoration(
                color: _headerTint,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'متكرر',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 8,
                  color: _brandGreen,
                ),
              ),
            ),
          ],
        ],
      ),
      if (note.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 1),
          child: pw.Text(
            note,
            style: pw.TextStyle(font: regular, fontSize: 9, color: _muted),
          ),
        ),
    ],
  );
}

pw.Widget _pdfGrandTotal(
  List<WafferTransaction> expenses, {
  required pw.Font bold,
  required pw.Font regular,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: pw.BoxDecoration(
      color: _headerTint,
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: _brandGreen, width: 0.8),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            'المجموع',
            style: pw.TextStyle(font: bold, fontSize: 13),
          ),
        ),
        pw.Text(
          _totalsAmount(expenses),
          style: pw.TextStyle(font: bold, fontSize: 13, color: _brandGreen),
        ),
      ],
    ),
  );
}

String _amountText(WafferTransaction expense) {
  return '${formatMoney(expense.amount)} ${currencyLabelFor(expense.currencyCode)}';
}

Future<void> shareExpenseHistoryPdf(List<WafferTransaction> expenses) async {
  try {
    final bytes = await buildExpenseHistoryPdfBytes(expenses);
    final folder = Directory(
      '${(await getTemporaryDirectory()).path}/shared_pdfs',
    );
    await folder.create(recursive: true);
    final file = File(
      '${folder.path}/waffer-expenses-${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    final saved = await file.length();
    if (!await file.exists() || saved != bytes.length || saved <= 0) {
      throw StateError('PDF was not saved at ${file.path}');
    }
    developer.log(
      'PDF saved path=${file.path} bytes=$saved',
      name: 'waffer.pdf',
    );
    await _sharePdfFile(file);
  } catch (error, stack) {
    developer.log(
      'PDF share failed',
      name: 'waffer.pdf',
      error: error,
      stackTrace: stack,
    );
    rethrow;
  }
}

Future<void> _sharePdfFile(File file) async {
  if (Platform.isAndroid) {
    try {
      const channel = MethodChannel('waffer/share_pdf');
      await channel.invokeMethod<void>('share', {'path': file.path});
      return;
    } catch (error, stack) {
      developer.log(
        'Android PDF channel failed, falling back to share_plus',
        name: 'waffer.pdf',
        error: error,
        stackTrace: stack,
      );
    }
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
  return '$label: ${_totalsAmount(expenses)}';
}

// Sum per currency, joined with dots ("1,500 ل.س  •  20 \$").
String _totalsAmount(List<WafferTransaction> expenses) {
  final totals = <String, double>{};
  for (final expense in expenses) {
    totals.update(
      expense.currencyCode,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
  }
  return totals.entries
      .map(
        (entry) =>
            '${formatMoney(entry.value)} ${currencyLabelFor(entry.key)}',
      )
      .join('  •  ');
}
