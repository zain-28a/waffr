import 'package:flutter/material.dart';
import 'package:waffer/data/models/transaction.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

// Glass bottom sheet for logging income (amount, frequency, leftover balance).

Future<void> showAddIncomeSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _AddIncomeSheet(),
  );
}

class _AddIncomeSheet extends StatefulWidget {
  const _AddIncomeSheet();

  @override
  State<_AddIncomeSheet> createState() => _AddIncomeSheetState();
}

class _AddIncomeSheetState extends State<_AddIncomeSheet> {
  static const String _freqNone = 'بدون مدة';
  static const String _freqWeekly = 'أسبوعي';
  static const String _freqMonthly = 'شهري';
  // Weekly income still works in the store; the chip is hidden for now.
  static const bool _weeklyIncomeChoiceEnabled = false;
  static const List<String> _frequencyOptions = [
    if (_weeklyIncomeChoiceEnabled) _freqWeekly,
    _freqMonthly,
    _freqNone,
  ];
  static const String _keepBalance = 'إبقاء الرصيد';
  static const String _moveBalance = 'نقل الرصيد للتوفير';

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _sourceController = TextEditingController();

  final TransactionStore _store = TransactionStore.instance;

  String _frequencyLabel = _freqNone;
  String _balanceAction = _keepBalance;
  bool _saving = false;
  late String _currencyCode;

  static const double _maxAmount = 999999999;

  double get _amount => parseAmount(_amountController.text);

  bool get _isValid => _amount > 0 && _amount <= _maxAmount;

  RecurringFrequency get _frequency => switch (_frequencyLabel) {
        _freqWeekly => RecurringFrequency.weekly,
        _freqMonthly => RecurringFrequency.monthly,
        _ => RecurringFrequency.none,
      };

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
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isValid || _saving) return;

    setState(() => _saving = true);

    final source = _sourceController.text.trim();

    await _store.addIncome(
      amount: _amount,
      source: source.isEmpty ? null : source,
      frequency: _frequency,
      moveBalanceToSavings: _balanceAction == _moveBalance,
      currencyCode: _currencyCode,
    );

    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  // Explains what happens to leftover balance when a new income period starts.
  void _showBalanceInfo() {
    showAppInfoDialog(
      context,
      title: 'الرصيد الحالي',
      message:
          'يُظهر هذا القسم الرصيد المتبقي لديك من الفترة السابقة. اختر ما تريد فعله به: نقله إلى التوفير، أو إبقاءه ضمن رصيدك الجديد.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBalance = _store.balanceFor(_currencyCode) > 0;

    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: 'إضافة دخل',
          subtitle: 'أدخل المبلغ ليضاف إلى رصيدك.',
          onNext: _isValid ? _save : null,
        ),
        const SizedBox(height: 18),
        SheetAmountField(
          label: 'مبلغ الدخل',
          controller: _amountController,
          helper:
              'الحد الأقصى ${formatMoney(_maxAmount)} ${currencyLabelFor(_currencyCode)}',
          currencyCode: _currencyCode,
          onCurrencyChanged: (code) => setState(() => _currencyCode = code),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'مدة المبلغ'),
        SheetChoiceChips(
          options: _frequencyOptions,
          selected: _frequencyLabel,
          onSelected: (value) => setState(() => _frequencyLabel = value),
        ),
        SheetExpand(
          visible: hasBalance,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              SheetFieldLabel(
                text: 'الرصيد الحالي',
                action: _SheetInfoButton(onTap: _showBalanceInfo),
              ),
              SheetChoiceChips(
                options: const [_keepBalance, _moveBalance],
                selected: _balanceAction,
                onSelected: (value) => setState(() => _balanceAction = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SheetFieldLabel(text: 'مصدر الدخل', optional: true),
        SheetTextField(
          controller: _sourceController,
          hint: 'مثال: راتب، عمل حر، تحويل...',
        ),
        const SizedBox(height: 22),
        SheetSaveButton(
          label: 'حفظ الدخل',
          enabled: _isValid && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}

class _SheetInfoButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SheetInfoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: textSecondary.withValues(alpha: 0.0)),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: accent,
          ),
        ),
      ),
    );
  }
}
