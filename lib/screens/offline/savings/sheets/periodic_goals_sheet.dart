import 'package:flutter/material.dart';
import 'package:waffer/core/data/savings_goal.dart';
import 'package:waffer/core/data/transaction.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showPeriodicGoalsSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _PeriodicGoalsSheet(),
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

  RecurringFrequency get _frequency => _store.preferredIncomeFrequency;

  double get _income => _store.referenceIncome(_frequency);

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
        if (!_preview) ..._buildPicker(context) else ..._buildPreview(context),
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
            'أضف دخلاً أسبوعياً أو شهرياً أولاً لاقتراح خطط مناسبة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
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
          fontFamily: 'Cairo',
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
                fontFamily: 'Cairo',
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
                fontFamily: 'Cairo',
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
