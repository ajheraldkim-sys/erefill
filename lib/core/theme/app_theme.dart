import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants.dart';
import 'app_fonts.dart';

class AppTheme {
  // Cached themes to eliminate redundant font loading and ThemeData re-instantiations
  static final ThemeData lightTheme = _buildLightTheme();
  static final ThemeData darkTheme = _buildDarkTheme();
  static final ThemeData outdoorTheme = _buildOutdoorTheme();

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

  static ThemeData _buildLightTheme() => _build(Brightness.light);
  static ThemeData _buildDarkTheme() => _build(Brightness.dark);

  /// Single token-driven builder for the light and dark themes so both
  /// modes always share the same component geometry and states.
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? AppUi.darkPageBg : AppUi.pageBg;
    final surface = dark ? AppUi.darkSurface : AppUi.surface;
    final surfaceRaised =
        dark ? AppUi.darkSurfaceRaised : AppUi.lightSurfaceRaised;
    final textPrimary = dark ? AppUi.darkTextPrimary : AppUi.textPrimary;
    final textSecondary = dark ? AppUi.darkTextSecondary : AppUi.textSecondary;
    final textMuted = dark ? AppUi.darkTextMuted : AppUi.textMuted;
    final border = dark ? AppUi.borderDark : AppUi.borderLight;
    final borderStrong =
        dark ? const Color(0xFF34435C) : AppUi.borderStrongLight;
    final primary = dark ? AppUi.accentCyan : AppUi.bluePrimary;
    final onPrimary = dark ? AppUi.darkPageBg : Colors.white;
    final primarySoft =
        dark ? AppUi.accentCyan.withValues(alpha: 0.16) : AppUi.blueSoft;
    final onPrimarySoft = dark ? AppUi.accentCyan : AppUi.bluePrimaryDark;
    final textTheme = AppFonts.textTheme(brightness);
    // Component styles must carry the brand font family explicitly; a bare
    // TextStyle in a component theme falls back to the platform font.
    final base = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      height: 1.2,
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppUi.radiusControl),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    const buttonMinSize = Size(64, AppUi.buttonHeight);
    final buttonText = base.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    final disabledBg = surfaceRaised;
    final disabledFg = dark ? AppUi.darkTextMuted : AppUi.textDisabled;

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusControl),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Plus Jakarta Sans',
      visualDensity: VisualDensity.standard,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppUi.bluePrimary,
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        surface: surface,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: borderStrong,
        outlineVariant: border,
        error: AppUi.error,
      ).copyWith(
        surfaceContainerHighest: surfaceRaised,
        surfaceContainerHigh: surfaceRaised,
        surfaceContainer: surfaceRaised,
        surfaceContainerLow: surface,
        surfaceContainerLowest: surface,
        primaryContainer: primarySoft,
        onPrimaryContainer: onPrimarySoft,
      ),
      scaffoldBackgroundColor: background,
      canvasColor: background,
      focusColor: primary.withValues(alpha: 0.14),
      hoverColor: primary.withValues(alpha: 0.06),
      iconTheme: IconThemeData(color: textPrimary, size: AppUi.iconLg),
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: textPrimary),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: baseOverlayStyle(dark),
      ),

      textTheme: textTheme,

      // ── Buttons: one height (48), one radius (8), one label style ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          shape: controlShape,
          elevation: 0,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          disabledForegroundColor: disabledFg,
          side: BorderSide(color: borderStrong),
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          disabledForegroundColor: disabledFg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(48, 44),
          shape: controlShape,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppUi.kMinTouchTarget, AppUi.kMinTouchTarget),
          shape: controlShape,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: primarySoft,
          selectedForegroundColor: onPrimarySoft,
          foregroundColor: textSecondary,
          side: BorderSide(color: border),
          shape: controlShape,
          textStyle: base.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Inputs: bordered in both modes so fields never disappear ──
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: surface,
        border: inputBorder(border),
        enabledBorder: inputBorder(border),
        disabledBorder: inputBorder(border.withValues(alpha: 0.6)),
        focusedBorder: inputBorder(primary, 2),
        errorBorder: inputBorder(AppUi.error),
        focusedErrorBorder: inputBorder(AppUi.error, 2),
        hintStyle: base.copyWith(
          color: textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: base.copyWith(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: base.copyWith(
          color: primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: base.copyWith(color: textSecondary, fontSize: 12),
        errorStyle: base.copyWith(
          color: dark ? const Color(0xFFFCA5A5) : AppUi.errorFg,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),

      // ── Navigation ──
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: base.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: base.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primarySoft,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.copyWith(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? primary
                : textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? primary
                : textSecondary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primarySoft,
        selectedIconTheme: IconThemeData(color: primary, size: 22),
        unselectedIconTheme: IconThemeData(color: textSecondary, size: 22),
        selectedLabelTextStyle: base.copyWith(
          color: primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: base.copyWith(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        dividerColor: border,
        labelStyle: base.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: base.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Surfaces ──
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusDialog),
          side: BorderSide(color: border),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: AppUi.radiusSheetTop,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        textStyle: base.copyWith(color: textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusControl),
          side: BorderSide(color: border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: base.copyWith(
          color: dark ? AppUi.textPrimary : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        decoration: BoxDecoration(
          color: dark ? AppUi.darkTextPrimary : AppUi.textPrimary,
          borderRadius: BorderRadius.circular(AppUi.radiusSm),
        ),
      ),

      // ── Selection & feedback ──
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primarySoft,
        secondarySelectedColor: primarySoft,
        disabledColor: surfaceRaised,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: base.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        secondaryLabelStyle: base.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: onPrimarySoft,
        ),
        checkmarkColor: onPrimarySoft,
        brightness: brightness,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusFull),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        subtitleTextStyle: textTheme.bodyMedium,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: AppUi.error,
        textColor: Colors.white,
        textStyle: base.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.transparent,
        ),
        side: BorderSide(color: borderStrong, width: 1.5),
        checkColor: WidgetStatePropertyAll(onPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusXs),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : textSecondary,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onPrimary
              : (dark ? AppUi.darkTextSecondary : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : borderStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusLgValue),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? AppUi.darkSurfaceRaised : AppUi.textPrimary,
        actionTextColor: dark ? AppUi.accentCyan : const Color(0xFF7DD3FC),
        contentTextStyle: base.copyWith(
          color: dark ? AppUi.darkTextPrimary : Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusControl),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceRaised,
      ),
    );
  }

  // High-Contrast Outdoor Theme Builder for Direct Sun Readability
  static ThemeData _buildOutdoorTheme() {
    const background = Colors.white;
    const surface = Colors.white;
    const surfaceSoft = Color(0xFFF1F5F9);
    const textPrimary = Color(0xFF000000);
    const textSecondary = Color(0xFF1E293B);
    const border = Color(0xFF0F172A);
    const primary = Color(0xFF0038A8); // Deep vibrant cobalt with 8.5:1 contrast against pure white

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Plus Jakarta Sans',
      dividerColor: border,
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1.5,
        space: 1.5,
      ),
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        outline: border,
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
        titleTextStyle: AppFonts.outdoorTextTheme().titleLarge,
        iconTheme: const IconThemeData(color: textPrimary),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: baseOverlayStyle(false),
      ),
      textTheme: AppFonts.outdoorTextTheme(),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
            side: const BorderSide(color: border, width: 1.5),
          ),
          elevation: 0,
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: border, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radius),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: primary, width: 2.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: Color(0xFF991B1B), width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusMd),
          borderSide: const BorderSide(color: Color(0xFF991B1B), width: 2.5),
        ),
        hintStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          side: const BorderSide(color: border, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          side: const BorderSide(color: border, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

