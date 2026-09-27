// Floating snackbars for success and error feedback using AppColors.

import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

const String insufficientBalanceMessage =
    'المبلغ أكبر من رصيدك الحالي، لا يمكن إتمام العملية.';

// Show a branded snackbar; success uses the accent background.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool success = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
  final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
  final textPrimary =
      isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

  final background = success ? accent : surface;
  final foreground = success ? Colors.white : textPrimary;

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: background,
      elevation: 0,
      duration: const Duration(milliseconds: 2400),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      dismissDirection: DismissDirection.horizontal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (success) ...[
            Icon(Icons.check_rounded, size: 18, color: foreground),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    ),
    snackBarAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 520),
      reverseDuration: Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
  );
}

void showInsufficientBalanceMessage(BuildContext context) {
  showAppSnackBar(context, insufficientBalanceMessage);
}
