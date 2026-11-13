// Edit sheet for a ledger row: change or delete an expense, an income, or
// a manual saving / withdrawal after it was recorded.

import 'package:flutter/material.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/shopping_list_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/screens/offline/home/sheets/add_expense_sheet.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';
import 'package:waffr/widgets/dialogs/waffr_date_picker.dart';
import 'package:waffr/widgets/motion/pressable.dart';

/// Opens the editor for [transaction]. Automatic savings transfers (period
/// leftovers, plan deductions) are not editable and open nothing.
Future<void> showEditTransactionSheet(
  BuildContext context,
  WaffrTransaction transaction,
) {
  final store = TransactionStore.instance;
  final editable =
      transaction.isExpense ||
      transaction.isIncome ||
      store.isEditableTransfer(transaction);
  if (!editable) return Future<void>.value();
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _EditTransactionSheet(transaction: transaction),
  );
}

/// Confirms and deletes [transaction], returning its money to where it came
/// from. Returns true when it was deleted.
Future<bool> confirmDeleteTransaction(
  BuildContext context,
  WaffrTransaction transaction,
) async {
  final store = TransactionStore.instance;
  final amount =
      '${formatMoney(transaction.amount)} '
      '${currencyLabelFor(transaction.currencyCode)}';
  final (title, message) = switch (transaction.type) {
    TransactionType.expense => (
      'حذف المصروف',
      'سيُحذف هذا المصروف من السجل ويُعاد $amount إلى رصيدك.',
    ),
    TransactionType.income => (
      'حذف الدخل',
      'سيُحذف هذا الدخل من السجل ويُخصم $amount من رصيدك.',
    ),
    TransactionType.savingsIn => (
      'حذف التوفير',
      'سيُحذف هذا التوفير ويُعاد $amount إلى رصيدك.',
    ),
    TransactionType.savingsOut => (
      'حذف السحب',
      'سيُحذف هذا السحب ويُعاد $amount إلى التوفير.',
    ),
  };

  final confirmed = await showAppConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: 'حذف',
    destructive: true,
  );
  if (confirmed != true || !context.mounted) return false;

  final deleted = switch (transaction.type) {
    TransactionType.expense => await store.undoExpense(transaction.id),
    TransactionType.income => await store.undoIncome(transaction.id),
    _ => await store.deleteSavingsTransfer(transaction.id),
  };
  if (!context.mounted) return deleted;

  if (!deleted) {
    showAppSnackBar(context, 'تعذّر الحذف: الرصيد لا يسمح بذلك.');
    return false;
  }
  if (transaction.isExpense) {
    await ShoppingListStore.instance.revertPurchaseForExpense(transaction.id);
    if (!context.mounted) return true;
  }
  AppHaptics.success();
  showAppSnackBar(context, 'تم الحذف', success: true);
  return true;
}

class _EditTransactionSheet extends StatefulWidget {
  final WaffrTransaction transaction;

  const _EditTransactionSheet({required this.transaction});

