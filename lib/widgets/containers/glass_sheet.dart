import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass.dart';

/// نافذة سفلية زجاجية تُضبّب الشاشة التي تحتها.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    elevation: 0,
    builder: (context) => _GlassSheetShell(builder: builder),
  );
}

class _GlassSheetShell extends StatelessWidget {
  final WidgetBuilder builder;

  const _GlassSheetShell({required this.builder});

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            constraints.maxHeight.isFinite ? constraints.maxHeight : screenHeight;

        final maxSheetHeight =
            (available - keyboard - 28).clamp(220.0, available);

        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSheetHeight),
                  child: builder(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// الهيكل الزجاجي للنافذة: زوايا علوية كبيرة ومحتوى قابل للتمرير.
class GlassSheetBody extends StatelessWidget {
  final List<Widget> children;

  const GlassSheetBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      colorType: GlassColorType.surface,
      tintOpacity: 0.92,
      blurSigma: 18,
      radius: const BorderRadius.vertical(top: Radius.circular(34)),
      padding: EdgeInsets.zero,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class GlassSheetHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onNext;

  const GlassSheetHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        Container(
          width: 42,
          height: 5,
          decoration: BoxDecoration(
            color: textSecondary.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 18),
        Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              child: SheetCircleButton(
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (onNext != null)
              Positioned(
                right: 0,
                child: SheetCircleButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: onNext!,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class SheetCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const SheetCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Material(
      color: sheetFieldColor(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            size: 22,
            color: textPrimary.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

/// عنوان صغير فوق الحقول، مع كلمة "اختياري" عند الحاجة.
class SheetFieldLabel extends StatelessWidget {
  final String text;
  final bool optional;

  const SheetFieldLabel({
    super.key,
    required this.text,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (optional)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Text(
                'اختياري',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// حقل المبلغ الكبير مع وحدة العملة والحد الأقصى.
class SheetAmountField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? helper;
  final ValueChanged<String>? onChanged;

  const SheetAmountField({
    super.key,
    required this.label,
    required this.controller,
    this.helper,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: sheetFieldColor(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 46),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  cursorColor: textPrimary,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: textSecondary.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  currencyLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(
              helper!,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                color: textSecondary.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// حقل نصي اختياري بنفس مظهر حقول النافذة.
class SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const SheetTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: TextAlign.right,
      cursorColor: textPrimary,
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 15,
        color: enabled ? textPrimary : textSecondary.withValues(alpha: 0.55),
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: sheetFieldColor(context),
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 14,
          color: textSecondary.withValues(alpha: 0.7),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// صف خيارات بنفس أسلوب طرق الدفع في نافذة المصروف.
class SheetChoiceChips extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  const SheetChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Row(
      children: options.map((option) {
        final isSelected = option == selected;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: GestureDetector(
              onTap: enabled ? () => onSelected(option) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 6),
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    option,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? accent : textPrimary,
                    ),
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

/// زر الحفظ الكبير أسفل النافذة.
class SheetSaveButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const SheetSaveButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Material(
      color: enabled ? accent : textSecondary.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.check_rounded, size: 20, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// لون الحقول داخل النافذة: خلفية التطبيق مع لمسة من اللون الأساسي.
Color sheetFieldColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final base = isDark ? AppColors.darkBackground : AppColors.lightBackground;
  final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

  return Color.alphaBlend(accent.withValues(alpha: isDark ? 0.10 : 0.07), base);
}

/// يعرض المبلغ بفواصل الآلاف أثناء الكتابة، بحد أقصى 9 أرقام.
class ThousandsInputFormatter extends TextInputFormatter {
  static const int maxDigits = 9;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return const TextEditingValue();

    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (trimmed.length > maxDigits) return oldValue;

    final formatted = formatMoney(int.parse(trimmed));

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// يقرأ المبلغ المكتوب بعد إزالة الفواصل.
double parseAmount(String text) {
  return double.tryParse(text.replaceAll(',', '').trim()) ?? 0;
}
