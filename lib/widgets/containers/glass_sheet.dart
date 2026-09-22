import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass.dart';

/// Dim used in place of the old BackdropFilter overlay.
const Color kSheetBarrierColor = Color.fromARGB(114, 0, 0, 0);

/// نافذة سفلية زجاجية تُضبّب الشاشة التي تحتها.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: kSheetBarrierColor,
    elevation: 0,
    builder: (context) => _GlassSheetShell(
      builder: builder,
      heightFactor: heightFactor,
    ),
  );
}

class _GlassSheetShell extends StatelessWidget {
  final WidgetBuilder builder;
  final double? heightFactor;

  const _GlassSheetShell({
    required this.builder,
    this.heightFactor,
  });

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;

    final maxSheetHeight =
        (screenHeight - keyboard - 28).clamp(220.0, screenHeight);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: heightFactor == null
          ? ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: builder(context),
            )
          : SizedBox(
              height: (screenHeight * heightFactor!).clamp(220.0, maxSheetHeight),
              child: builder(context),
            ),
    );
  }
}

/// هيكل ثابت الارتفاع: الترويسة ثابتة والمحتوى يتمرّر داخل الشيت.
class GlassSheetFixedBody extends StatelessWidget {
  final Widget header;
  final Widget body;

  const GlassSheetFixedBody({
    super.key,
    required this.header,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: GlassContainer(
        colorType: GlassColorType.surface,
        tintOpacity: 1,
        radius: const BorderRadius.vertical(top: Radius.circular(34)),
        padding: EdgeInsets.zero,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: header,
              ),
              const SizedBox(height: 8),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// الهيكل الزجاجي للنافذة: زوايا علوية كبيرة ومحتوى قابل للتمرير.
class GlassSheetBody extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const GlassSheetBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      colorType: GlassColorType.surface,
      tintOpacity: 1,
      radius: const BorderRadius.vertical(top: Radius.circular(34)),
      padding: EdgeInsets.zero,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: padding,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
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
                      fontFamily: 'Tajawal',
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
                      fontFamily: 'Tajawal',
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
  final Widget? action;

  const SheetFieldLabel({
    super.key,
    required this.text,
    this.optional = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: textSecondary,
            ),
          ),
          
          if (optional)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Text(
                ' (اختياري)',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  color: textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action!,
          ],
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

  /// يحل محل الفراغ المقابل لـ «ل.س» على الجهة اليمنى.
  final Widget? leading;

  const SheetAmountField({
    super.key,
    required this.label,
    required this.controller,
    this.helper,
    this.onChanged,
    this.leading,
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
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 46,
                child: leading,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  cursorColor: textPrimary,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontFamily: 'Tajawal',
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
                    fontFamily: 'Tajawal',
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
                fontFamily: 'Tajawal',
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
        fontFamily: 'Tajawal',
        fontSize: 15,
        color: enabled ? textPrimary : textSecondary.withValues(alpha: 0.55),
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: sheetFieldColor(context),
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Tajawal',
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

    if (options.isEmpty) return const SizedBox.shrink();

    final selectedIndex = options.indexOf(selected).clamp(0, options.length - 1);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: sheetFieldColor(context),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / options.length;

            return Stack(
              children: [
                AnimatedPositionedDirectional(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  start: selectedIndex * itemWidth,
                  width: itemWidth,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: accent, width: 1.4),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final option in options)
                      Expanded(
                        child: GestureDetector(
                          onTap: enabled ? () => onSelected(option) : null,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 4,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                                color: option == selected ? accent : textPrimary,
                              ),
                              child: Text(
                                option,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// يظهر أو يخفي محتوى الشيت مع تمدد وبهتان هادئ.
class SheetExpand extends StatelessWidget {
  final bool visible;
  final Widget child;

  const SheetExpand({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        layoutBuilder: (currentChild, _) =>
            currentChild ?? const SizedBox(width: double.infinity),
        child: visible
            ? KeyedSubtree(key: const ValueKey('sheet-expand-on'), child: child)
            : const SizedBox(width: double.infinity, key: ValueKey('off')),
      ),
    );
  }
}

/// تبديل محتوى الشيت عند تغيير الخيار، مع بهتان خفيف.
class SheetSwap extends StatelessWidget {
  final Object switchKey;
  final Widget child;

  const SheetSwap({super.key, required this.switchKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      layoutBuilder: (currentChild, _) =>
          currentChild ?? const SizedBox(width: double.infinity),
      child: KeyedSubtree(key: ValueKey(switchKey), child: child),
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
                  fontFamily: 'Tajawal',
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
