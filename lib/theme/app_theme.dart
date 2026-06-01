import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Light palette ──────────────────────────────────────────────────────────
  static const _lLabel      = Color(0xFF1C1C1E);
  static const _lSecondary  = Color(0xFF8E8E93);
  static const _lSurface    = Colors.white;
  static const _lSeparator  = Color(0xFFD1D1D6);

  // ── Dark palette ───────────────────────────────────────────────────────────
  static const _dLabel      = Color(0xFFFFFFFF);
  static const _dSecondary  = Color(0xFF8E8E93);
  static const _dSurface    = Color(0xFF161618);
  static const _dSeparator  = Color(0xFF2E2E30);

  static TextTheme _buildTextTheme(ThemeData base, Color label, Color secondary) =>
      GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge:   GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: label),
        headlineLarge:  GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: label),
        headlineMedium: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: label),
        headlineSmall:  GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: label),
        titleLarge:     GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: label),
        titleMedium:    GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: label),
        titleSmall:     GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: label),
        bodyLarge:      GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: label),
        bodyMedium:     GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400, color: secondary),
        bodySmall:      GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: secondary),
        labelLarge:     GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: label),
        labelMedium:    GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: secondary),
        labelSmall:     GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: secondary),
      );

  static ThemeData light([Color primary = const Color(0xFF007AFF)]) {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        onPrimary: Colors.white,
        surface: _lSurface,
        onSurface: _lLabel,
        onSurfaceVariant: _lSecondary,
        outline: _lSeparator,
      ),
      textTheme: _buildTextTheme(base, _lLabel, _lSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: _lLabel),
        iconTheme: const IconThemeData(color: _lLabel),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        labelStyle: GoogleFonts.inter(fontSize: 15, color: _lSecondary),
        hintStyle: GoogleFonts.inter(fontSize: 15, color: _lSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      dividerTheme: const DividerThemeData(color: _lSeparator, thickness: 0.8),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _lLabel,
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white),
      ),
    );
  }

  static ThemeData dark([Color primary = const Color(0xFF0A84FF)]) {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F0F11),
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        onPrimary: Colors.white,
        surface: _dSurface,
        onSurface: _dLabel,
        onSurfaceVariant: _dSecondary,
        outline: _dSeparator,
      ),
      textTheme: _buildTextTheme(base, _dLabel, _dSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: _dLabel),
        iconTheme: const IconThemeData(color: _dLabel),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        labelStyle: GoogleFonts.inter(fontSize: 15, color: _dSecondary),
        hintStyle: GoogleFonts.inter(fontSize: 15, color: _dSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      dividerTheme: const DividerThemeData(color: _dSeparator, thickness: 0.8),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2C2C2E),
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white),
      ),
    );
  }
}
