// Design-token colors for light and dark UI. Values are the source of truth.

import 'package:flutter/material.dart';

/// The app's color tokens. Widgets read these (or [AppPalette]) instead of
/// writing color values.
class AppColors {
  AppColors._();

  /// Light page background: soft aqua grey, so white cards lift off it
  /// without heavy shadows.
  static const Color lightBackground = Color(0xFFEAF1F3);

  /// Light cards and sheets.
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Light main text.
  static const Color lightTextPrimary = Color(0xFF0D1D22);

  /// Light captions and hints.
  static const Color lightTextSecondary = Color(0xFF5C6E74);

  /// Light brand petrol blue (Youth Guide): buttons, selection, highlights.
  static const Color lightAccent = Color(0xFF005E76);

  /// Text and icons on [lightAccent].
  static const Color lightOnAccent = Color(0xFFFFFFFF);

  /// Dark page background: deep petrol, close to black.
  static const Color darkBackground = Color(0xFF06171C);

  /// Dark cards and sheets, lighter than the background so they read as
  /// raised.
  static const Color darkSurface = Color(0xFF0F262D);

  /// Dark main text.
  static const Color darkTextPrimary = Color(0xFFEEF5F6);

  /// Dark captions and hints.
  static const Color darkTextSecondary = Color(0xFF9AB0B5);

  /// Dark accent: the logo's teal green (Youth Guide), bright on petrol.
  static const Color darkAccent = Color(0xFF38B8A0);

  /// Text and icons on [darkAccent]. The accent is bright, so it takes
  /// deep petrol text instead of white.
  static const Color darkOnAccent = Color(0xFF00262E);

  /// Delete / remove / errors, light theme.
  static const Color lightDestructive = Color(0xFF8E3B3B);

  /// Delete / remove / errors, dark theme.
  static const Color darkDestructive = Color(0xFFE38B8B);

  /// Needs attention (low balance, charge waiting for approval), light.
  static const Color lightWarning = Color(0xFF8A6A24);

  /// Needs attention, dark.
  static const Color darkWarning = Color(0xFFE2C27A);

  /// [lightOnAccent] or [darkOnAccent] for the current theme.
  static Color onAccentOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkOnAccent
      : lightOnAccent;

  /// [lightWarning] or [darkWarning] for the current theme.
  static Color warningOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkWarning
      : lightWarning;

  /// [lightDestructive] or [darkDestructive] for the current theme.
  static Color destructiveOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkDestructive
      : lightDestructive;
}
