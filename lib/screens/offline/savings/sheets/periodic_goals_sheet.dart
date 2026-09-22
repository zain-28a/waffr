import 'package:flutter/material.dart';
import 'package:waffer/core/data/savings_goal.dart';
import 'package:waffer/core/data/transaction.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';
import 'package:waffer/widgets/sheets/monthly_income_required_sheet.dart';

Future<void> showPeriodicGoalsSheet(BuildContext context) async {
  await TransactionStore.instance.ensureLoaded();
  if (!context.mounted) return;
  if (!TransactionStore.instance.hasConfiguredMonthlyIncome) {
    await showMonthlyIncomeRequiredSheet(
      context,
      requirement: MonthlyIncomeRequirement.plan,
    );
    return;
  }

  final plan = TransactionStore.instance.activePeriodicGoal;

  return showGlassSheet<void>(
    context: context,
    builder: (context) => plan == null
        ? const _PeriodicGoalsSheet()
        : _PeriodicPlanDetailsSheet(goal: plan),
  );
}

class _PeriodicGoalsSheet extends StatefulWidget {
  const _PeriodicGoalsSheet();

  @override
  State<_PeriodicGoalsSheet> createState() => _PeriodicGoalsSheetState();
}

class _PeriodicGoalsSheetState extends State<_PeriodicGoalsSheet> {
  static const List<int> _percents = [5, 10, 15, 20];
  static const List<GoalDurationPreset> _durations = [
    GoalDurationPreset.threeMonths,
    GoalDurationPreset.sixMonths,
    GoalDurationPreset.year,
  ];

  final TransactionStore _store = TransactionStore.instance;

  int _percent = 10;
  GoalDurationPreset _duration = GoalDurationPreset.sixMonths;
  bool _preview = false;
  bool _saving = false;

  RecurringFrequency get _frequency => RecurringFrequency.monthly;

  double get _income => _store.configuredMonthlyIncome ?? 0;

  double get _perPeriod => _income * _percent / 100;

  int get _cycles => _duration.cycleCount(_frequency);

  double get _expected => _perPeriod * _cycles;

