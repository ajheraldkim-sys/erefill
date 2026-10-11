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
  static const String paymongoPublicKey =
      'pk_test_1zYhxAz8T8ceWW9wXeLM9cMb';

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
      'Linibonan',
      'Magsaysay',
      'Manga',
      'Panubigan',
      'Patong',
      'Quirino',
      'San Juan',
      'San Roque',
      'San Vicente',
      'Union',
      'Urbiztondo',
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
      'Linibonan': defaultPuroks,
      'Magsaysay': defaultPuroks,
      'Manga': defaultPuroks,
      'Panubigan': defaultPuroks,
      'Patong': defaultPuroks,
      'Quirino': defaultPuroks,
      'San Juan': defaultPuroks,
      'San Roque': defaultPuroks,
      'San Vicente': defaultPuroks,
      'Union': defaultPuroks,
      'Urbiztondo': defaultPuroks,
    },
  };
}

class AppUi {
  // Premium coastal palette
  static const Color bluePrimary = Color(0xFF087E8B);
  static const Color bluePrimaryDark = Color(0xFF066873);
  static const Color blueSoft = Color(0xFFE3F3F3);
  static const Color blueBorder = Color(0xFFC6E0E1);
  static const Color bluePale = Color(0xFFF0F8F8);
  static const Color deepBlue = Color(0xFF193438);
  static const Color accentCyan = Color(0xFF42C2C8);
  static const Color accentGreen = Color(0xFF21866A);

  /// Legacy aliases
  static const Color tealPrimary = bluePrimary;
  static const Color tealPrimaryDark = bluePrimaryDark;
  static const Color tealSoft = blueSoft;
  static const Color tealBorder = blueBorder;
  static const Color tealPale = bluePale;

  static const Color surface = Colors.white;
  static const Color pageBg = Color(0xFFF5F7F8);
  static const Color lightSurfaceRaised = Color(0xFFEDF2F3);
  static const Color darkPageBg = Color(0xFF0B1215);
  static const Color darkSurface = Color(0xFF121D21);
  static const Color darkSurfaceRaised = Color(0xFF1B2A2F);
  static const Color textPrimary = Color(0xFF17252A);
  static const Color textSecondary = Color(0xFF64777D);
  static const Color textMuted = Color(0xFF829398);
  static const Color textDisabled = Color(0xFFC9D1DD);
  static const Color navUnselected = Color(0xFFA0B2B7);

  static const Color successBg = Color(0xFFE8F5EF);
  static const Color successFg = Color(0xFF17664F);
  static const Color warningBg = Color(0xFFFFF4DF);
  static const Color warningFg = Color(0xFF85520F);
  static const Color error = Color(0xFFC2414B);

  static const double radius = 8;
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLgValue = 12;
  static const double radiusControl = 8;
  static const double radiusCard = 12;
  static const double radiusDialog = 12;
  static const double radiusPill = 24;
  static const double radiusSheet = 16;
  static const double cardElevation = 0;
  static const double spacingXs = 6;
  static const double spacingSm = 10;
  static const double spacingMd = 14;
  static const double spacingLg = 18;
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
  static const BorderRadius radiusSheetTop = BorderRadius.vertical(
    top: Radius.circular(radiusSheet),
  );

  static const double headerHeight = 72;
  static const double headerHeightWithSubtitle = 88;

  static const TextStyle headerTitleStyle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );

  static const TextStyle headerSubtitleStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// Consistent typography scale for screens and sections.
  static const TextStyle screenTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );
  static const TextStyle bodyText = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
  static const TextStyle captionText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(20, 12, 20, 12);

  static BoxDecoration cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: radiusLg,
    boxShadow: const [
      BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4)),
    ],
  );

  static BoxDecoration flatCardDecoration = BoxDecoration(
    color: surface,
    borderRadius: radiusLg,
  );

  static BoxDecoration flatCardDecorationOf(BuildContext context) =>
      BoxDecoration(color: surfaceOf(context), borderRadius: radiusLg);

  /// Softened 1px hairline border tokens for reduced visual noise.
  static const Color borderLight = Color(0xFFF1F4F5);
  static const Color borderDark = Color(0xFF243237);
  static const Color borderColor = borderLight;
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

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
        return const Color(0xFFF0F4F6);
      }
      return themeColor;
    }
    return isDark ? const Color(0xFFF0F4F6) : textPrimary;
  }

  static Color textSecondaryOf(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).textTheme.bodyMedium?.color;
    if (themeColor != null) {
      if (isDark && themeColor.computeLuminance() < 0.25) {
        return const Color(0xFFA0B2B7);
      }
      return themeColor;
    }
    return isDark ? const Color(0xFFA0B2B7) : textSecondary;
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
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
      floatingLabelStyle: const TextStyle(
        color: bluePrimary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
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
        borderRadius: cardRadius,
        borderSide: BorderSide(color: borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: BorderSide(color: borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: BorderSide(
          color: isDark ? accentCyan : bluePrimary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: const BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: const BorderSide(color: error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
        color: textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
      floatingLabelStyle: const TextStyle(
        color: bluePrimary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
      hintStyle: const TextStyle(
        color: textMuted,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: const BorderSide(color: bluePrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: const BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: cardRadius,
        borderSide: const BorderSide(color: error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }
}
