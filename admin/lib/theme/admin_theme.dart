import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Desktop admin theme — extends the mobile eRefill design system.
class AdminTheme {
  static ThemeData get light => _build(AppTheme.lightTheme, Brightness.light);
  static ThemeData get dark => _build(AppTheme.darkTheme, Brightness.dark);

  static ThemeData _build(ThemeData base, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? AppUi.darkSurface : AppUi.surface;
    final border = dark ? AppUi.borderDark : AppUi.borderLight;
    final text = dark ? AppUi.darkTextPrimary : AppUi.textPrimary;
    final mutedSurface = dark ? AppUi.darkSurfaceRaised : AppUi.blueSoft;
    final primary = dark ? AppUi.accentCyan : AppUi.bluePrimary;
    final onPrimary = dark ? AppUi.darkPageBg : Colors.white;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppUi.radiusControl),
    );
    final filledButtonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? mutedSurface : primary,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? (dark ? AppUi.navUnselected : AppUi.textSecondary)
            : onPrimary,
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      overlayColor: WidgetStatePropertyAll(
        onPrimary.withValues(alpha: dark ? 0.12 : 0.16),
      ),
      shape: WidgetStatePropertyAll(buttonShape),
    );
    final outlineTint = primary.withValues(alpha: dark ? 0.12 : 0.07);
    final outlineBorder = primary.withValues(alpha: dark ? 0.72 : 0.55);
    final buttonOverlay = primary.withValues(alpha: dark ? 0.16 : 0.12);

    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: dark ? AppUi.darkPageBg : AppUi.pageBg,
      colorScheme: base.colorScheme.copyWith(
        brightness: brightness,
        primary: primary,
        surface: surface,
        surfaceContainerHighest: mutedSurface,
        outline: border,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      dividerColor: border,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: dark ? AppUi.darkPageBg : AppUi.pageBg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: filledButtonStyle),
      filledButtonTheme: FilledButtonThemeData(style: filledButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? (dark ? AppUi.navUnselected : AppUi.textSecondary)
                : primary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? Colors.transparent
                : outlineTint,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? border
                  : outlineBorder,
            ),
          ),
          overlayColor: WidgetStatePropertyAll(buttonOverlay),
          shape: WidgetStatePropertyAll(buttonShape),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? (dark ? AppUi.navUnselected : AppUi.textSecondary)
                : primary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? Colors.transparent
                : primary.withValues(alpha: dark ? 0.08 : 0.05),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          overlayColor: WidgetStatePropertyAll(buttonOverlay),
          shape: WidgetStatePropertyAll(buttonShape),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? (dark ? AppUi.navUnselected : AppUi.textSecondary)
                : primary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? Colors.transparent
                : outlineTint,
          ),
          overlayColor: WidgetStatePropertyAll(buttonOverlay),
          side: WidgetStatePropertyAll(
            BorderSide(color: primary.withValues(alpha: dark ? 0.3 : 0.2)),
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppUi.deepBlue,
        indicatorColor: AppUi.bluePrimary,
        selectedIconTheme: IconThemeData(color: Colors.white),
        unselectedIconTheme: IconThemeData(color: Colors.white54),
        selectedLabelTextStyle: TextStyle(color: Colors.white),
        unselectedLabelTextStyle: TextStyle(color: Colors.white54),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(mutedSurface),
        dataRowMinHeight: 48,
        headingRowHeight: 44,
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: text,
          fontSize: 13,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: dark ? AppUi.darkTextSecondary : AppUi.textSecondary,
        textColor: text,
        selectedColor: primary,
        selectedTileColor: primary.withValues(alpha: dark ? 0.12 : 0.08),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : (dark ? AppUi.navUnselected : AppUi.textSecondary),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.35)
              : mutedSurface,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(onPrimary),
        side: BorderSide(color: dark ? AppUi.navUnselected : border),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(primary)),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: mutedSurface,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.16),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        textStyle: TextStyle(color: text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusControl),
          side: BorderSide(color: border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: mutedSurface,
        contentTextStyle: TextStyle(color: text),
        actionTextColor: primary,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppUi.cardRadius,
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(backgroundColor: surface),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: primary,
        unselectedLabelColor: dark
            ? AppUi.darkTextSecondary
            : AppUi.textSecondary,
        indicatorColor: primary,
      ),
    );
  }
}
