// Design-token colors for light and dark UI. Values are the source of truth.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color lightBackground   = Color.fromARGB(255, 255, 254, 253); 
  static const Color lightSurface      = Color.fromARGB(255, 248, 247, 246); 
  static const Color lightTextPrimary  = Color.fromARGB(255, 0, 0, 0);
  static const Color lightTextSecondary= Color.fromARGB(255, 111, 111, 111);
  static const Color lightAccent       = Color.fromARGB(255, 37, 74, 35);

  static const Color darkBackground    = Color.fromARGB(255, 20, 20, 20); 
  static const Color darkSurface       = Color.fromARGB(255, 15, 15, 15);
  static const Color darkTextPrimary   = Color.fromARGB(255, 255, 255, 255); 
  static const Color darkTextSecondary = Color.fromARGB(255, 131, 131, 131);
  static const Color darkAccent        = Color.fromARGB(255, 91, 136, 88);

  // Delete / remove / errors. One red for every destructive control.
  static const Color lightDestructive  = Color(0xFF8E3B3B);
  static const Color darkDestructive   = Color(0xFFE38B8B);

  // Needs attention (low balance, charge waiting for approval).
  static const Color lightWarning      = Color(0xFF8A6A24);
  static const Color darkWarning       = Color(0xFFE2C27A);

  static Color warningOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkWarning
          : lightWarning;

  static Color destructiveOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkDestructive
          : lightDestructive;
}
