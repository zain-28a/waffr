// Resolves AppColors tokens for the current Theme brightness.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_color.dart';

/// Picks the light or dark token set so screens do not repeat brightness checks.
class AppPalette {
  /// Page background.
  final Color background;

  /// Cards and sheets.
  final Color surface;

  /// Brand accent.
  final Color accent;

  /// Text and icons on an [accent] fill.
  final Color onAccent;

  /// Main text.
  final Color textPrimary;

  /// Captions and hints.
  final Color textSecondary;

  /// Teal light used for glows and the aurora, beside the brand green.
  final Color glow;

  /// The page light-field colors (see `AuroraBackdrop`).
  final List<Color> aurora;

  /// A palette of the given tokens.
  const AppPalette({
    required this.background,
    required this.surface,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.glow,
    required this.aurora,
  });

  /// The light theme tokens.
  static const AppPalette light = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    accent: AppColors.lightAccent,
    onAccent: AppColors.lightOnAccent,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    glow: AppColors.lightGlow,
    aurora: AppColors.lightAurora,
  );

  /// The dark theme tokens.
  static const AppPalette dark = AppPalette(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    accent: AppColors.darkAccent,
    onAccent: AppColors.darkOnAccent,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    glow: AppColors.darkGlow,
    aurora: AppColors.darkAurora,
  );

  /// The palette for the theme around [context].
  factory AppPalette.of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}
