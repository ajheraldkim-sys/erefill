import 'package:flutter/painting.dart';

/// eRefill brand identity colors, from the brand board.
///
/// The mark's gradient runs from [sky] (top right) through [azure] to
/// [royal] (bottom left). [navy] is the wordmark color and the dark brand
/// surface (splash); [slate] is the tagline on light backgrounds.
abstract final class BrandColors {
  static const Color sky = Color(0xFF3CCBFA);
  static const Color azure = Color(0xFF2196F3);
  static const Color royal = Color(0xFF1858D8);
  static const Color royalDeep = Color(0xFF1449C0);
  static const Color navy = Color(0xFF0F1F3D);
  static const Color slate = Color(0xFF4A5A78);

  static const String tagline = 'CLEAN WATER. MADE EASY.';
}
