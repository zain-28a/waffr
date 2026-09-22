import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

class AppTheme {
  AppTheme._();

  static const String cairo = 'Tajawal';
  static const String merriweather = 'bebas neue';

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      primaryColor: AppColors.lightAccent,
      cardColor: AppColors.lightSurface,
      fontFamily: cairo,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightAccent,
        surface: AppColors.lightSurface,
      ),
      textTheme: _textTheme(
        primary: AppColors.lightTextPrimary,
        secondary: AppColors.lightTextSecondary,
        accent: AppColors.lightAccent,
      ),
      appBarTheme: _appBarTheme(
        background: AppColors.lightSurface,
        foreground: AppColors.lightTextPrimary,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      primaryColor: AppColors.darkAccent,
      cardColor: AppColors.darkSurface,
      fontFamily: cairo,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkAccent,
        surface: AppColors.darkSurface,
      ),
      textTheme: _textTheme(
        primary: AppColors.darkTextPrimary,
        secondary: AppColors.darkTextSecondary,
        accent: AppColors.darkAccent,
      ),
      appBarTheme: _appBarTheme(
        background: AppColors.darkSurface,
        foreground: AppColors.darkTextPrimary,
      ),
    );
  }

  static AppBarTheme _appBarTheme({
    required Color background,
    required Color foreground,
  }) {
    return AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      centerTitle: true,
      foregroundColor: foreground,
      titleTextStyle: TextStyle(
        fontFamily: cairo,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: foreground,
      ),
      iconTheme: IconThemeData(color: foreground),
    );
  }

  static TextTheme _textTheme({
    required Color primary,
    required Color secondary,
    required Color accent,
  }) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: merriweather,
        fontSize: 40,
        fontWeight: FontWeight.bold,
        fontStyle: FontStyle.italic,
        color: accent,
      ),
      displayMedium: TextStyle(
        fontFamily: merriweather,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
        height: 1,
        color: accent,
      ),
      headlineSmall: TextStyle(
        fontFamily: cairo,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontFamily: cairo,
        color: primary,
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(
        fontFamily: cairo,
        color: primary,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(fontFamily: cairo, color: primary),
      bodyMedium: TextStyle(fontFamily: cairo, color: primary),
      bodySmall: TextStyle(fontFamily: cairo, color: secondary),
    );
  }
}
