// Resolves AppColors tokens for the current Theme brightness.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_color.dart';

// Picks the light or dark token set so screens do not repeat brightness checks.
class AppPalette {
  final Color background;
  final Color surface;
  final Color accent;

  /// Text and icons on an [accent] fill.
  final Color onAccent;
  final Color textPrimary;
  final Color textSecondary;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
  });

  static const AppPalette light = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    accent: AppColors.lightAccent,
    onAccent: AppColors.lightOnAccent,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
  );

  static const AppPalette dark = AppPalette(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    accent: AppColors.darkAccent,
    onAccent: AppColors.darkOnAccent,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
  );

  factory AppPalette.of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}
