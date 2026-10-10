import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/expense_preset_store.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/models/expense_preset.dart';
import 'package:waffr/data/models/recurring_expense.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/screens/offline/home/sheets/expense_presets_dialog.dart';
import 'package:waffr/screens/offline/obligations/obligations_sheet.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';
import 'package:waffr/widgets/dialogs/edit_delete_menu.dart';

// Glass bottom sheet for one-off or recurring expenses, plus category picks.

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

  String _category = CategoryStore.instance.defaultLabel;
  final String _paymentMethod = paymentMethods.first;

  bool _saving = false;
  bool _recurring = false;
  // Star filled: the expense is also kept as a preset once it is saved.
  bool _saveAsPreset = false;
  // Multiplies the entered amount (×1–×10) before saving.
  int _multiplier = 1;
  late String _currencyCode;
  RecurringUnit _recurringUnit = RecurringUnit.month;
  // Null until the user picks; then the default follows the monthly income.
  bool? _confirmChoice;
  final TextEditingController _intervalController = TextEditingController(
    text: '1',
  );

  static const double _maxAmount = 999999999;
  static const String _onceLabel = 'مرة واحدة';
  static const String _recurringLabel = 'مصروف متكرر';

  double get _enteredAmount => parseAmount(_amountController.text);

  double get _amount => _enteredAmount * _multiplier;

  String? get _amountHelper {
    final symbol = currencyLabelFor(_currencyCode);
    if (_exceedsBalance) {
      final available = TransactionStore.instance.balanceFor(_currencyCode);
      return 'أكبر من الرصيد المتاح ${formatMoney(available)} $symbol';
    }
    if (_multiplier == 1) return null;
    return 'الإجمالي ${formatMoney(_amount)} $symbol';
  }

  // Fixed salary → automatic; no monthly income set → ask before deducting.
  bool get _requiresConfirmation =>
      _confirmChoice ??
      !TransactionStore.instance.hasConfiguredMonthlyIncomeFor(_currencyCode);

  int get _intervalCount {
    final value = int.tryParse(_intervalController.text.trim()) ?? 0;
    return value;
  }

  // One-off expenses cannot exceed the balance in that currency. Recurring
  // bills are saved for later, so they are not blocked here.
  bool get _exceedsBalance {
    if (_recurring || _amount <= 0) return false;
    return _amount > TransactionStore.instance.balanceFor(_currencyCode);
  }

  bool get _isValid {
    if (_amount <= 0 || _amount > _maxAmount || _exceedsBalance) return false;
    if (!_recurring) return true;
    return _intervalCount > 0 && _intervalCount <= 99;
  }

  @override
  void initState() {
    super.initState();
    _currencyCode = CurrencyStore.instance.activeCode;
    TransactionStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    ExpensePresetStore.instance.ensureLoaded();
    CategoryStore.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      final store = CategoryStore.instance;
      if (!store.isSelectable(_category)) {
        setState(() => _category = store.defaultLabel);
      }
    });
  }

  // Star: pick a saved expense, or mark this one to be saved as a preset.
  Future<void> _openPresets() async {
    FocusScope.of(context).unfocus();
    final choice = await showExpensePresetsDialog(
      context,
      marked: _saveAsPreset,
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case ExpensePresetMark():
        setState(() => _saveAsPreset = true);
      case ExpensePresetUnmark():
        setState(() => _saveAsPreset = false);
      case ExpensePresetSelected(:final preset):
        await _applyPreset(preset);
    }
  }

  // Fills every field from [preset]; the user can still edit before saving.
  Future<void> _applyPreset(ExpensePreset preset) async {
    final recurring = preset.recurring;
    final code = CurrencyStore.instance.enabledCodes.contains(
      preset.currencyCode,
    )
        ? preset.currencyCode
        : _currencyCode;

    final note = preset.note ?? '';
    setState(() {
      _amountController.text = formatMoney(preset.amount);
      _multiplier = preset.multiplier;
      _currencyCode = code;
      _category = preset.category;
      _noteController.text = note;
      _recurring = recurring;
      _recurringUnit = preset.unit;
      _intervalController.text = '${preset.intervalCount}';
      _saveAsPreset = false;
    });
  }

  Future<void> _storePresetIfMarked(String note) async {
    if (!_saveAsPreset) return;
    await ExpensePresetStore.instance.add(
      ExpensePreset(
        id: ExpensePreset.newId(),
        amount: _enteredAmount,
        multiplier: _multiplier,
        currencyCode: _currencyCode,
        category: _category,
        paymentMethod: _paymentMethod,
        note: note.isEmpty ? null : note,
        recurring: _recurring,
        unit: _recurringUnit,
        intervalCount: _recurring ? _intervalCount : 1,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  // One-off goes to TransactionStore; recurring becomes an obligation.
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
        currencyCode: _currencyCode,
        requiresConfirmation: _requiresConfirmation,
      );
      await _storePresetIfMarked(note);

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

    await _storePresetIfMarked(note);
    if (!mounted) return;
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
          helper: _amountHelper,
          currencyCode: _currencyCode,
          onCurrencyChanged: (code) => setState(() => _currencyCode = code),
          multiplier: _multiplier,
          onMultiplierChanged: (value) => setState(() => _multiplier = value),
          multiplierAccessory: _PresetStarButton(
            filled: _saveAsPreset,
            onTap: _openPresets,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
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
              const SizedBox(height: 10),
              const SheetFieldLabel(
                text: 'طريقة الخصم',
                action: SheetInfoButton(
                  title: kDeductModeInfoTitle,
                  message: kDeductModeInfoMessage,
                ),
              ),
              SheetChoiceChips(
                options: const [kDeductAutomaticLabel, kDeductConfirmLabel],
                selected: _requiresConfirmation
                    ? kDeductConfirmLabel
                    : kDeductAutomaticLabel,
                onSelected: (value) => setState(
                  () => _confirmChoice = value == kDeductConfirmLabel,
                ),
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

// Star above the × button. Filled (accent green) once the expense is marked
// to be kept as a preset.
class _PresetStarButton extends StatelessWidget {
  final bool filled;
  final VoidCallback onTap;

  const _PresetStarButton({required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Semantics(
      button: true,
      label: filled ? 'سيُحفظ كمصروف محفوظ' : 'المصروفات المحفوظة',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 36,
          height: 26,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              key: ValueKey(filled),
              size: 22,
              color: filled ? accent : textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// Built-in + custom categories; long-press a tile to remove it (custom tiles
// can also be edited).
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
    return showAppDialog<_CustomCategoryDraft>(
      context: context,
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

  // Long-press menu: custom categories can be edited or removed; built-in
  // ones can be removed.
  Future<void> _showActions(
    BuildContext tileContext,
    ExpenseCategory category,
  ) async {
    final store = CategoryStore.instance;
    final custom = store.isCustom(category.label);
    if (!custom && !store.isBuiltIn(category.label)) return;

    final action = await showEditDeleteMenu(
      context,
      anchorContext: tileContext,
      allowEdit: custom,
    );

    if (!mounted || action == null) return;

    switch (action) {
      case EditDeleteAction.edit:
        await _editCustom(category);
      case EditDeleteAction.delete:
        await _deleteCategory(category.label);
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

  // Old expenses keep the label, icon and color of a removed category.
  Future<void> _deleteCategory(String label) async {
    final store = CategoryStore.instance;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'حذف تصنيف «$label»',
      message: store.isBuiltIn(label)
          ? 'لن يظهر في قائمة التصنيفات بعد الآن. المصروفات السابقة تبقى كما هي، '
              'ويمكنك إعادته بإضافة تصنيف مخصص بالاسم نفسه.'
          : 'لن يظهر في قائمة التصنيفات بعد الآن. المصروفات السابقة تبقى كما هي.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final removed = await store.removeCategory(label);
    if (!removed || !mounted) return;

    if (widget.selected == label) {
      widget.onSelected(store.defaultLabel);
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
                      onLongPress: () =>
                          _showActions(tileContext, category),
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

// Name + icon picker used when creating or renaming a custom category.
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
    final width = MediaQuery.sizeOf(context).width;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width > 460 ? 400 : width - 40,
        height: maxHeight,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
                  'الأيقونة',
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
                    child: AppDialogActionButton(
                      action: AppDialogAction(
                        label: 'إلغاء',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppDialogActionButton(
                      action: AppDialogAction(
                        label: widget.submitLabel,
                        primary: true,
                        onPressed: _submit,
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
                color: selected ? AppColors.onAccentOf(context) : accent,
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

    final onAccent = AppColors.onAccentOf(context);
    final foreground = isSelected ? onAccent : textPrimary;
    final iconColor = isSelected ? onAccent : accent;

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
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
