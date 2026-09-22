// Alert dialog for editing a money amount (same validation as monthly income).
import 'package:flutter/material.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

/// Returned when the user clears a previously set amount (allowClear path).
class AmountDialogCleared {
  final String currencyCode;
  const AmountDialogCleared(this.currencyCode);
}

/// Successful save: parsed amount plus the currency chosen in the dialog.
class EditAmountResult {
  final double amount;
  final String currencyCode;

  const EditAmountResult(this.amount, this.currencyCode);
}

/// Amount + currency editor with optional clear action.
class EditAmountDialog extends StatefulWidget {
  final String title;
  final double initialAmount;
  final Color accent;
  final bool allowClear;
  final String? currencyCode;

  const EditAmountDialog({
    super.key,
    required this.title,
    required this.initialAmount,
    required this.accent,
    this.allowClear = false,
    this.currencyCode,
  });

  @override
  State<EditAmountDialog> createState() => _EditAmountDialogState();
}

class _EditAmountDialogState extends State<EditAmountDialog> {
  static const double _maxAmount = 999999999;

  late final TextEditingController _controller;
  late String _currencyCode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currencyCode = Currencies.normalize(
      widget.currencyCode ?? CurrencyStore.instance.activeCode,
    );
    _controller = TextEditingController(
      text: widget.initialAmount > 0 && widget.initialAmount.isFinite
          ? formatMoney(widget.initialAmount)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Validates and pops [EditAmountResult], or shows an inline error.
  void _submit() {
    final amount = parseAmount(_controller.text);
    if (!amount.isFinite || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً أكبر من صفر');
      return;
    }
    if (amount > _maxAmount) {
      setState(() => _error = 'المبلغ أكبر من الحد المسموح');
      return;
    }
    Navigator.of(context).pop(EditAmountResult(amount, _currencyCode));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsInputFormatter()],
            textAlign: TextAlign.center,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'المبلغ',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SheetCurrencySelector(
              currencyCode: _currencyCode,
              onChanged: (code) => setState(() => _currencyCode = code),
              dense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        if (widget.allowClear)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(AmountDialogCleared(_currencyCode)),
            child: Text('إزالة الدخل', style: TextStyle(color: widget.accent)),
          ),
        TextButton(
          onPressed: _submit,
          child: Text('حفظ', style: TextStyle(color: widget.accent)),
        ),
      ],
    );
  }
}
