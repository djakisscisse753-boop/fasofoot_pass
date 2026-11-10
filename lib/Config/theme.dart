import 'package:flutter/material.dart';

/// Palette commune de FasoFoot Pass, inspirée des couleurs nationales.
class AppColors {
  AppColors._();

  static const green = Color(0xFF008751);
  static const greenDark = Color(0xFF005A36);
  static const yellow = Color(0xFFFCD116);
  static const red = Color(0xFFDA121A);
  static const background = Color(0xFF101820);
  static const backgroundDeep = Color(0xFF0B151D);
  static const surface = Color(0xFF1A2634);
  static const surfaceRaised = Color(0xFF223142);
  static const textMuted = Color(0xFF9AA8B5);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.green,
      brightness: Brightness.dark,
      primary: AppColors.green,
      secondary: AppColors.yellow,
      tertiary: AppColors.red,
      surface: AppColors.surface,
      onSurface: Colors.white,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.green.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.yellow,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        side: const BorderSide(color: AppColors.yellow, width: 1.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.yellow,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.045),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      hintStyle: const TextStyle(color: AppColors.textMuted),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.yellow, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red, width: 1.4),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.yellow,
      unselectedItemColor: AppColors.textMuted,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceRaised,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.yellow,
      linearTrackColor: AppColors.surfaceRaised,
    ),
    dividerColor: Colors.white12,
  );
}
