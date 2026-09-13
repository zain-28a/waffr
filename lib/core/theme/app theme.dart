import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      primaryColor: AppColors.lightAccent,
      cardColor: AppColors.lightSurface,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightAccent,
        surface: AppColors.lightSurface,
        
      ),
      textTheme: _textTheme(
        primary: AppColors.lightTextPrimary,
        secondary: AppColors.lightTextSecondary,
      ),
      fontFamily: 'scheherazade new',
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      primaryColor: AppColors.darkAccent,
      cardColor: AppColors.darkSurface,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkAccent,
        surface: AppColors.darkSurface,
      ),
      textTheme: _textTheme(
        primary: AppColors.darkTextPrimary,
        secondary: AppColors.darkTextSecondary,
      ),
      fontFamily: 'scheherazade new',
    );
  }

  static TextTheme _textTheme({required Color primary, required Color secondary}) {
    return TextTheme(
      bodyLarge: TextStyle(color: primary),
      bodyMedium: TextStyle(color: primary),
      bodySmall: TextStyle(color: secondary),
      titleLarge: TextStyle(color: primary, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: primary, fontWeight: FontWeight.w600),
    );
  }
}