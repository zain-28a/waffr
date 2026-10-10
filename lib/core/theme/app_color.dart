// Design-token colors for light and dark UI. Values are the source of truth.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color lightBackground   = Color.fromARGB(255, 255, 254, 253); 
  static const Color lightSurface      = Color.fromARGB(255, 248, 247, 246); 
  static const Color lightTextPrimary  = Color.fromARGB(255, 0, 0, 0);
  static const Color lightTextSecondary= Color.fromARGB(255, 111, 111, 111);
  static const Color lightAccent       = Color.fromARGB(255, 37, 74, 35);
  static const Color lightOnAccent     = Color.fromARGB(255, 255, 255, 255);

  // Dark keeps a hint of the brand green. Cards sit lighter than the
  // background so they read as raised, like the light theme's cards.
  static const Color darkBackground    = Color.fromARGB(255, 15, 19, 17);
  static const Color darkSurface       = Color.fromARGB(255, 26, 32, 28);
  static const Color darkTextPrimary   = Color.fromARGB(255, 255, 255, 255);
  static const Color darkTextSecondary = Color.fromARGB(255, 155, 165, 158);
  static const Color darkAccent        = Color.fromARGB(255, 123, 193, 122);
  // Text and icons drawn on an accent fill. The dark accent is bright, so
  // it takes deep green text instead of white.
  static const Color darkOnAccent      = Color.fromARGB(255, 12, 26, 13);

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
