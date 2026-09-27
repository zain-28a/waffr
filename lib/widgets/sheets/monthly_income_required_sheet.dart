// Bottom sheet shown when the user tries to create a plan or recurring expense
// without a monthly income set.
import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

/// Why income is required — wording differs for plans vs expenses.
enum MonthlyIncomeRequirement { plan, expense }

/// Explains that monthly income must be set in settings, then dismisses.
Future<void> showMonthlyIncomeRequiredSheet(
  BuildContext context, {
  required MonthlyIncomeRequirement requirement,
}) {
  final isPlan = requirement == MonthlyIncomeRequirement.plan;
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
            subtitle: isPlan
                ? 'لا يمكن إنشاء الخطة الدورية الآن.'
                : 'لا يمكن إنشاء مصروف متكرر الآن.',
          ),
          const SizedBox(height: 16),
          Text(
            isPlan
                ? 'الخطة الدورية تُحسب من دخلك الشهري. افتح الإعدادات واضبط «الدخل الشهري» أولاً، ثم أعد المحاولة.'
                : 'المصروف المتكرر يحتاج دخلاً شهرياً محدداً حتى يُخصم في موعده. افتح الإعدادات واضبط «الدخل الشهري» أولاً.',
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
