// Design-token colors for light and dark UI. Values are the source of truth.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Light: soft grey-green page with white cards, so cards lift off the
  // page without heavy shadows.
  static const Color lightBackground   = Color.fromARGB(255, 238, 241, 237);
  static const Color lightSurface      = Color.fromARGB(255, 255, 255, 255);
  static const Color lightTextPrimary  = Color.fromARGB(255, 17, 20, 18);
  static const Color lightTextSecondary= Color.fromARGB(255, 102, 107, 104);
  static const Color lightAccent       = Color.fromARGB(255, 37, 74, 35);
  static const Color lightOnAccent     = Color.fromARGB(255, 255, 255, 255);

  // Dark is a near-neutral charcoal; the brand green is kept for the accent
  // only, and that accent is a calm sage so it does not take over the
  // screen. Cards sit lighter than the background so they read as raised.
  static const Color darkBackground    = Color.fromARGB(255, 15, 16, 16);
  static const Color darkSurface       = Color.fromARGB(255, 28, 30, 29);
  static const Color darkTextPrimary   = Color.fromARGB(255, 243, 245, 244);
  static const Color darkTextSecondary = Color.fromARGB(255, 158, 163, 160);
  static const Color darkAccent        = Color.fromARGB(255, 140, 184, 139);
  // Text and icons drawn on an accent fill. The dark accent is bright, so
  // it takes deep green text instead of white.
  static const Color darkOnAccent      = Color.fromARGB(255, 13, 25, 14);

  // Delete / remove / errors. One red for every destructive control.
  static const Color lightDestructive  = Color(0xFF8E3B3B);
  static const Color darkDestructive   = Color(0xFFE38B8B);

  // Needs attention (low balance, charge waiting for approval).
  static const Color lightWarning      = Color(0xFF8A6A24);
  static const Color darkWarning       = Color(0xFFE2C27A);

  static Color onAccentOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkOnAccent
          : lightOnAccent;

  static Color warningOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkWarning
          : lightWarning;

  static Color destructiveOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkDestructive
          : lightDestructive;
}
