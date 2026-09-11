import 'package:flutter/material.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/sheets/glass_sheet.dart';

/// نافذة "إضافة دخل" الزجاجية.
Future<void> showAddIncomeSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _AddIncomeSheet(),
  );
}

class _AddIncomeSheet extends StatefulWidget {
  const _AddIncomeSheet();

  @override
  State<_AddIncomeSheet> createState() => _AddIncomeSheetState();
}

class _AddIncomeSheetState extends State<_AddIncomeSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _sourceController = TextEditingController();

  bool _saving = false;

  static const double _maxAmount = 999999999;

  double get _amount => parseAmount(_amountController.text);

  bool get _isValid => _amount > 0 && _amount <= _maxAmount;

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isValid || _saving) return;

    setState(() => _saving = true);

    final source = _sourceController.text.trim();

    await TransactionStore.instance.addIncome(
      amount: _amount,
      source: source.isEmpty ? null : source,
    );

    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: 'إضافة دخل',
          subtitle: 'أدخل المبلغ ليضاف إلى رصيدك.',
          onNext: _isValid ? _save : null,
        ),
        const SizedBox(height: 18),
        SheetAmountField(
          label: 'مبلغ الدخل',
          controller: _amountController,
          helper: 'الحد الأقصى ${formatMoney(_maxAmount)} $currencyLabel',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'مصدر الدخل', optional: true),
        SheetTextField(
          controller: _sourceController,
          hint: 'مثال: راتب، عمل حر، تحويل...',
        ),
        const SizedBox(height: 22),
        SheetSaveButton(
          label: 'حفظ الدخل',
          enabled: _isValid && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}
