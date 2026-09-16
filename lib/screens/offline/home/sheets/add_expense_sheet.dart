import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffer/core/data/category_store.dart';
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
        SheetExpand(
          visible: _recurring,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
          ),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'التصنيف'),
        ExpenseCategoryGrid(
          selected: _category,
          onSelected: (label) => setState(() => _category = label),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'طريقة الدفع'),
        SheetChoiceChips(
          options: paymentMethods,
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

class ExpenseCategoryGrid extends StatefulWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const ExpenseCategoryGrid({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<ExpenseCategoryGrid> createState() => _ExpenseCategoryGridState();
}

class _ExpenseCategoryGridState extends State<ExpenseCategoryGrid> {
  @override
  void initState() {
    super.initState();
    CategoryStore.instance.ensureLoaded();
  }

  Future<void> _createCustom() async {
    final draft = await showDialog<_CustomCategoryDraft>(
      context: context,
      builder: (_) => const _CustomCategoryNameDialog(),
    );
    if (draft == null || !mounted) return;

    final created = await CategoryStore.instance.addCustom(
      draft.label,
      iconIndex: draft.iconIndex,
    );
    if (created == null || !mounted) return;

    widget.onSelected(created);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ListenableBuilder(
        listenable: CategoryStore.instance,
        builder: (context, _) {
          final categories = CategoryStore.instance.selectableCategories;
          return GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.92,
            children: [
              for (final category in categories)
                _CategoryTile(
                  key: ValueKey(category.label),
                  category: category,
                  isSelected: category.label == widget.selected,
                  onTap: () => widget.onSelected(category.label),
                ),
              _CategoryTile(
                key: const ValueKey('__custom_action__'),
                category: customCategoryAction,
                isSelected: false,
                isAction: true,
                onTap: _createCustom,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CustomCategoryDraft {
  final String label;
  final int iconIndex;

  const _CustomCategoryDraft({
    required this.label,
    required this.iconIndex,
  });
}

class _CustomCategoryNameDialog extends StatefulWidget {
  const _CustomCategoryNameDialog();

  @override
  State<_CustomCategoryNameDialog> createState() =>
      _CustomCategoryNameDialogState();
}

class _CustomCategoryNameDialogState extends State<_CustomCategoryNameDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  int _iconIndex = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = CategoryStore.instance.validateName(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      _CustomCategoryDraft(
        label: _controller.text.trim(),
        iconIndex: _iconIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    return AlertDialog(
      title: const Text('تصنيف مخصص'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              maxLength: 16,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'مثال: إيجار، قهوة...',
                errorText: _error,
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'الشعار',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < customCategoryIconChoices.length; i++)
                  _IconChoice(
                    icon: customCategoryIconChoices[i],
                    selected: i == _iconIndex,
                    accent: accent,
                    onTap: () => setState(() => _iconIndex = i),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('إضافة', style: TextStyle(color: accent)),
        ),
      ],
    );
  }
}

class _IconChoice extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected ? accent : sheetFieldColor(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: selected ? Colors.white : accent,
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ExpenseCategory category;
  final bool isSelected;
  final bool isAction;
  final VoidCallback onTap;

  const _CategoryTile({
    super.key,
    required this.category,
    required this.isSelected,
    required this.onTap,
    this.isAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final foreground = isSelected ? Colors.white : textPrimary;
    final iconColor = isSelected ? Colors.white : accent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? accent
              : isAction
                  ? sheetFieldColor(context).withValues(alpha: 0.55)
                  : sheetFieldColor(context),
          borderRadius: BorderRadius.circular(18),
          border: isAction
              ? Border.all(color: accent.withValues(alpha: 0.32), width: 1.2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              category.icon,
              size: 22,
              color: iconColor,
            ),
            const SizedBox(height: 8),
            Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Tajawal',
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
