// Builds Material ThemeData for light and dark modes from AppColors and fonts.

import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

// Central theme: Outfit (mixed-case Latin) with Tajawal fallback for Arabic.
class AppTheme {
  AppTheme._();

  static const String arabic = 'Tajawal';
  static const String english = 'Outfit';
  static const List<String> fallback = [arabic];

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      primaryColor: AppColors.lightAccent,
      cardColor: AppColors.lightSurface,
      fontFamily: english,
      fontFamilyFallback: fallback,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightAccent,
        surface: AppColors.lightSurface,
      ),
      textTheme: _textTheme(
        primary: AppColors.lightTextPrimary,
        secondary: AppColors.lightTextSecondary,
        accent: AppColors.lightAccent,
      ),
      pageTransitionsTheme: _pageTransitions,
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
      fontFamily: english,
      fontFamilyFallback: fallback,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkAccent,
        surface: AppColors.darkSurface,
      ),
      textTheme: _textTheme(
        primary: AppColors.darkTextPrimary,
        secondary: AppColors.darkTextSecondary,
        accent: AppColors.darkAccent,
      ),
      pageTransitionsTheme: _pageTransitions,
      appBarTheme: _appBarTheme(
        background: AppColors.darkSurface,
        foreground: AppColors.darkTextPrimary,
      ),
    );
  }

  static const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
      TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
      TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      TargetPlatform.linux: ZoomPageTransitionsBuilder(),
    },
  );

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
        fontFamily: english,
        fontFamilyFallback: fallback,
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
        fontFamily: english,
        fontFamilyFallback: fallback,
        fontSize: 40,
        fontWeight: FontWeight.bold,
        
        color: accent,
      ),
      displayMedium: TextStyle(
        fontFamily: english,
        fontFamilyFallback: fallback,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1,
        color: accent,
      ),
      headlineSmall: TextStyle(
        fontFamily: english,
        fontFamilyFallback: fallback,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontFamily: english,
        fontFamilyFallback: fallback,
        color: primary,
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(
        fontFamily: english,
        fontFamilyFallback: fallback,
        color: primary,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        fontFamily: english,
        fontFamilyFallback: fallback,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontFamily: english,
        fontFamilyFallback: fallback,
        color: primary,
      ),
      bodySmall: TextStyle(
        fontFamily: english,
        fontFamilyFallback: fallback,
        color: secondary,
      ),
    );
  }
}
