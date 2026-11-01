// Centralized Application Theme & Palette Architecture
// Restrained Automotive Design System

import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFF7F7F2); // Warm White main background
  static const Color card = Color(0xFFFFFFFF); // Pure White cards, forms, dialogs
  static const Color cardBackground = Color(0xFFFFFFFF); // Pure White cards, forms, dialogs alias
  static const Color navy = Color(0xFF172B3A); // Deep Navy headers, nav, primary text
  static const Color primary = Color(0xFFB94724); // Burnt Orange primary actions
  static const Color primaryHover = Color(0xFF9E3C1E);
  static const Color secondaryText = Color(0xFF5D6873); // Slate Grey secondary text
  static const Color border = Color(0xFFDDE2E5); // Light Grey borders & dividers
  static const Color success = Color(0xFF24734D); // Dark Green approved, verified
  static const Color warning = Color(0xFF946200); // Amber pending, under review
  static const Color amber = Color(0xFF946200); // Amber alias
  static const Color danger = Color(0xFFB42318); // Dark Red errors, rejected
  static const Color disabled = Color(0xFF94A3B8);
  static const Color disabledBackground = Color(0xFFE2E8F0);
}

class AppTheme {
  static ThemeData get theme {
    const fontFamily = 'Inter';

    const textTheme = TextTheme(
      displayLarge: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 32),
      displayMedium: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 28),
      displaySmall: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 24),
      headlineMedium: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 20),
      headlineSmall: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 18),
      titleLarge: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 20),
      titleMedium: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 16),
      titleSmall: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 14),
      bodyLarge: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.normal, fontSize: 16),
      bodyMedium: TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontWeight: FontWeight.normal, fontSize: 14),
      bodySmall: TextStyle(fontFamily: fontFamily, color: AppColors.secondaryText, fontWeight: FontWeight.normal, fontSize: 12),
      labelLarge: TextStyle(fontFamily: fontFamily, color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
      labelMedium: TextStyle(fontFamily: fontFamily, color: AppColors.secondaryText, fontWeight: FontWeight.w500, fontSize: 12),
      labelSmall: TextStyle(fontFamily: fontFamily, color: AppColors.secondaryText, fontWeight: FontWeight.w500, fontSize: 10),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      disabledColor: AppColors.disabled,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.navy,
        surface: AppColors.card,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.navy,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.disabledBackground,
          disabledForegroundColor: AppColors.disabled,
          elevation: 0,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          disabledForegroundColor: AppColors.disabled,
          elevation: 0,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: AppColors.border, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.disabled,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        labelStyle: const TextStyle(fontFamily: fontFamily, color: AppColors.secondaryText, fontSize: 14),
        hintStyle: const TextStyle(fontFamily: fontFamily, color: AppColors.disabled, fontSize: 14),
        errorStyle: const TextStyle(fontFamily: fontFamily, color: AppColors.danger, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.navy,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.navy,
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        modalBackgroundColor: AppColors.card,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.secondaryText,
        selectedLabelStyle: TextStyle(fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontFamily: fontFamily, fontSize: 12),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.card,
        elevation: 4,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.secondaryText,
        indicatorColor: AppColors.primary,
        labelStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.normal, fontSize: 13),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.border,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.white;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.background,
        selectedColor: AppColors.primary,
        disabledColor: AppColors.disabledBackground,
        labelStyle: const TextStyle(fontFamily: fontFamily, color: AppColors.navy, fontSize: 13),
        secondaryLabelStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
    );
  }
}


