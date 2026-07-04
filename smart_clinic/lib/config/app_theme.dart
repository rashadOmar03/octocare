import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF00A8B5);
  static const Color accentColor = Color(0xFF00838F);
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color successColor = Color(0xFF388E3C);
  static const Color warningColor = Color(0xFFF57C00);

  static ThemeData get lightTheme {
    final textTheme = GoogleFonts.robotoTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: accentColor,
        error: errorColor,
        surface: Colors.white,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFF212121),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor),
        ),
        labelStyle: const TextStyle(color: Color(0xFF757575)),
        prefixIconColor: const Color(0xFF757575),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF9E9E9E),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE0F7FA),
        selectedColor: primaryColor,
        labelStyle: const TextStyle(color: Color(0xFF212121)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE0E0E0),
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
      ),
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF212121)),
        headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF212121)),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF212121)),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF424242)),
        bodyLarge: textTheme.bodyLarge?.copyWith(color: const Color(0xFF424242)),
        bodyMedium: textTheme.bodyMedium?.copyWith(color: const Color(0xFF616161)),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  static ThemeData get darkTheme {
    final textTheme = GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF4DD0E1),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4DD0E1),
        secondary: Color(0xFF26C6DA),
        error: Color(0xFFEF5350),
        surface: Color(0xFF1E1E1E),
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: Color(0xFFE0E0E0),
        onError: Colors.black,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        color: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4DD0E1),
          foregroundColor: Colors.black,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF4DD0E1),
          side: const BorderSide(color: Color(0xFF4DD0E1)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF4DD0E1),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2C2C2C),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF424242)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF424242)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4DD0E1), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFEF5350)),
        ),
        labelStyle: const TextStyle(color: Color(0xFFBDBDBD)),
        prefixIconColor: const Color(0xFFBDBDBD),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        selectedItemColor: const Color(0xFF4DD0E1),
        unselectedItemColor: Color(0xFF757575),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF4DD0E1),
        foregroundColor: Colors.black,
        elevation: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1A3A40),
        selectedColor: const Color(0xFF4DD0E1),
        labelStyle: const TextStyle(color: Color(0xFFE0E0E0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF424242),
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: const Color(0xFF4DD0E1),
        unselectedLabelColor: const Color(0xFF9E9E9E),
        indicatorColor: Color(0xFF4DD0E1),
      ),
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFFE0E0E0)),
        headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFFE0E0E0)),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFFE0E0E0)),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFFBDBDBD)),
        bodyLarge: textTheme.bodyLarge?.copyWith(color: const Color(0xFFBDBDBD)),
        bodyMedium: textTheme.bodyMedium?.copyWith(color: const Color(0xFF9E9E9E)),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
