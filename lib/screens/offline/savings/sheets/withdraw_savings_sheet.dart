import 'package:flutter/material.dart';
import 'package:waffer/core/data/currency.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showWithdrawSavingsSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _WithdrawSavingsSheet(),
  );
}

class _WithdrawSavingsSheet extends StatefulWidget {
  const _WithdrawSavingsSheet();

  @override
  State<_WithdrawSavingsSheet> createState() => _WithdrawSavingsSheetState();
}

class _WithdrawSavingsSheetState extends State<_WithdrawSavingsSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TransactionStore _store = TransactionStore.instance;
  bool _saving = false;
  late String _currencyCode;

  double get _amount => parseAmount(_amountController.text);

  bool get _isValid =>
      _amount > 0 && _amount <= _store.savingsBalanceFor(_currencyCode);

  @override
  void initState() {
    super.initState();
    _currencyCode = CurrencyStore.instance.activeCode;
    _store.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isValid || _saving) return;
    setState(() => _saving = true);

    final ok = await _store.withdrawFromSavings(
      _amount,
      currencyCode: _currencyCode,
    );
    if (!mounted) return;
    if (ok) Navigator.of(context).maybePop();
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: 'سحب إلى الرصيد',
          subtitle: 'يُعاد المبلغ من الادخار إلى الرصيد التشغيلي.',
          onNext: _isValid ? _save : null,
        ),
        const SizedBox(height: 18),
        SheetAmountField(
          label: 'المبلغ',
          controller: _amountController,
          helper:
              'المدّخر ${formatMoney(_store.savingsBalanceFor(_currencyCode))} ${currencyLabelFor(_currencyCode)}',
          currencyCode: _currencyCode,
          onCurrencyChanged: (code) => setState(() => _currencyCode = code),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 22),
        SheetSaveButton(
          label: 'تأكيد السحب',
          enabled: _isValid && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}
