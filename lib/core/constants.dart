// lib/core/constants.dart
import 'package:flutter/material.dart';

/// Legacy tones kept for the account setup flow, which intentionally retains
/// its existing onboarding look.
class OnboardingPalette {
  static const Color bluePrimary = Color(0xFF2563EB);
  static const Color blueSoft = Color(0xFFEFF6FF);
  static const Color bluePale = Color(0xFFF0F9FF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF7B8493);
  static const Color textMuted = Color(0xFFA4ADBB);
}

class AppConstants {
  static const String supabaseUrl = 'https://ormmjxtbwosnraijphra.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9ybW1qeHRid29zbnJhaWpwaHJhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTgxOTQsImV4cCI6MjA4OTM5NDE5NH0.s_A7c1BEFyKRLnq8Fzw_YRCOmyQLm7uPqN7vzKxLGzo';
  static const String paymongoPublicKey = 'pk_test_1zYhxAz8T8ceWW9wXeLM9cMb';

  static const List<String> defaultPuroks = [
    'Purok 1',
    'Purok 2',
    'Purok 3',
    'Purok 4',
    'Purok 5',
    'Purok 6',
    'Purok 7',
  ];

  static const Map<String, String> municipalityZipCodes = {
    'Cantilan': '8317',
    'Madrid': '8316',
  };

  /// Initial map positions for the municipalities supported by eRefill.
  /// They are starting points only; customers must still place the pin at
  /// their precise delivery location.
  static const Map<String, ({double latitude, double longitude})>
  municipalityCenters = {
    'Cantilan': (latitude: 9.3517, longitude: 125.9784),
    'Madrid': (latitude: 9.2745, longitude: 125.9643),
  };

  static const Map<String, List<String>> municipalityData = {
    'Cantilan': [
      'Bugsukan',
      'Buntalid',
      'Cabangahan',
      'Cabas-an',
      'Calagdaan',
      'Consuelo',
      'General Island',
      'Lininti-an',
      'Lobo',
      'Magasang',
      'Magosilom',
      'Pag-antayan',
      'Palasao',
      'Parang',
      'San Pedro',
      'Tapi',
      'Tigabong',
    ],
    'Madrid': [
      'Bagsac',
      'Bayogo',
      'Magsaysay',
      'Manga',
      'Panayogon',
      'Patong Patong',
      'Quirino',
      'San Antonio',
      'San Juan',
      'San Roque',
      'San Vicente',
      'Songkit',
      'Union',
      'Linibonan',
    ],
  };

  static const Map<String, Map<String, List<String>>> purokData = {
    'Cantilan': {
      'Bugsukan': defaultPuroks,
      'Buntalid': defaultPuroks,
      'Cabangahan': defaultPuroks,
      'Cabas-an': defaultPuroks,
      'Calagdaan': defaultPuroks,
      'Consuelo': defaultPuroks,
      'General Island': defaultPuroks,
      'Lininti-an': defaultPuroks,
      'Lobo': defaultPuroks,
      'Magasang': defaultPuroks,
      'Magosilom': defaultPuroks,
      'Pag-antayan': defaultPuroks,
      'Palasao': defaultPuroks,
      'Parang': defaultPuroks,
      'San Pedro': defaultPuroks,
      'Tapi': defaultPuroks,
      'Tigabong': defaultPuroks,
    },
    'Madrid': {
      'Bagsac': defaultPuroks,
      'Bayogo': defaultPuroks,
      'Magsaysay': defaultPuroks,
      'Manga': defaultPuroks,
      'Panayogon': defaultPuroks,
      'Patong Patong': defaultPuroks,
      'Quirino': defaultPuroks,
      'San Antonio': defaultPuroks,
      'San Juan': defaultPuroks,
      'San Roque': defaultPuroks,
      'San Vicente': defaultPuroks,
      'Songkit': defaultPuroks,
      'Union': defaultPuroks,
      'Linibonan': defaultPuroks,
    },
  };
}

