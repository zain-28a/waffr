import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffer/core/data/savings_goal.dart';
import 'package:waffer/core/data/transaction.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showCreateGoalSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _CreateGoalSheet(),
  );
}

class _CreateGoalSheet extends StatefulWidget {
  const _CreateGoalSheet();

  @override
  State<_CreateGoalSheet> createState() => _CreateGoalSheetState();
}

enum _ContributionType { percent, fixed, custom }

class _CreateGoalSheetState extends State<_CreateGoalSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _percentController = TextEditingController();
  final TextEditingController _fixedAmountController =
      TextEditingController();

  final TransactionStore _store = TransactionStore.instance;

  bool _saving = false;
  late _ContributionType _type;

  static const double _maxAmount = 999999999;

  double get _target => parseAmount(_targetController.text);

  double get _fixedAmount => parseAmount(_fixedAmountController.text);

  RecurringFrequency get _frequency =>
      _store.preferredIncomeFrequency;

  double get _income =>
      _store.referenceIncome(_frequency);

  bool get _isCustom => _type == _ContributionType.custom;

  int get _percent {
    final value =
        int.tryParse(_percentController.text.trim()) ?? 0;

    return value.clamp(0, 100);
  }

  double get _periodAmount {
    if (_isCustom) {
      return 0;
    }

    if (_type == _ContributionType.fixed) {
      return _fixedAmount;
    }

    if (_percent <= 0 || _income <= 0) {
      return 0;
    }

    return _income * _percent / 100;
  }

  int get _requiredPeriods {
    if (_isCustom || _target <= 0 || _periodAmount <= 0) {
      return 0;
    }

    return (_target / _periodAmount).ceil();
  }

  double get _expectedAmount {
    if (_requiredPeriods <= 0) {
      return 0;
    }

    return _periodAmount * _requiredPeriods;
  }

  bool get _isValid {
    if (_nameController.text.trim().isEmpty) {
      return false;
    }

    if (_target <= 0 || _target > _maxAmount) {
      return false;
    }

    if (_isCustom) {
      return true;
    }

    if (_income <= 0) {
      return false;
    }

    if (_type == _ContributionType.fixed) {
      return _fixedAmount > 0;
    }

    return _percent > 0;
  }

  String get _frequencyTitle {
    return _frequency == RecurringFrequency.weekly
        ? 'أسبوعي'
        : 'شهري';
  }

  String get _periodSingular {
    return _frequency == RecurringFrequency.weekly
        ? 'أسبوع'
        : 'شهر';
  }

  @override
  void initState() {
    super.initState();

    _type = _store.hasRecurringIncome
        ? _ContributionType.percent
        : _ContributionType.custom;

    _store.ensureLoaded().then((_) {
      if (!mounted) return;

      setState(() {
        if (!_store.hasRecurringIncome) {
          _type = _ContributionType.custom;
        }
      });
    });

    _nameController.addListener(_refresh);
    _targetController.addListener(_refresh);
    _percentController.addListener(_refresh);
    _fixedAmountController.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;

    setState(() {});
  }

  void _switchMethod(_ContributionType type) {
    if (_type == type) {
      return;
    }

    setState(() {
      _type = type;

      if (type == _ContributionType.fixed) {
        _percentController.clear();
      } else if (type == _ContributionType.percent) {
        _fixedAmountController.clear();
      }
    });
  }

  Future<void> _save() async {
    if (!_isValid || _saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final periods = _isCustom ? null : _requiredPeriods;

    final duration = _isCustom
        ? GoalDurationPreset.year
        : GoalDurationPresetLabel.fromCount(
            periods ?? 1,
            frequency: _frequency,
          );

    final success = await _store.createGoal(
      name: _nameController.text.trim(),
      targetAmount: _target,
      duration: duration,
      allocatePercent: _type == _ContributionType.percent
          ? _percent.toDouble()
          : null,
      allocateAmount: _isCustom ? null : _periodAmount,
      deductFrequency: _isCustom
          ? RecurringFrequency.none
          : _frequency,
      isPeriodic: !_isCustom,
      durationCount: periods,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).maybePop();
      return;
    }

    setState(() {
      _saving = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _percentController.dispose();
    _fixedAmountController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    final colors = _GoalColors(
      textPrimary: isDark
          ? AppColors.darkTextPrimary
          : AppColors.lightTextPrimary,
      textSecondary: isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary,
      accent: isDark
          ? AppColors.darkAccent
          : AppColors.lightAccent,
    );

    return GlassSheetBody(
      children: [
        GlassSheetHeader(
          title: 'إنشاء هدف',
          subtitle: 'حدّد هدفك واختر طريقة الادخار.',
          onNext: _isValid && !_saving ? _save : null,
        ),

        const SizedBox(height: 18),

        const SheetFieldLabel(
          text: 'اسم الهدف',
        ),

        SheetTextField(
          controller: _nameController,
          hint: 'مثال: صندوق الطوارئ',
        ),

        const SizedBox(height: 18),

        SheetAmountField(
          label: 'المبلغ المستهدف',
          controller: _targetController,
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: 20),

        Text(
          'نوع الخطة',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _MethodButton(
                title: 'نسبة من الدخل',
                subtitle: _frequencyTitle,
                selected: _type == _ContributionType.percent,
                onTap: () => _switchMethod(_ContributionType.percent),
                colors: colors,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MethodButton(
                title: 'مبلغ ثابت',
                subtitle: 'كل $_periodSingular',
                selected: _type == _ContributionType.fixed,
                onTap: () => _switchMethod(_ContributionType.fixed),
                colors: colors,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MethodButton(
                title: 'مبلغ مخصص',
                subtitle: 'يدوي',
                selected: _isCustom,
                onTap: () => _switchMethod(_ContributionType.custom),
                colors: colors,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        if (_type == _ContributionType.percent)
          ...[
            const SheetFieldLabel(
              text: 'نسبة الادخار',
            ),

            SheetTextField(
              controller: _percentController,
              hint: 'مثال: 10',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              'الدخل المرجعي: '
              '${formatMoney(_income)} '
              '$currencyLabel / $_periodSingular',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ]
        else if (_type == _ContributionType.fixed)
          ...[
            const SheetFieldLabel(
              text: 'مبلغ الادخار لكل دورة',
            ),

            SheetTextField(
              controller: _fixedAmountController,
              hint: 'مثال: 100000',
              keyboardType: TextInputType.number,
              inputFormatters: [
                ThousandsInputFormatter(),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              'سيتم اقتطاع هذا المبلغ من الدخل كل '
              '$_periodSingular.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ]
        else
          ...[
            Text(
              'المساهمات هنا ليست تلقائية. انقل بنفسك من رصيدك إلى الهدف متى شئت عبر «ادخار مبلغ».',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                height: 1.5,
                color: colors.textSecondary,
              ),
            ),
          ],

        if (!_isCustom && _periodAmount > 0 && _target > 0)
          ...[
            const SizedBox(height: 18),

            _GoalPreview(
              target: _target,
              periodAmount: _periodAmount,
              periods: _requiredPeriods,
              expected: _expectedAmount,
              frequency: _frequency,
              colors: colors,
            ),
          ],

        const SizedBox(height: 22),

        SheetSaveButton(
          label: 'حفظ الهدف',
          enabled: _isValid && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final _GoalColors colors;

  const _MethodButton({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.12)
              : colors.textPrimary.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colors.accent.withValues(alpha: 0.45)
                : colors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colors.accent
                      : colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalPreview extends StatelessWidget {
  final double target;
  final double periodAmount;
  final int periods;
  final double expected;
  final RecurringFrequency frequency;
  final _GoalColors colors;

  const _GoalPreview({
    required this.target,
    required this.periodAmount,
    required this.periods,
    required this.expected,
    required this.frequency,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final periodSingular =
        frequency == RecurringFrequency.weekly
            ? 'أسبوع'
            : 'شهر';

    final periodPlural =
        frequency == RecurringFrequency.weekly
            ? 'أسابيع'
            : 'أشهر';

    final durationText = periods == 1
        ? 'أسبوع واحد'
        : '$periods $periodPlural';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.accent.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        children: [
          Text(
            'معاينة الخطة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            '${formatMoney(periodAmount)} '
            '$currencyLabel / $periodSingular',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.accent,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'المدة المتوقعة: $durationText',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: colors.textPrimary,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'المجموع المتوقع: '
            '${formatMoney(expected)} $currencyLabel',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              color: colors.textSecondary,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            'الهدف: ${formatMoney(target)} $currencyLabel',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalColors {
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;

  const _GoalColors({
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
  });
}