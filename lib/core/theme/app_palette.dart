// Resolves AppColors tokens for the current Theme brightness.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_color.dart';

// Picks the light or dark token set so screens do not repeat brightness checks.
class AppPalette {
  final Color background;
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  factory AppPalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const AppPalette(
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        accent: AppColors.darkAccent,
        textPrimary: AppColors.darkTextPrimary,
        textSecondary: AppColors.darkTextSecondary,
      );
    }
    return const AppPalette(
      background: AppColors.lightBackground,
      surface: AppColors.lightSurface,
      accent: AppColors.lightAccent,
      textPrimary: AppColors.lightTextPrimary,
      textSecondary: AppColors.lightTextSecondary,
    );
  }
}
