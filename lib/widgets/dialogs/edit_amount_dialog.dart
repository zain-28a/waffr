import 'package:flutter/material.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

/// حوار تعديل مبلغ، بنفس التحقق المستخدم للدخل الشهري.
/// يُرجعه الحوار عندما يزيل المستخدم المبلغ المضبوط بالكامل.
class AmountDialogCleared {
  const AmountDialogCleared();
}

const amountDialogCleared = AmountDialogCleared();

class EditAmountDialog extends StatefulWidget {
  final String title;
  final double initialAmount;
  final Color accent;
  final bool allowClear;

  const EditAmountDialog({
    super.key,
    required this.title,
    required this.initialAmount,
    required this.accent,
    this.allowClear = false,
  });

  @override
  State<EditAmountDialog> createState() => _EditAmountDialogState();
}

class _EditAmountDialogState extends State<EditAmountDialog> {
  static const double _maxAmount = 999999999;

  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
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
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        if (widget.allowClear)
          TextButton(
            onPressed: () => Navigator.of(context).pop(amountDialogCleared),
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
