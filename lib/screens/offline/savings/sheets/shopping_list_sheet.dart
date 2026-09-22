// Shopping list preview card plus sheets to add items and record purchases as expenses.

import 'package:flutter/material.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/data/models/expense_categories.dart';
import 'package:waffer/data/stores/shopping_list_store.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/screens/offline/home/sheets/add_expense_sheet.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showShoppingListSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _ShoppingListSheet(),
  );
}

// Compact teaser on the savings screen; opens the full shopping list sheet.
class ShoppingListPreviewCard extends StatefulWidget {
  const ShoppingListPreviewCard({super.key});

  @override
  State<ShoppingListPreviewCard> createState() =>
      _ShoppingListPreviewCardState();
}

class _ShoppingListPreviewCardState extends State<ShoppingListPreviewCard> {
  final ShoppingListStore _store = ShoppingListStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final colors = _ShoppingColors.of(context);
        final preview = _store.items.take(3).toList(growable: false);

        return GlassButton(
          onTap: () => showShoppingListSheet(context),
          colorType: GlassColorType.surface,
          borderRadius: 28,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.format_list_bulleted_rounded,
                      size: 21,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'قائمة المشتريات',
                          style: TextStyle(
                            fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          preview.isEmpty
                              ? 'أضف ما تحتاج إلى شرائه'
                              : '${_store.items.length} عناصر محفوظة',
                          style: TextStyle(
                            fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left_rounded, color: colors.textSecondary),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final item in preview)
                  _PreviewItem(item: item, colors: colors),
                if (_store.items.length > preview.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+ ${_store.items.length - preview.length} عناصر أخرى',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// One preview line under the shopping list teaser.
class _PreviewItem extends StatelessWidget {
  final ShoppingItem item;
  final _ShoppingColors colors;

  const _PreviewItem({required this.item, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            item.isPurchased
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 17,
            color: item.isPurchased
                ? colors.accent
                : colors.textSecondary.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                fontSize: 12.5,
                color: item.isPurchased
                    ? colors.textSecondary
                    : colors.textPrimary,
                decoration: item.isPurchased
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Full list: add items, mark purchases, or clear everything.
class _ShoppingListSheet extends StatefulWidget {
  const _ShoppingListSheet();

  @override
  State<_ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<_ShoppingListSheet> {
  final ShoppingListStore _store = ShoppingListStore.instance;
  final TextEditingController _itemController = TextEditingController();

  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  void dispose() {
    _itemController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final name = _itemController.text.trim();
    if (name.isEmpty || _adding) return;

    setState(() => _adding = true);
    await _store.addItem(name);

    if (!mounted) return;
    _itemController.clear();
    setState(() => _adding = false);
  }

  // Confirms then wipes all shopping items (recorded expenses stay).
  Future<void> _clearList() async {
    if (_store.items.isEmpty) return;

    final colors = _ShoppingColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          title: Text(
            'إفراغ قائمة المشتريات',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          content: Text(
            'سيتم حذف كل العناصر من القائمة. المصروفات المسجّلة لن تتأثر.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                  color: colors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'إفراغ',
                style: TextStyle(
                  fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                  color: colors.accent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _store.clearAll();
    if (!mounted) return;
    showAppSnackBar(context, 'تم إفراغ قائمة المشتريات', success: true);
  }

  // Opens the purchase sheet for an unpurchased item.
  Future<void> _purchase(ShoppingItem item) async {
    if (item.isPurchased) return;
    await showPurchaseShoppingItemSheet(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ShoppingColors.of(context);

    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return GlassSheetBody(
          children: [
            const GlassSheetHeader(
              title: 'قائمة المشتريات',
              subtitle: 'احتفظ باحتياجاتك وسجّل المشتريات كمصروفات.',
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SheetTextField(
                    controller: _itemController,
                    hint: 'اسم العنصر',
                    enabled: !_adding,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: _itemController.text.trim().isEmpty
                      ? colors.textSecondary.withValues(alpha: 0.3)
                      : colors.accent,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: _itemController.text.trim().isEmpty || _adding
                        ? null
                        : _addItem,
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: _adding
                          ? const Padding(
                              padding: EdgeInsets.all(17),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_store.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.shopping_basket_outlined,
                      size: 42,
                      color: colors.textSecondary.withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'قائمة المشتريات فارغة',
                      style: TextStyle(
                        fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: _clearList,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  label: Text(
                    'إفراغ القائمة',
                    style: TextStyle(
                      fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final item in _store.items) ...[
                _ShoppingItemTile(
                  item: item,
                  colors: colors,
                  onTap: () => _purchase(item),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        );
      },
    );
  }
}

// Checkbox row; tap opens the purchase sheet when not yet bought.
class _ShoppingItemTile extends StatelessWidget {
  final ShoppingItem item;
  final _ShoppingColors colors;
  final VoidCallback onTap;

  const _ShoppingItemTile({
    required this.item,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: sheetFieldColor(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: item.isPurchased ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Checkbox(
                value: item.isPurchased,
                onChanged: item.isPurchased ? null : (_) => onTap(),
                activeColor: colors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: item.isPurchased
                        ? colors.textSecondary
                        : colors.textPrimary,
                    decoration: item.isPurchased
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.isPurchased ? 'تم الشراء' : 'تسجيل الشراء',
                style: TextStyle(
                  fontFamily: 'BebasNeue', fontFamilyFallback: ['Tajawal'],
                  fontSize: 10.5,
                  color: item.isPurchased
                      ? colors.textSecondary
                      : colors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Records an expense for a shopping item and marks it purchased.
Future<void> showPurchaseShoppingItemSheet(
  BuildContext context,
  ShoppingItem item,
) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => _PurchaseShoppingItemSheet(item: item),
  );
}

// Amount + category form that posts an expense and marks the item bought.
class _PurchaseShoppingItemSheet extends StatefulWidget {
  final ShoppingItem item;

  const _PurchaseShoppingItemSheet({required this.item});

  @override
  State<_PurchaseShoppingItemSheet> createState() =>
      _PurchaseShoppingItemSheetState();
}

class _PurchaseShoppingItemSheetState
    extends State<_PurchaseShoppingItemSheet> {
  final TextEditingController _amountController = TextEditingController();

  String _category = expenseCategories.first.label;
  bool _saving = false;
  late String _currencyCode;

  double get _amount => parseAmount(_amountController.text);

  bool get _exceedsBalance =>
      _amount > TransactionStore.instance.balanceFor(_currencyCode);

  bool get _isValid =>
      _amount > 0 && _amount <= 999999999 && !_exceedsBalance;

  @override
  void initState() {
    super.initState();
    _currencyCode = CurrencyStore.instance.activeCode;
    TransactionStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // Posts the expense via ShoppingListStore and closes on success.
  Future<void> _save() async {
    if (!_isValid || _saving) return;
    setState(() => _saving = true);

    try {
      final saved = await ShoppingListStore.instance.completePurchase(
        itemId: widget.item.id,
        amount: _amount,
        category: _category,
        currencyCode: _currencyCode,
      );

      if (!mounted) return;

      if (saved) {
        Navigator.of(context).maybePop();
        return;
      }
    } catch (_) {
      if (!mounted) return;
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (_amount > TransactionStore.instance.balanceFor(_currencyCode)) {
      showInsufficientBalanceMessage(context);
      return;
    }

    showAppSnackBar(context, 'تعذر حفظ المصروف. حاول مرة أخرى.');
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: 'إضافة مصروف',
          subtitle: widget.item.name,
          onNext: _isValid && !_saving ? _save : null,
        ),
        const SizedBox(height: 18),
        SheetAmountField(
          label: 'السعر',
          controller: _amountController,
          helper: _exceedsBalance
              ? 'أكبر من الرصيد المتاح ${formatMoney(TransactionStore.instance.balanceFor(_currencyCode))} ${currencyLabelFor(_currencyCode)}'
              : null,
          currencyCode: _currencyCode,
          onCurrencyChanged: (code) => setState(() => _currencyCode = code),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'الصنف'),
        ExpenseCategoryGrid(
          selected: _category,
          onSelected: (value) => setState(() => _category = value),
        ),
        const SizedBox(height: 22),
        SheetSaveButton(
          label: 'حفظ المصروف',
          enabled: _isValid && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}

// Local light/dark colors for shopping UI.
class _ShoppingColors {
  final Color accent;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;

  const _ShoppingColors({
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
  });

  factory _ShoppingColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _ShoppingColors(
      accent: isDark ? AppColors.darkAccent : AppColors.lightAccent,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      textPrimary: isDark
          ? AppColors.darkTextPrimary
          : AppColors.lightTextPrimary,
      textSecondary: isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary,
    );
  }
}
