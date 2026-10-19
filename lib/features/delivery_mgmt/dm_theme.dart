// Shared design tokens & helpers for the Delivery Management module
import 'package:flutter/material.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';

class DmColors {
  static const bg = AppUi.pageBg;
  static const surface = AppUi.surface;
  static const border = AppUi.borderColor;
  static const borderFocus = AppColors.brandPrimary;

  static const primary = AppColors.brandPrimary;
  static const primarySoft = AppColors.brandSoft;

  static const green = AppColors.statusCompleted;
  static const greenSoft = AppColors.uiSuccessBg;

  static const red = AppColors.statusCancelled;
  static const redSoft = AppColors.uiErrorBg;

  static const amber = AppColors.statusPending;
  static const amberSoft = AppColors.uiWarningBg;

  static const purple = AppColors.statusPreparing;
  static const purpleSoft = Color(0xFFF5F3FF);

  static const sky = AppColors.accentCyan;
  static const skySoft = AppColors.brandPale;

  static const textPrimary = AppUi.textPrimary;
  static const textSecondary = AppUi.textSecondary;
  static const textMuted = AppUi.textMuted;
  static const textDisabled = AppUi.textDisabled;

  static Color surfaceOf(BuildContext context) => AppUi.surfaceOf(context);
  static Color bgOf(BuildContext context) => AppUi.pageBgOf(context);
  static Color borderOf(BuildContext context) => AppUi.borderOf(context);
  static Color textPrimaryOf(BuildContext context) => AppUi.textPrimaryOf(context);
  static Color textSecondaryOf(BuildContext context) => AppUi.textSecondaryOf(context);
}

class DmText {
  static TextStyle h1Of(BuildContext context) => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: DmColors.textPrimaryOf(context),
    letterSpacing: 0,
  );
  static TextStyle h2Of(BuildContext context) => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: DmColors.textPrimaryOf(context),
    letterSpacing: 0,
  );
  static TextStyle h3Of(BuildContext context) => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: DmColors.textPrimaryOf(context),
  );
  static TextStyle bodyOf(BuildContext context) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: DmColors.textSecondaryOf(context),
  );
  static TextStyle labelOf(BuildContext context) => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: DmColors.textMuted,
  );
  static TextStyle captionOf(BuildContext context) => const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: DmColors.textMuted,
  );

  static const h1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: DmColors.textPrimary,
    letterSpacing: 0,
  );
  static const h2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: DmColors.textPrimary,
    letterSpacing: 0,
  );
  static const h3 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: DmColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: DmColors.textSecondary,
  );
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: DmColors.textMuted,
  );
  static const caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: DmColors.textMuted,
  );
}

class DmUi {
  /// Theme-aware card decoration.
  static BoxDecoration cardOf(BuildContext context, {Color? border}) =>
      BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.radiusLg,
        border: border != null ? Border.all(color: border) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      );

  /// Bottom sheet surface decoration.
  static BoxDecoration sheetDecorationOf(BuildContext context) => BoxDecoration(
    color: AppUi.surfaceOf(context),
    borderRadius: AppUi.radiusSheetTop,
  );

  /// Drag handle for modal sheets.
  static Widget sheetHandle(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppUi.dividerOf(context),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  /// Filter / date chip decoration.
  static BoxDecoration filterChipDecoration(
    BuildContext context, {
    required bool selected,
  }) => BoxDecoration(
    color: selected ? AppUi.bluePrimary : AppUi.chipBgOf(context),
    borderRadius: AppUi.radiusLg,
    border: selected ? Border.all(color: AppUi.bluePrimary) : null,
  );

  static Color filterChipTextColor(
    BuildContext context, {
    required bool selected,
  }) => selected ? Colors.white : AppUi.textSecondaryOf(context);

  /// Tappable field surface (date pickers, dropdowns).
  static BoxDecoration fieldSurfaceOf(BuildContext context) => BoxDecoration(
    color: AppUi.pageBgOf(context),
    borderRadius: AppUi.controlRadius,
  );

  /// List/card surface in DM lists.
  static BoxDecoration listCardOf(BuildContext context) => BoxDecoration(
    color: AppUi.surfaceOf(context),
    borderRadius: AppUi.radiusLg,
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );

  /// Standard card decoration
  static BoxDecoration card({Color? border}) => BoxDecoration(
    color: DmColors.surface,
    borderRadius: AppUi.radiusLg,
    border: Border.all(color: border ?? DmColors.border),
    boxShadow: const [
      BoxShadow(color: Color(0x05000000), blurRadius: 12, offset: Offset(0, 3)),
    ],
  );

  /// Theme-aware input field decoration.
  static InputDecoration inputDecorationOf(
    BuildContext context,
    String hint, {
    Widget? prefixIcon,
    Widget? suffix,
    String? suffixText,
    String? prefixText,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: DmText.body.copyWith(color: DmColors.textDisabled),
    prefixIcon: prefixIcon,
    suffix: suffix,
    suffixText: suffixText,
    prefixText: prefixText,
    filled: true,
    fillColor: AppUi.pageBgOf(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppUi.radiusMd),
      borderSide: BorderSide(color: AppUi.borderOf(context)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppUi.radiusMd),
      borderSide: BorderSide(color: AppUi.borderOf(context)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppUi.radiusMd),
      borderSide: const BorderSide(color: DmColors.borderFocus, width: 2),
    ),
  );

  /// Input field decoration
  static InputDecoration inputDecoration(
    String hint, {
    Widget? prefixIcon,
    Widget? suffix,
    String? suffixText,
    String? prefixText,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: DmText.body.copyWith(color: DmColors.textDisabled),
    prefixIcon: prefixIcon,
    suffix: suffix,
    suffixText: suffixText,
    prefixText: prefixText,
    filled: true,
    fillColor: DmColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppUi.radiusMd),
      borderSide: const BorderSide(color: DmColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppUi.radiusMd),
      borderSide: const BorderSide(color: DmColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppUi.radiusMd),
      borderSide: const BorderSide(color: DmColors.borderFocus, width: 2),
    ),
  );

  /// Colored micro-chip
  static Widget chip(String label, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppUi.radiusControl),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );

  /// Section label above form fields
  static Widget fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: DmText.body.copyWith(
        fontWeight: FontWeight.w700,
        color: DmColors.textPrimary,
      ),
    ),
  );

  /// Primary action button
  static Widget primaryButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
    Color color = DmColors.primary,
    IconData? icon,
  }) => SizedBox(
    width: double.infinity,
    height: 54,
    child: ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppUi.radiusLg),
      ),
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    ),
  );

  /// Avatar circle with colored initial
  static Color avatarColor(String name) {
    final colors = [
      AppColors.brandPrimary,
      AppColors.statusPreparing,
      AppColors.statusCompleted,
      AppColors.statusPending,
      AppColors.statusCancelled,
      AppColors.accentCyan,
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  static Widget avatar(String name, {double size = 44}) {
    final color = avatarColor(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  /// Peso formatter
  static String peso(double v) =>
      '₱${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  /// Date string short
  static String dateShort(DateTime d) {
    const ms = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${ms[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Empty state widget
  static Widget emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: DmColors.border,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 44, color: DmColors.textDisabled),
        ),
        const SizedBox(height: 20),
        Text(title, style: DmText.h3),
        const SizedBox(height: 6),
        Text(subtitle, style: DmText.body, textAlign: TextAlign.center),
      ],
    ),
  );

  /// Loading section
  static Widget loadingSection() => const SkeletonList(itemCount: 5);
}
