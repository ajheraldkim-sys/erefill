import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants.dart';

/// Plus Jakarta Sans typography for eRefill.
class AppFonts {
  static const List<String> fontFallbacks = [
    'Roboto',
    'Noto Sans',
    'Segoe UI Emoji',
    'Apple Color Emoji',
    'sans-serif',
  ];

  static TextTheme textTheme(Brightness brightness) {
    final base = GoogleFonts.plusJakartaSansTextTheme().apply(
      fontFamilyFallback: fontFallbacks,
    );
    final primary = brightness == Brightness.dark
        ? const Color(0xFFE8F0F2)
        : AppUi.textPrimary;
    final secondary = brightness == Brightness.dark
        ? const Color(0xFFA0B2B7)
        : AppUi.textSecondary;

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: secondary,
        height: 1.45,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: secondary,
        letterSpacing: 0.3,
      ),
    );
  }
}
