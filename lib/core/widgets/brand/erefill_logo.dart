import 'package:flutter/material.dart';

import '../../constants.dart';
import 'erefill_mark.dart';

export 'erefill_mark.dart' show BrandColors, ERefillMark;

/// eRefill logo lockup: the ribbon "e" mark, the "eRefill" wordmark and,
/// optionally, the "CLEAN WATER. MADE EASY." tagline.
///
/// The wordmark is navy on light surfaces and white on dark ones, like the
/// brand board. Pass [color] to force a wordmark color (e.g. white on a
/// blue hero) and [markColor] for a one-color mark.
class ERefillLogo extends StatelessWidget {
  const ERefillLogo({
    super.key,
    this.size = 48,
    this.showWordmark = true,
    this.showMark = true,
    this.showTagline = false,
    this.stacked = false,
    this.color,
    this.markColor,
  });

  /// Height of the mark; the wordmark scales with it.
  final double size;
  final bool showWordmark;

  /// When false, only the wordmark is shown.
  final bool showMark;
  final bool showTagline;

  /// Mark above the wordmark (login, splash) instead of beside it.
  final bool stacked;

  /// Wordmark color; defaults to navy, or white in dark mode.
  final Color? color;

  /// One-color mark; null keeps the brand gradient.
  final Color? markColor;

  @override
  Widget build(BuildContext context) {
    final fg =
        color ??
        (AppUi.isDark(context) ? Colors.white : BrandColors.navy);
    final mark = ERefillMark(size: size, color: markColor);
    if (!showWordmark) return mark;

    final wordmark = _Wordmark(
      color: fg,
      fontSize: showMark ? size * 0.62 : size,
      showTagline: showTagline,
      center: stacked,
    );
    if (!showMark) return wordmark;

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [mark, SizedBox(height: size * 0.18), wordmark],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [mark, SizedBox(width: size * 0.16), wordmark],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({
    required this.color,
    required this.fontSize,
    required this.showTagline,
    required this.center,
  });

  final Color color;
  final double fontSize;
  final bool showTagline;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final name = Text(
      'eRefill',
      semanticsLabel: 'eRefill',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -fontSize * 0.02,
        height: 1.05,
        color: color,
      ),
    );
    if (!showTagline) return name;

    final taglineColor = color == BrandColors.navy
        ? BrandColors.slate
        : color.withValues(alpha: 0.72);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        name,
        SizedBox(height: fontSize * 0.08),
        Text(
          BrandColors.tagline,
          style: TextStyle(
            fontSize: (fontSize * 0.2).clamp(9, 18),
            fontWeight: FontWeight.w600,
            letterSpacing: fontSize * 0.055,
            color: taglineColor,
          ),
        ),
      ],
    );
  }
}
