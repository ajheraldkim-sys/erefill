import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants.dart';
import 'app_fonts.dart';

class AppTheme {
  // Cached themes to eliminate redundant font loading and ThemeData re-instantiations
  static final ThemeData lightTheme = _buildLightTheme();
  static final ThemeData darkTheme = _buildDarkTheme();

  /// Returns the appropriate SystemUiOverlayStyle for the current theme context.
  static SystemUiOverlayStyle systemUiOverlayStyle(
    BuildContext context, {
    bool isHero = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return baseOverlayStyle(isDark, isHero: isHero);
  }

  /// Base SystemUiOverlayStyle for light or dark mode.
  static SystemUiOverlayStyle baseOverlayStyle(
    bool isDark, {
    bool isHero = false,
  }) {
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isHero
          ? (isDark ? Brightness.light : Brightness.dark)
          : (isDark ? Brightness.light : Brightness.dark),
      statusBarBrightness: isHero
          ? (isDark ? Brightness.dark : Brightness.light)
          : (isDark ? Brightness.dark : Brightness.light),
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
  }

  // Light Theme Builder
  static ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppUi.bluePrimary,
        brightness: Brightness.light,
        primary: AppUi.bluePrimary,
      ).copyWith(surfaceContainerHighest: AppUi.lightSurfaceRaised),
      scaffoldBackgroundColor: AppUi.pageBg,
      fontFamily: 'Plus Jakarta Sans',
      iconTheme: const IconThemeData(color: AppUi.textPrimary),
      dividerColor: AppUi.borderLight,
      dividerTheme: const DividerThemeData(
        color: AppUi.borderLight,
        thickness: 1,
        space: 1,
      ),

      // AppBar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: AppUi.pageBg,
        foregroundColor: AppUi.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        titleTextStyle: AppFonts.textTheme(Brightness.light).titleLarge,
        iconTheme: const IconThemeData(color: AppUi.textPrimary),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: baseOverlayStyle(false),
      ),

      // Text Themes
      textTheme: AppFonts.textTheme(Brightness.light),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppUi.bluePrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
          ),
          elevation: 0,
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppUi.bluePrimary,
          side: const BorderSide(color: AppUi.bluePrimary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radius),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppUi.bluePrimary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        filled: true,
        fillColor: AppUi.lightSurfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: AppUi.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: AppUi.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: AppUi.bluePrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: AppUi.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: AppUi.error, width: 2),
        ),
        hintStyle: const TextStyle(
          color: AppUi.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: AppUi.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        errorStyle: const TextStyle(color: AppUi.error, fontSize: 12),
      ),

      // Bottom Navigation Bar Theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppUi.surface,
        selectedItemColor: AppUi.bluePrimary,
        unselectedItemColor: AppUi.navUnselected,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: AppUi.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          side: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: AppUi.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          side: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
        ),
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: AppUi.blueSoft,
        selectedColor: AppUi.bluePrimary,
        secondarySelectedColor: AppUi.bluePrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppUi.textPrimary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        brightness: Brightness.light,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppUi.textSecondary,
        textColor: AppUi.textPrimary,
        subtitleTextStyle: AppFonts.textTheme(Brightness.light).bodyMedium,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppUi.bluePrimary,
        unselectedLabelColor: AppUi.textSecondary,
        indicatorColor: AppUi.bluePrimary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppUi.surface,
        modalBackgroundColor: AppUi.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppUi.surface,
        textStyle: TextStyle(color: AppUi.textPrimary),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppUi.bluePrimary
              : AppUi.lightSurfaceRaised,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppUi.bluePrimary
              : AppUi.textSecondary,
        ),
      ),

      // Floating Action Button Theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppUi.bluePrimary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusLgValue),
        ),
      ),

      // Snackbar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppUi.textPrimary,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      // Progress Indicator Theme
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppUi.bluePrimary,
      ),
    );
  }

  // Dark Theme Builder
  static ThemeData _buildDarkTheme() {
    const background = AppUi.darkPageBg;
    const surface = AppUi.darkSurface;
    const surfaceSoft = AppUi.darkSurfaceRaised;
    const textPrimary = Color(0xFFE8F0F2);
    const textSecondary = Color(0xFFA0B2B7);
    const border = Color(0xFF29383D);
    const primary = AppUi.accentCyan;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Plus Jakarta Sans',
      dividerColor: border,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppUi.bluePrimary,
        brightness: Brightness.dark,
        primary: primary,
        surface: surface,
      ).copyWith(surfaceContainerHighest: surfaceSoft),
      scaffoldBackgroundColor: background,
      iconTheme: const IconThemeData(color: textPrimary),

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        titleTextStyle: AppFonts.textTheme(Brightness.dark).titleLarge,
        iconTheme: const IconThemeData(color: textPrimary),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: baseOverlayStyle(true),
      ),

      textTheme: AppFonts.textTheme(Brightness.dark),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: background,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
          ),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radius),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        filled: true,
        fillColor: surfaceSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: AppUi.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: AppUi.error, width: 2),
        ),
        hintStyle: const TextStyle(
          color: AppUi.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        errorStyle: const TextStyle(color: AppUi.error, fontSize: 12),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          side: const BorderSide(color: Color(0xFF27272A), width: 1),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          side: const BorderSide(color: Color(0xFF27272A), width: 1),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceSoft,
        selectedColor: primary,
        secondarySelectedColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: background,
        ),
        brightness: Brightness.dark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        subtitleTextStyle: AppFonts.textTheme(Brightness.dark).bodyMedium,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: surface,
        textStyle: TextStyle(color: textPrimary),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : surfaceSoft,
        ),
        checkColor: const WidgetStatePropertyAll(background),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : textSecondary,
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: background,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusLgValue),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceSoft,
        contentTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? primary : border;
        }),
      ),
    );
  }
}
