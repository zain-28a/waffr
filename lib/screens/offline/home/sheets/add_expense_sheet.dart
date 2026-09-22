import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffer/core/data/category_store.dart';
import 'package:waffer/core/data/currency.dart';
import 'package:waffer/core/data/expense_categories.dart';
import 'package:waffer/core/data/recurring_expense.dart';
import 'package:waffer/core/data/recurring_expense_store.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';
import 'package:waffer/widgets/sheets/monthly_income_required_sheet.dart';

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
  int _multiplier = 1;
  late String _currencyCode;
  RecurringUnit _recurringUnit = RecurringUnit.month;
  final TextEditingController _intervalController = TextEditingController(
    text: '1',
  );

  static const double _maxAmount = 999999999;
  static const String _onceLabel = 'مرة واحدة';
  static const String _recurringLabel = 'مصروف متكرر';

  double get _enteredAmount => parseAmount(_amountController.text);

  double get _amount => _enteredAmount * _multiplier;

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
  void initState() {
    super.initState();
    _currencyCode = CurrencyStore.instance.activeCode;
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
      await TransactionStore.instance.ensureLoaded();
      if (!TransactionStore.instance.hasConfiguredMonthlyIncomeFor(
        _currencyCode,
      )) {
        if (!mounted) return;
        setState(() => _saving = false);
        await showMonthlyIncomeRequiredSheet(
          context,
          requirement: MonthlyIncomeRequirement.expense,
        );
        return;
      }
      await RecurringExpenseStore.instance.addExpense(
        amount: _amount,
        category: _category,
        paymentMethod: _paymentMethod,
        unit: _recurringUnit,
        intervalCount: _intervalCount,
        note: note.isEmpty ? null : note,
        currencyCode: _currencyCode,
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
      currencyCode: _currencyCode,
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      children: [
        GlassSheetHeader(
          title: 'إضافة مصروف',
          subtitle: 'أدخل المبلغ واختر التصنيف.',
          onNext: _isValid ? _save : null,
        ),
        const SizedBox(height: 10),
        SheetAmountField(
          label: 'المبلغ',
          controller: _amountController,
          helper: _multiplier == 1
              ? null
              : 'الإجمالي ${formatMoney(_amount)} ${currencyLabelFor(_currencyCode)}',
          currencyCode: _currencyCode,
          onCurrencyChanged: (code) => setState(() => _currencyCode = code),
          leading: _AmountMultiplierControl(
            value: _multiplier,
            onChanged: (value) => setState(() => _multiplier = value),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        const SheetFieldLabel(text: 'نوع المصروف'),
        SheetChoiceChips(
          options: const [_onceLabel, _recurringLabel],
          selected: _recurring ? _recurringLabel : _onceLabel,
          onSelected: (value) async {
            final recurring = value == _recurringLabel;
            if (recurring) {
              await TransactionStore.instance.ensureLoaded();
              if (!context.mounted) return;
              if (!TransactionStore.instance.hasConfiguredMonthlyIncomeFor(
                _currencyCode,
              )) {
                await showMonthlyIncomeRequiredSheet(
                  context,
                  requirement: MonthlyIncomeRequirement.expense,
                );
                return;
              }
            }
            if (!mounted) return;
            setState(() => _recurring = recurring);
          },
        ),
        SheetExpand(
          visible: _recurring,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
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
        const SizedBox(height: 10),
        const SheetFieldLabel(text: 'التصنيف'),
        ExpenseCategoryGrid(
          selected: _category,
          onSelected: (label) => setState(() => _category = label),
        ),
        
        const SizedBox(height: 10),
        const SheetFieldLabel(text: 'ملاحظة', optional: true),
        SheetTextField(
          controller: _noteController,
          hint: 'مثال: غداء، تاكسي، فاتورة إنترنت...',
        ),
        const SizedBox(height: 12),
        SheetSaveButton(
          label: _recurring ? 'حفظ المصروف المتكرر' : 'حفظ المصروف',
          enabled: _isValid && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}

class _AmountMultiplierControl extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _AmountMultiplierControl({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_AmountMultiplierControl> createState() =>
      _AmountMultiplierControlState();
}

class _AmountMultiplierControlState extends State<_AmountMultiplierControl> {
  static const List<int> _values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      _removeEntry();
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.sizeOf(context);

    _entry = OverlayEntry(
      builder: (overlayContext) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
        final textPrimary = isDark
            ? AppColors.darkTextPrimary
            : AppColors.lightTextPrimary;
        final textSecondary = isDark
            ? AppColors.darkTextSecondary
            : AppColors.lightTextSecondary;
        final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
        const cardWidth = 220.0;
        final left = (origin.dx + size.width - cardWidth)
            .clamp(12.0, screen.width - cardWidth - 12);
        final top = origin.dy > 120 ? origin.dy - 108 : origin.dy + size.height + 6;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _removeEntry,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: cardWidth,
              child: Material(
                color: surface,
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final value in _values)
                        _MultiplierOption(
                          label: '×$value',
                          selected: value == widget.value,
                          accent: accent,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () {
                            widget.onChanged(value);
                            _removeEntry();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Text(
        '×${widget.value}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
      ),
    );
  }
}

class _MultiplierOption extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _MultiplierOption({
    required this.label,
    required this.selected,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.16) : textPrimary.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
          child: SizedBox(
          width: 36,
          height: 32,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
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
    final draft = await _openCategoryDialog();
    if (draft == null || !mounted) return;

    final created = await CategoryStore.instance.addCustom(
      draft.label,
      iconIndex: draft.iconIndex,
    );
    if (created == null || !mounted) return;

    widget.onSelected(created);
  }

  Future<_CustomCategoryDraft?> _openCategoryDialog({
    ExpenseCategory? editing,
  }) {
    final store = CategoryStore.instance;
    return showDialog<_CustomCategoryDraft>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CustomCategoryNameDialog(
        title: editing == null ? 'تصنيف مخصص' : 'تعديل التصنيف',
        submitLabel: editing == null ? 'إضافة' : 'حفظ',
        initialLabel: editing?.label,
        initialIconIndex:
            editing == null ? 0 : store.iconIndexOf(editing.label),
        ignoring: editing?.label,
      ),
    );
  }

  Future<void> _showActions(
    BuildContext tileContext,
    ExpenseCategory category,
  ) async {
    if (!CategoryStore.instance.isCustom(category.label)) return;

    final tileBox = tileContext.findRenderObject() as RenderBox?;
    if (tileBox == null || !tileBox.hasSize) return;

    final origin = tileBox.localToGlobal(Offset.zero);
    final size = tileBox.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    final action = await showMenu<String>(
      context: context,
      color: surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy - 8,
        origin.dx + size.width,
        origin.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_rounded, size: 18, color: textPrimary.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Text(
                'تعديل',
                style: TextStyle(fontFamily: 'Tajawal', color: textPrimary),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_rounded, size: 18, color: Color(0xFFD3544D)),
              SizedBox(width: 8),
              Text(
                'حذف',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  color: Color(0xFFD3544D),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;

    if (action == 'edit') {
      await _editCustom(category);
    } else if (action == 'delete') {
      await _deleteCustom(category.label);
    }
  }

  Future<void> _editCustom(ExpenseCategory category) async {
    final store = CategoryStore.instance;
    final draft = await _openCategoryDialog(editing: category);
    if (draft == null || !mounted) return;

    final renamed = await store.renameCustom(
      category.label,
      draft.label,
      iconIndex: draft.iconIndex,
    );
    if (renamed == null || !mounted) return;

    if (widget.selected == category.label) {
      widget.onSelected(renamed);
    }
  }

  Future<void> _deleteCustom(String label) async {
    final removed = await CategoryStore.instance.removeCustom(label);
    if (!removed || !mounted) return;

    if (widget.selected == label) {
      widget.onSelected(expenseCategories.first.label);
    }
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
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 1.12,
            children: [
              for (final category in categories)
                Builder(
                  builder: (tileContext) {
                    return _CategoryTile(
                      key: ValueKey(category.label),
                      category: category,
                      isSelected: category.label == widget.selected,
                      onTap: () => widget.onSelected(category.label),
                      onLongPress:
                          CategoryStore.instance.isCustom(category.label)
                          ? () => _showActions(tileContext, category)
                          : null,
                    );
                  },
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
  final String title;
  final String submitLabel;
  final String? initialLabel;
  final int initialIconIndex;
  final String? ignoring;

  const _CustomCategoryNameDialog({
    this.title = 'تصنيف مخصص',
    this.submitLabel = 'إضافة',
    this.initialLabel,
    this.initialIconIndex = 0,
    this.ignoring,
  });

  @override
  State<_CustomCategoryNameDialog> createState() =>
      _CustomCategoryNameDialogState();
}

class _CustomCategoryNameDialogState extends State<_CustomCategoryNameDialog> {
  late final TextEditingController _controller;
  String? _error;
  late int _iconIndex;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLabel ?? '');
    _iconIndex = clampCustomIconIndex(widget.initialIconIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = CategoryStore.instance.validateName(
      _controller.text,
      ignoring: widget.ignoring,
    );
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
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 420,
        height: maxHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Column(
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(height: 14),
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
                  filled: true,
                  fillColor: sheetFieldColor(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'الشعار',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  itemCount: customCategoryIconChoices.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemBuilder: (context, i) {
                    return _IconChoice(
                      icon: customCategoryIconChoices[i],
                      selected: i == _iconIndex,
                      accent: accent,
                      onTap: () => setState(() => _iconIndex = i),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _submit,
                      child: Text(
                        widget.submitLabel,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: side,
              height: side,
              alignment: Alignment.center,
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
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ExpenseCategory category;
  final bool isSelected;
  final bool isAction;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _CategoryTile({
    super.key,
    required this.category,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
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
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? accent
              : isAction
                  ? sheetFieldColor(context).withValues(alpha: 0.55)
                  : sheetFieldColor(context),
          borderRadius: BorderRadius.circular(14),
          border: isAction
              ? Border.all(color: accent.withValues(alpha: 0.32), width: 1.2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              category.icon,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(height: 4),
            Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 10.5,
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
