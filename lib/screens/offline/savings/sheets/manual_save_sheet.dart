import 'package:flutter/material.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showManualSaveSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _ManualSaveSheet(),
  );
}

class _ManualSaveSheet extends StatefulWidget {
  const _ManualSaveSheet();

  @override
  State<_ManualSaveSheet> createState() => _ManualSaveSheetState();
}

class _ManualSaveSheetState extends State<_ManualSaveSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TransactionStore _store = TransactionStore.instance;
  bool _saving = false;

  double get _amount => parseAmount(_amountController.text);

  bool get _isValid => _amount > 0 && _amount <= _store.balance;

  @override
  void initState() {
    super.initState();
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

    final ok = await _store.saveManually(_amount);
    if (!mounted) return;
    if (ok) Navigator.of(context).maybePop();
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: 'ادخار مبلغ',
          subtitle: 'يُنقل من الرصيد التشغيلي إلى الادخار.',
          onNext: _isValid ? _save : null,
        ),
        const SizedBox(height: 18),
        SheetAmountField(
          label: 'المبلغ',
          controller: _amountController,
          helper:
              'المتاح ${formatMoney(_store.balance)} $currencyLabel',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 22),
        SheetSaveButton(
          label: 'تأكيد الادخار',
          enabled: _isValid && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}
