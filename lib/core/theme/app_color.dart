// Design-token colors for light and dark UI. Values are the source of truth.

import 'package:flutter/material.dart';

/// The app's color tokens. Widgets read these (or [AppPalette]) instead of
/// writing color values.
class AppColors {
  AppColors._();

  /// Light page background: soft grey-green, so white cards lift off it
  /// without heavy shadows.
  static const Color lightBackground = Color.fromARGB(255, 238, 241, 237);

  /// Light cards and sheets.
  static const Color lightSurface = Color.fromARGB(255, 255, 255, 255);

  /// Light main text.
  static const Color lightTextPrimary = Color.fromARGB(255, 17, 20, 18);

  /// Light captions and hints.
  static const Color lightTextSecondary = Color.fromARGB(255, 102, 107, 104);

  /// Light brand green: buttons, selection, highlights.
  static const Color lightAccent = Color.fromARGB(255, 37, 74, 35);

  /// Text and icons on [lightAccent].
  static const Color lightOnAccent = Color.fromARGB(255, 255, 255, 255);

  /// Dark page background: near-neutral charcoal.
  static const Color darkBackground = Color.fromARGB(255, 15, 16, 16);

  /// Dark cards and sheets, lighter than the background so they read as
  /// raised.
  static const Color darkSurface = Color.fromARGB(255, 28, 30, 29);

  /// Dark main text.
  static const Color darkTextPrimary = Color.fromARGB(255, 243, 245, 244);

  /// Dark captions and hints.
  static const Color darkTextSecondary = Color.fromARGB(255, 158, 163, 160);

  /// Dark accent: a calm sage, so the brand green does not take over.
  static const Color darkAccent = Color.fromARGB(255, 140, 184, 139);

  /// Text and icons on [darkAccent]. The accent is bright, so it takes
  /// deep green text instead of white.
  static const Color darkOnAccent = Color.fromARGB(255, 13, 25, 14);

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

  /// Cool teal light that plays around the brand green (glows, auroras,
  /// the smart analysis). Never used for text on its own.
  static const Color lightGlow = Color(0xFF1C8C7C);

  /// Dark-theme teal glow.
  static const Color darkGlow = Color(0xFF63D6C6);

  /// Deep green at the lit corner of hero surfaces (balance card).
  static const Color heroStart = Color(0xFF2F6B3C);

  /// Forest green in the body of hero surfaces.
  static const Color heroMiddle = Color(0xFF1B4423);

  /// Teal-black at the far corner of hero surfaces.
  static const Color heroEnd = Color(0xFF0E3A3A);

  /// Text and icons on hero surfaces, in both themes.
  static const Color onHero = Color(0xFFF2F7F1);

  /// Soft light-field colors behind pages (mint, teal, lime), light theme.
  static const List<Color> lightAurora = [
    Color(0xFFB4E2BA),
    Color(0xFF9EDCD3),
    Color(0xFFDDEFBE),
  ];

  /// Light-field colors behind pages, dark theme.
  static const List<Color> darkAurora = [
    Color(0xFF1F6A35),
    Color(0xFF0E6660),
    Color(0xFF3A5A1C),
  ];
}
