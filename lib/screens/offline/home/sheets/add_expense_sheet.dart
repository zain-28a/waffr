import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffer/core/data/expense_categories.dart';
import 'package:waffer/core/data/recurring_expense.dart';
import 'package:waffer/core/data/recurring_expense_store.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

/// نافذة "إضافة مصروف" الزجاجية.
Future<void> showAddExpenseSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _AddExpenseSheet(),
  );
}

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet();

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  String _category = expenseCategories.first.label;
  String _paymentMethod = paymentMethods.first;

  bool _saving = false;
  bool _recurring = false;
  RecurringUnit _recurringUnit = RecurringUnit.month;
  final TextEditingController _intervalController = TextEditingController(
    text: '1',
  );

  static const double _maxAmount = 999999999;
  static const String _onceLabel = 'مرة واحدة';
  static const String _recurringLabel = 'مصروف متكرر';

  double get _amount => parseAmount(_amountController.text);

  int get _intervalCount {
    final value = int.tryParse(_intervalController.text.trim()) ?? 0;
    return value;
  }

  bool get _isValid {
    if (_amount <= 0 || _amount > _maxAmount) return false;
    if (!_recurring) return true;
    return _intervalCount > 0 && _intervalCount <= 99;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isValid || _saving) return;

    setState(() => _saving = true);

    final note = _noteController.text.trim();

    if (_recurring) {
      await RecurringExpenseStore.instance.addExpense(
        amount: _amount,
        category: _category,
        paymentMethod: _paymentMethod,
        unit: _recurringUnit,
        intervalCount: _intervalCount,
        note: note.isEmpty ? null : note,
      );

      if (!mounted) return;
      Navigator.of(context).maybePop();
      return;
    }

    final added = await TransactionStore.instance.addExpense(
      amount: _amount,
      category: _category,
      paymentMethod: _paymentMethod,
      note: note.isEmpty ? null : note,
    );

    if (!mounted) return;

    if (added == null) {
      setState(() => _saving = false);
      showInsufficientBalanceMessage(context);
      return;
    }

    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: 'إضافة مصروف',
          subtitle: 'أدخل المبلغ واختر التصنيف.',
          onNext: _isValid ? _save : null,
        ),
        const SizedBox(height: 18),
        SheetAmountField(
          label: 'المبلغ',
          controller: _amountController,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'نوع المصروف'),
        SheetChoiceChips(
          options: const [_onceLabel, _recurringLabel],
          selected: _recurring ? _recurringLabel : _onceLabel,
          onSelected: (value) {
            setState(() => _recurring = value == _recurringLabel);
          },
        ),
        if (_recurring) ...[
          const SizedBox(height: 18),
          const SheetFieldLabel(text: 'التكرار'),
          SheetChoiceChips(
            options: const ['يوم', 'أسبوع', 'شهر'],
            selected: _recurringUnit.label,
            onSelected: (value) {
              setState(() {
                _recurringUnit = switch (value) {
                  'أسبوع' => RecurringUnit.week,
                  'شهر' => RecurringUnit.month,
                  _ => RecurringUnit.day,
                };
              });
            },
          ),
          const SizedBox(height: 18),
          SheetFieldLabel(
            text: 'كل كم ${_recurringUnit.label}؟',
          ),
          SheetTextField(
            controller: _intervalController,
            hint: 'مثال: 1',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'التصنيف'),
        ExpenseCategoryGrid(
          selected: _category,
          onSelected: (label) => setState(() => _category = label),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'طريقة الدفع'),
        _PaymentMethods(
          selected: _paymentMethod,
          onSelected: (method) => setState(() => _paymentMethod = method),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'ملاحظة', optional: true),
        SheetTextField(
          controller: _noteController,
          hint: 'مثال: غداء، تاكسي، فاتورة إنترنت...',
        ),
        const SizedBox(height: 22),
        SheetSaveButton(
          label: _recurring ? 'حفظ المصروف المتكرر' : 'حفظ المصروف',
          enabled: _isValid && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}

class ExpenseCategoryGrid extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const ExpenseCategoryGrid({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: expenseCategories
          .map(
            (category) => _CategoryTile(
              category: category,
              isSelected: category.label == selected,
              onTap: () => onSelected(category.label),
            ),
          )
          .toList(),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ExpenseCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final foreground = isSelected ? Colors.white : textPrimary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected ? accent : sheetFieldColor(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              category.icon,
              size: 22,
              color: isSelected ? Colors.white : accent,
            ),
            const SizedBox(height: 8),
            Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethods extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _PaymentMethods({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    return Row(
      children: paymentMethods.map((method) {
        final isSelected = method == selected;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: GestureDetector(
              onTap: () => onSelected(method),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withValues(alpha: 0.14)
                      : sheetFieldColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? accent : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Text(
                  method,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? accent : textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
