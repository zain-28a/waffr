// Bottom sheet shown when the user tries to create a periodic savings plan
// without a monthly income set.
import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

/// Explains that monthly income must be set in settings, then dismisses.
Future<void> showMonthlyIncomeRequiredSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final textSecondary = isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary;

      return GlassSheetBody(
        children: [
          GlassSheetHeader(
            title: 'يلزم الدخل الشهري',
            subtitle: 'لا يمكن إنشاء الخطة الدورية الآن.',
          ),
          const SizedBox(height: 16),
          Text(
            'الخطة الدورية تُحسب من دخلك الشهري. افتح الإعدادات وحدّد «الدخل الشهري» أولاً، ثم أعد المحاولة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              fontSize: 14,
              height: 1.7,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 22),
          SheetSaveButton(
            label: 'حسناً',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    },
  );
}