/// eRefill design tokens — the single source of truth for color, radius,
/// spacing, type, motion and elevation. See `design-system/MASTER.md`.
///
/// Every text/background pair below is verified against WCAG 2.2 AA
/// (4.5:1 for body text, 3:1 for icons and large text).
class AppUi {
  // ── Brand (water blue) ─────────────────────────────────────────
  static const Color bluePrimary = Color(0xFF0F71C3); // 5.0:1 on white
  static const Color bluePrimaryDark = Color(0xFF0C5BA0);
  static const Color blueSoft = Color(0xFFEEF6FD); // brand text 4.6:1
  static const Color blueBorder = Color(0xFFBAD7F2);
  static const Color bluePale = Color(0xFFF1F7FD);
  static const Color deepBlue = Color(0xFF10283B);
  static const Color accentCyan = Color(0xFF42C2C8); // dark-mode primary
  static const Color accentGreen = Color(0xFF21866A);

  /// Legacy aliases
  static const Color tealPrimary = bluePrimary;
  static const Color tealPrimaryDark = bluePrimaryDark;
  static const Color tealSoft = blueSoft;
  static const Color tealBorder = blueBorder;
  static const Color tealPale = bluePale;

  // ── Neutrals (slate) ───────────────────────────────────────────
  static const Color surface = Colors.white;
  static const Color pageBg = Color(0xFFF8FAFC);
  static const Color lightSurfaceRaised = Color(0xFFF1F5F9);
  static const Color darkPageBg = Color(0xFF0B1220);
  static const Color darkSurface = Color(0xFF111A2B);
  static const Color darkSurfaceRaised = Color(0xFF1A2538);
  static const Color textPrimary = Color(0xFF0F172A); // 17.9:1
  static const Color textSecondary = Color(0xFF475569); // 7.6:1
  static const Color textMuted = Color(0xFF5B6B80); // 5.0:1 on raised
  static const Color textDisabled = Color(0xFF94A3B8);
  static const Color navUnselected = Color(0xFF5B6B80);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFFA8B4C6);
  static const Color darkTextMuted = Color(0xFF8E9BB0);

  // ── Semantic feedback ──────────────────────────────────────────
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color successFg = Color(0xFF166534);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color warningFg = Color(0xFF92400E);
  static const Color errorBg = Color(0xFFFEE2E2);
  static const Color error = Color(0xFFDC2626); // 4.8:1 on white
  static const Color errorFg = Color(0xFFB91C1C); // 5.3:1 on errorBg
  static const Color infoBg = blueSoft;
  static const Color info = bluePrimary;
  // Tint borders (light) and readable foregrounds on dark surfaces.
  static const Color successBorder = Color(0xFFBBF7D0);
  static const Color warningBorder = Color(0xFFFDE68A);
  static const Color errorBorder = Color(0xFFFECACA);
  static const Color successFgDark = Color(0xFF6EE7B7);
  static const Color warningFgDark = Color(0xFFFCD34D);
  static const Color errorFgDark = Color(0xFFFCA5A5);
  static const Color infoFgDark = Color(0xFF93C5FD);

  // ── Radius scale ───────────────────────────────────────────────
  // xs 4 · sm 6 · control 8 · card 12 · sheet 16 · pill 24 · full 999
  static const double radiusXs = 4;
  static const double radius = 8;
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLgValue = 12;
  static const double radiusControl = 8;
  static const double radiusCard = 12;
  static const double radiusDialog = 16;
  static const double radiusPill = 24;
  static const double radiusSheet = 16;
  static const double radiusFull = 999;
  static const double cardElevation = 0;
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;

  /// Standard touch target dimensions:
  /// - kMinTouchTarget (48dp): WCAG AA minimum for all interactive elements
  /// - kRiderTouchTarget (56dp): Large target for one-handed rider & transit operation
  static const double kMinTouchTarget = 48.0;
  static const double kRiderTouchTarget = 56.0;

  // ── Control dimensions ─────────────────────────────────────────
  static const double buttonHeightSm = 40;
  static const double buttonHeight = 48;
  static const double buttonHeightLg = 56;
  static const double inputHeight = 48;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;

  // ── Motion ─────────────────────────────────────────────────────
  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionBase = Duration(milliseconds: 200);
  static const Duration motionSlow = Duration(milliseconds: 300);
  static const Curve motionCurve = Curves.easeOutCubic;

  /// Honors the OS "reduce motion" setting; use [Duration.zero] when true.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration motion(BuildContext context, [Duration d = motionBase]) =>
      reduceMotion(context) ? Duration.zero : d;

  // ── Elevation ──────────────────────────────────────────────────
  // Borders do the separation work; shadows are reserved for overlays.
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 4)),
  ];

  // ── Spacing (4pt grid) ─────────────────────────────────────────
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 24;
  static const double spacing2xl = 32;
  static const double screenPadding = 16;
  static const double screenPaddingWide = 20;
  static const double bottomPadding = 32;

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(
    screenPadding,
    screenPadding,
    screenPadding,
    bottomPadding,
  );
  static const EdgeInsets pagePaddingLoose = EdgeInsets.fromLTRB(
    screenPaddingWide,
    screenPaddingWide,
    screenPaddingWide,
    bottomPadding,
  );
  static const EdgeInsets sectionPadding = EdgeInsets.all(screenPadding);
  static const EdgeInsets cardPadding = EdgeInsets.all(screenPadding);
  static const EdgeInsets cardPaddingLoose = EdgeInsets.all(screenPaddingWide);
  static const EdgeInsets sheetPadding = EdgeInsets.all(spacingXl);

  static const SizedBox gapXs = SizedBox(height: spacingXs, width: spacingXs);
  static const SizedBox gapSm = SizedBox(height: spacingSm, width: spacingSm);
  static const SizedBox gapMd = SizedBox(height: spacingMd, width: spacingMd);
  static const SizedBox gapLg = SizedBox(height: spacingLg, width: spacingLg);
  static const SizedBox gapXl = SizedBox(height: spacingXl, width: spacingXl);
  static const SizedBox vGapXs = SizedBox(height: spacingXs);
  static const SizedBox vGapSm = SizedBox(height: spacingSm);
  static const SizedBox vGapMd = SizedBox(height: spacingMd);
  static const SizedBox vGapLg = SizedBox(height: spacingLg);
  static const SizedBox vGapXl = SizedBox(height: spacingXl);
  static const SizedBox hGapXs = SizedBox(width: spacingXs);
  static const SizedBox hGapSm = SizedBox(width: spacingSm);
  static const SizedBox hGapMd = SizedBox(width: spacingMd);
  static const SizedBox hGapLg = SizedBox(width: spacingLg);
  static const SizedBox hGapXl = SizedBox(width: spacingXl);

  static BorderRadius get radiusLg => BorderRadius.circular(radiusMd);
  static BorderRadius get controlRadius => BorderRadius.circular(radiusControl);
  static BorderRadius get cardRadius => BorderRadius.circular(radiusCard);
  static BorderRadius get dialogRadius => BorderRadius.circular(radiusDialog);
  static BorderRadius get pillRadius => BorderRadius.circular(radiusPill);
  static BorderRadius get fullRadius => BorderRadius.circular(radiusFull);
  static const BorderRadius radiusSheetTop = BorderRadius.vertical(
    top: Radius.circular(radiusSheet),
  );

  static const double headerHeight = 72;
  static const double headerHeightWithSubtitle = 88;

  static const TextStyle headerTitleStyle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle headerSubtitleStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// Consistent typography scale for screens and sections.
  static const TextStyle screenTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
  static const TextStyle bodyText = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );
  static const TextStyle captionText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(20, 12, 20, 12);

  static BoxDecoration cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: cardRadius,
    border: Border.all(color: borderLight),
  );

  static BoxDecoration flatCardDecoration = BoxDecoration(
    color: surface,
    borderRadius: cardRadius,
  );

  static BoxDecoration flatCardDecorationOf(BuildContext context) =>
      BoxDecoration(color: surfaceOf(context), borderRadius: cardRadius);

  /// Refined 1px border tokens for crisp contrast across light and dark modes.
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderStrongLight = Color(0xFFCBD5E1);
  static const Color borderDark = Color(0xFF26334A);
  static const Color borderColor = borderLight;
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Brand accent that stays readable in both modes (cyan on dark).
  static Color brandOf(BuildContext context) =>
      isDark(context) ? accentCyan : bluePrimary;

  /// Soft brand tint for icon tiles, selected chips and tonal buttons.
  static Color brandSoftOf(BuildContext context) =>
      isDark(context) ? accentCyan.withValues(alpha: 0.16) : blueSoft;

  /// Text/icon color on [brandSoftOf].
  static Color onBrandSoftOf(BuildContext context) =>
      isDark(context) ? accentCyan : bluePrimaryDark;

  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color surfaceRaisedOf(BuildContext context) =>
      isDark(context) ? darkSurfaceRaised : lightSurfaceRaised;

  static Color pageBgOf(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  /// Hairline separators inside grouped lists.
  static Color dividerOf(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? borderDark : borderLight;
  }

  /// Card and container outlines — Shadcn 1px subtle border.
  static Color borderOf(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? borderDark : borderLight;
  }

  static Color textPrimaryOf(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).textTheme.bodyLarge?.color;
    if (themeColor != null) {
      if (isDark && themeColor.computeLuminance() < 0.25) {
        return darkTextPrimary;
      }
      return themeColor;
    }
    return isDark ? darkTextPrimary : textPrimary;
  }

  static Color textSecondaryOf(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).textTheme.bodyMedium?.color;
    if (themeColor != null) {
      if (isDark && themeColor.computeLuminance() < 0.25) {
        return darkTextSecondary;
      }
      return themeColor;
    }
    return isDark ? darkTextSecondary : textSecondary;
  }

  static Color chipBgOf(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  static Color chipBorderOf(BuildContext context) => borderOf(context);

  static BoxDecoration cardDecorationOf(
    BuildContext context, {
    Color? color,
    Color? borderColor,
    BorderRadius? borderRadius,
    bool elevated = false,
  }) {
    final outline = borderColor ?? borderOf(context);
    return BoxDecoration(
      color: color ?? surfaceOf(context),
      borderRadius: borderRadius ?? cardRadius,
      border: Border.all(color: outline, width: 1),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.25
                      : 0.05,
                ),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );
  }

  static InputDecoration fieldDecorationOf(
    BuildContext context,
    String hint, {
    Widget? prefixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
      labelText: hint,
      labelStyle: TextStyle(
        color: textSecondaryOf(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      floatingLabelStyle: const TextStyle(
        color: bluePrimary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      hintStyle: TextStyle(
        color: textSecondaryOf(context),
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      filled: true,
      fillColor: surfaceOf(context),
      border: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(
          color: isDark ? accentCyan : bluePrimary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: const BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: const BorderSide(color: error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  static Color heroColorOf(BuildContext context) {
    return Theme.of(context).scaffoldBackgroundColor;
  }

  // Flat single-color gradients for legacy compatibility (no gradient transitions)
  static const LinearGradient heroGradientLight = LinearGradient(
    colors: [pageBg, pageBg],
  );

  static const LinearGradient heroGradientDark = LinearGradient(
    colors: [darkPageBg, darkPageBg],
  );

  static LinearGradient heroGradientOf(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? heroGradientDark
        : heroGradientLight;
  }

  static InputDecoration fieldDecoration(String hint, {Widget? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
      labelText: hint,
      labelStyle: const TextStyle(
        color: textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      floatingLabelStyle: const TextStyle(
        color: bluePrimary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      hintStyle: const TextStyle(
        color: textSecondary,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: const BorderSide(color: bluePrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: const BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: const BorderSide(color: error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
