// lib/core/theme/app_spacing.dart
// Re-exports AppUi spacing for a single source of truth.
export '../constants.dart' show AppUi;

import 'package:flutter/material.dart';
import '../constants.dart';

/// @deprecated Use [AppUi] spacing constants instead.
class AppSpacing {
  // Padding and Margin — mirrors AppUi
  static const double xs = AppUi.spacingXs;
  static const double sm = AppUi.spacingSm;
  static const double md = AppUi.spacingMd;
  static const double lg = AppUi.screenPadding;
  static const double xl = AppUi.spacingXl;
  static const double xxl = AppUi.spacing2xl;
  static const double xxxl = AppUi.spacing2xl;
  static const double screen = AppUi.screenPadding;
  static const double screenWide = AppUi.screenPaddingWide;

  // Border Radius
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 14;
  static const double radiusXl = 16;
  static const double radiusCircle = 32;

  // Icon Sizes
  static const double iconXs = 16;
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double iconXl = 48;
  static const double iconXxl = 64;

  // Button Heights
  static const double buttonHeightSmall = 36;
  static const double buttonHeightMedium = 44;
  static const double buttonHeightLarge = 52;

  // Common Padding
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(
    screen,
    screen,
    screen,
    xxxl,
  );
  static const EdgeInsets pagePaddingLoose = EdgeInsets.fromLTRB(
    screenWide,
    screenWide,
    screenWide,
    xxxl,
  );
  static const EdgeInsets cardPadding = EdgeInsets.all(screen);

  static const EdgeInsets paddingHorizontalMd = EdgeInsets.symmetric(
    horizontal: md,
  );
  static const EdgeInsets paddingHorizontalLg = EdgeInsets.symmetric(
    horizontal: lg,
  );
  static const EdgeInsets paddingVerticalMd = EdgeInsets.symmetric(
    vertical: md,
  );
  static const EdgeInsets paddingVerticalLg = EdgeInsets.symmetric(
    vertical: lg,
  );

  // Common Gaps
  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
  static const SizedBox gapXl = SizedBox(width: xl, height: xl);

  static const SizedBox gapVerticalXs = SizedBox(height: xs);
  static const SizedBox gapVerticalSm = SizedBox(height: sm);
  static const SizedBox gapVerticalMd = SizedBox(height: md);
  static const SizedBox gapVerticalLg = SizedBox(height: lg);
  static const SizedBox gapVerticalXl = SizedBox(height: xl);

  static const SizedBox gapHorizontalXs = SizedBox(width: xs);
  static const SizedBox gapHorizontalSm = SizedBox(width: sm);
  static const SizedBox gapHorizontalMd = SizedBox(width: md);
  static const SizedBox gapHorizontalLg = SizedBox(width: lg);
  static const SizedBox gapHorizontalXl = SizedBox(width: xl);
}