  @override
  State<_EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<_EditTransactionSheet> {
  final TransactionStore _store = TransactionStore.instance;

  late final WaffrTransaction _original = widget.transaction;
  late final TextEditingController _amount = TextEditingController(
    text: formatMoney(_original.amount),
  );
  late final TextEditingController _note = TextEditingController(
    text: _original.note ?? '',
  );
  late String _category = categoryFor(_original.category).label;
  late String _payment = paymentMethods.contains(_original.paymentMethod)
      ? _original.paymentMethod!
      : paymentMethods.first;
  late DateTime _date = _original.dateTime;
  bool _saving = false;

  bool get _isExpense => _original.isExpense;
  bool get _isIncome => _original.isIncome;

  /// One-off incomes and expenses can move to another day; a recurring
  /// income belongs to its period.
  bool get _canChangeDate =>
      _isExpense ||
      (_isIncome && _original.frequency == RecurringFrequency.none);

  double get _value => parseAmount(_amount.text);

  bool get _changed =>
      _value != _original.amount ||
      _note.text.trim() != (_original.note ?? '').trim() ||
      (_isExpense &&
          (_category != categoryFor(_original.category).label ||
              _payment != _original.paymentMethod)) ||
      _date != _original.dateTime;

  bool get _valid => _value > 0 && _changed;

  String get _title => switch (_original.type) {
    TransactionType.expense => 'تعديل المصروف',
    TransactionType.income => 'تعديل الدخل',
    TransactionType.savingsIn => 'تعديل التوفير',
    TransactionType.savingsOut => 'تعديل السحب',
  };

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = deviceNow();
    final picked = await showWaffrDatePicker(
      context: context,
      title: 'تاريخ العملية',
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDate: _date,
    );
    if (picked == null || !mounted) return;
    // Keep the time of day; only the day moves.
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
        _date.second,
      );
    });
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final note = _note.text.trim();
    final date = _date != _original.dateTime ? _date : null;

    final ok = switch (_original.type) {
      TransactionType.expense => await _store.updateExpense(
        _original.id,
        amount: _value,
        category: _category,
        paymentMethod: _payment,
        note: note,
        clearNote: note.isEmpty,
        dateTime: date,
      ),
      TransactionType.income => await _store.updateIncome(
        _original.id,
        amount: _value,
        note: note,
        clearNote: note.isEmpty,
        dateTime: date,
      ),
      _ => await _store.updateSavingsTransfer(_original.id, _value),
    };
    if (!mounted) return;

    if (!ok) {
      setState(() => _saving = false);
      AppHaptics.warning();
      showInsufficientBalanceMessage(context);
      return;
    }
    AppHaptics.success();
    Navigator.of(context).maybePop();
  }

  Future<void> _delete() async {
    final deleted = await confirmDeleteTransaction(context, _original);
    if (deleted && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: _title,
          subtitle: 'غيّر ما تريد ثم احفظ، أو احذف العملية.',
        ),
        const SizedBox(height: 16),
        SheetAmountField(
          label: 'المبلغ',
          controller: _amount,
          currencyCode: _original.currencyCode,
          onChanged: (_) => setState(() {}),
        ),
        if (_isExpense) ...[
          const SizedBox(height: 14),
          const SheetFieldLabel(text: 'التصنيف'),
          ExpenseCategoryGrid(
            selected: _category,
            onSelected: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 14),
          const SheetFieldLabel(text: 'طريقة الدفع'),
          SheetChoiceChips(
            options: paymentMethods,
            selected: _payment,
            onSelected: (value) => setState(() => _payment = value),
          ),
        ],
        if (_isExpense || _isIncome) ...[
          const SizedBox(height: 14),
          SheetFieldLabel(
            text: _isIncome ? 'مصدر الدخل' : 'ملاحظة',
            optional: true,
          ),
          SheetTextField(
            controller: _note,
            hint: _isIncome
                ? 'مثال: راتب، عمل حر، تحويل...'
                : 'مثال: غداء، تاكسي، فاتورة إنترنت...',
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (_canChangeDate) ...[
          const SizedBox(height: 14),
          const SheetFieldLabel(text: 'التاريخ'),
          Semantics(
            button: true,
            label: 'تغيير التاريخ',
            child: Pressable(
              onTap: _pickDate,
              depth: 0.02,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: sheetFieldColor(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(AppIcons.calendar, size: 19, color: palette.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_date.day} ${CalendarPeriod.monthName(_date.month)} '
                        '${_date.year}',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontFamilyFallback: const ['Tajawal'],
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      AppIcons.chevronDown,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        SheetSaveButton(
          label: 'حفظ التعديلات',
          enabled: _valid && !_saving,
          onTap: _save,
        ),
        const SizedBox(height: 10),
        SheetDestructiveButton(
          label: 'حذف',
          icon: AppIcons.trash,
          onTap: _saving ? null : _delete,
        ),
      ],
    );
  }
}