  bool get _isMeaningful => _income > 0 && _perPeriod > 0 && _expected > 0;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _confirm() async {
    if (!_isMeaningful || _saving) return;
    setState(() => _saving = true);

    final ok = await _store.applyPeriodicPlan(
      percent: _percent.toDouble(),
      duration: _duration,
      frequency: _frequency,
      income: _income,
    );

    if (!mounted) return;
    if (ok) Navigator.of(context).maybePop();
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: _preview ? 'معاينة الخطة' : 'أهداف ادخار دورية',
          subtitle: _preview
              ? 'راجع النتيجة قبل التأكيد.'
              : 'اختر النسبة والمدة حسب دخلك.',
          onNext: _preview
              ? (_isMeaningful ? _confirm : null)
              : (_isMeaningful ? () => setState(() => _preview = true) : null),
        ),
        const SizedBox(height: 18),
        SheetSwap(
          switchKey: _preview,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _preview ? _buildPreview(context) : _buildPicker(context),
          ),
        ),
        const SizedBox(height: 22),
        SheetSaveButton(
          label: _preview ? 'تأكيد الخطة' : 'معاينة الخطة',
          enabled: _isMeaningful && !_saving,
          onTap: _preview ? _confirm : () => setState(() => _preview = true),
        ),
      ],
    );
  }

  List<Widget> _buildPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    if (_income <= 0) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(
            'أضف دخلاً شهرياً أولاً لاقتراح خطط مناسبة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              color: textSecondary,
            ),
          ),
        ),
      ];
    }

    return [
      SheetFieldLabel(
        text: _frequency == RecurringFrequency.weekly
            ? 'الدخل الأسبوعي المعتمد'
            : 'الدخل الشهري المعتمد',
      ),
      Text(
        '${formatMoney(_income)} $currencyLabel',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
        ),
      ),
      const SizedBox(height: 18),
      const SheetFieldLabel(text: 'نسبة الادخار'),
      SheetChoiceChips(
        options: _percents.map((item) => '$item٪').toList(),
        selected: '$_percent٪',
        onSelected: (value) {
          setState(() {
            _percent = int.tryParse(value.replaceAll('٪', '')) ?? 10;
          });
        },
      ),
      const SizedBox(height: 18),
      const SheetFieldLabel(text: 'المدة'),
      SheetChoiceChips(
        options: _durations.map((item) => item.label).toList(),
        selected: _duration.label,
        onSelected: (value) {
          setState(() {
            _duration = _durations.firstWhere((item) => item.label == value);
          });
        },
      ),
    ];
  }

  List<Widget> _buildPreview(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final periodWord =
        _frequency == RecurringFrequency.weekly ? 'أسبوعياً' : 'شهرياً';

    return [
      GlassContainer(
        colorType: GlassColorType.surface,
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          children: [
            _PreviewRow(
              label: _frequency == RecurringFrequency.weekly
                  ? 'الدخل الأسبوعي'
                  : 'الدخل الشهري',
              value: '${formatMoney(_income)} $currencyLabel',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            _PreviewRow(
              label: 'نسبة الادخار',
              value: '$_percent٪',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            _PreviewRow(
              label: 'الاقتطاع $periodWord',
              value: '${formatMoney(_perPeriod)} $currencyLabel',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            _PreviewRow(
              label: 'المدة',
              value: _duration.label,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            _PreviewRow(
              label: 'المبلغ المستهدف',
              value: '${formatMoney(_expected)} $currencyLabel',
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              emphasize: true,
            ),
          ],
        ),
      ),
    ];
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;
  final bool emphasize;

  const _PreviewRow({
    required this.label,
    required this.value,
    required this.textPrimary,
    required this.textSecondary,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13.5,
                color: textSecondary,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: emphasize ? 16 : 14,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodicPlanDetailsSheet extends StatefulWidget {
  final SavingsGoal goal;

  const _PeriodicPlanDetailsSheet({required this.goal});

  @override
  State<_PeriodicPlanDetailsSheet> createState() =>
      _PeriodicPlanDetailsSheetState();
}

class _PeriodicPlanDetailsSheetState extends State<_PeriodicPlanDetailsSheet> {
  final TransactionStore _store = TransactionStore.instance;
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    if (_deleting) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          title: Text(
            'حذف الخطة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          content: const Text(
            'هل أنت متأكد من حذف هذه الخطة الدورية؟',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Tajawal', fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'إلغاء',
                style: TextStyle(fontFamily: 'Tajawal', color: textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'حذف',
                style: TextStyle(fontFamily: 'Tajawal', color: accent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final deleted = await _store.deleteGoal(widget.goal.id);
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _deleting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final periodWord = switch (widget.goal.deductFrequency) {
      RecurringFrequency.weekly => 'أسبوعياً',
      RecurringFrequency.monthly => 'شهرياً',
      RecurringFrequency.none => 'بدون تكرار',
    };
    final percent = widget.goal.allocatePercent;
    final amount = widget.goal.allocateAmount;

    return GlassSheetBody(
      children: [
        const GlassSheetHeader(
          title: 'الخطة الجارية',
          subtitle: 'تفاصيل الخطة الدورية المحفوظة.',
        ),
        const SizedBox(height: 18),
        GlassContainer(
          colorType: GlassColorType.surface,
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            children: [
              _PreviewRow(
                label: 'الاسم',
                value: widget.goal.name,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
              if (percent != null && percent > 0)
                _PreviewRow(
                  label: 'نسبة الادخار',
                  value: '${percent.round()}٪',
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              if (amount != null && amount > 0)
                _PreviewRow(
                  label: 'الاقتطاع $periodWord',
                  value: '${formatMoney(amount)} $currencyLabel',
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              _PreviewRow(
                label: 'التردد',
                value: periodWord,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
              _PreviewRow(
                label: 'المدة',
                value: widget.goal.duration.label,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
              _PreviewRow(
                label: 'المبلغ المستهدف',
                value:
                    '${formatMoney(widget.goal.targetAmount)} $currencyLabel',
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                emphasize: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Material(
          color: textPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _deleting ? null : _confirmDelete,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'حذف الخطة',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: textPrimary.withValues(alpha: 0.75),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
