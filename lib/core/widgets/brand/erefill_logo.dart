import 'package:flutter/material.dart';

import '../../constants.dart';

/// Modern eRefill brand mark — rounded icon + clean wordmark.
class ERefillLogo extends StatelessWidget {
  const ERefillLogo({
    super.key,
    this.size = 48,
    this.showWordmark = true,
    this.showMark = true,
    this.stacked = false,
    this.color,
    this.markColor,
  });

  final double size;
  final bool showWordmark;

  /// When false, only the wordmark is shown (e.g. login header).
  final bool showMark;

  /// Icon above wordmark (login / splash).
  final bool stacked;
  final Color? color;
  final Color? markColor;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppUi.textPrimaryOf(context);
    final primary = markColor ?? AppUi.bluePrimary;

    final mark = _BrandMark(size: size, primary: primary);
    final wordmark = _Wordmark(
      fg: fg,
      primary: primary,
      size: size,
      wordmarkOnly: !showMark,
    );

    if (!showMark) return wordmark;
    if (!showWordmark) return mark;

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(height: size * 0.22),
          wordmark,
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        SizedBox(width: size * 0.2),
        wordmark,
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size, required this.primary});

  final double size;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final dim = size * 1.05;
    return Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(dim * 0.28),
      ),
      child: CustomPaint(painter: _DropGlyphPainter(), size: Size(dim, dim)),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({
    required this.fg,
    required this.primary,
    required this.size,
    this.wordmarkOnly = false,
  });

  final Color fg;
  final Color primary;
  final double size;
  final bool wordmarkOnly;

  @override
  Widget build(BuildContext context) {
    final fontSize = wordmarkOnly ? size : size * 0.58;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'e',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: primary,
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: 'Refill',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: -0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;

    final drop = Path()
      ..moveTo(cx, h * 0.22)
      ..cubicTo(w * 0.78, h * 0.38, w * 0.72, h * 0.72, cx, h * 0.78)
      ..cubicTo(w * 0.28, h * 0.72, w * 0.22, h * 0.38, cx, h * 0.22)
      ..close();

    canvas.drawPath(
      drop,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, h * 0.52), radius: w * 0.14),
      2.4,
      2.2,
      false,
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
