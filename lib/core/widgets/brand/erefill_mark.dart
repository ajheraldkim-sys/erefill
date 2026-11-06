import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';

export '../../theme/brand_colors.dart';

/// The eRefill symbol: a ribbon "e" with a water drop in its mouth.
///
/// Drawn in code so it stays sharp at any size; the launcher icon and splash
/// images are rendered from this same painter (see `tool/render_brand_assets`).
/// Pass [color] for a one-color version (white on blue, black on paper).
class ERefillMark extends StatelessWidget {
  const ERefillMark({super.key, this.size = 48, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'eRefill',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: ERefillMarkPainter(color: color),
      ),
    );
  }
}

class ERefillMarkPainter extends CustomPainter {
  const ERefillMarkPainter({this.color});

  /// One-color override; null paints the brand gradient.
  final Color? color;

  // Geometry in a unit square, tuned against the reference artwork so the
  // whole symbol (bowl + drop) is optically centred.
  static const _center = Offset(0.49, 0.50);
  static const _radius = 0.28; // stroke centerline
  static const _stroke = 0.205;
  static const _terminalDeg = 52.0; // bottom-right cut end of the bowl
  static const _turnDeg = -30.0; // top right, where the ribbon folds back
  static const _barEnd = Offset(0.267, 0.626);

  /// Where along the crossbar the tucked-under shading begins (0..1).
  static const _foldFrom = 0.48;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s);

    final c = _center;
    final r = _radius;
    const bounds = Rect.fromLTWH(0, 0, 1, 1);
    final mono = color;

    final start = _terminalDeg * math.pi / 180;
    final turn = _turnDeg * math.pi / 180;
    final sweep = (2 * math.pi - start) + turn;
    final corner = c + Offset(math.cos(turn) * r, math.sin(turn) * r);

    // 1. The ribbon as ONE stroke: bottom-right terminal, round the bowl,
    //    a folded corner at the top right, then the crossbar down-left.
    //    One stroke with one shader means no seam where the bar meets the
    //    bowl; the round join gives the folded corner its curve.
    final ribbon = Path()
      ..arcTo(Rect.fromCircle(center: c, radius: r), start, sweep, true)
      ..lineTo(_barEnd.dx, _barEnd.dy);
    final ribbonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.butt;
    final fill = mono == null
        ? (const LinearGradient(
            begin: Alignment(0.75, -1),
            end: Alignment(-0.75, 1),
            colors: [BrandColors.sky, BrandColors.azure, BrandColors.royal],
            stops: [0, 0.42, 1],
          ).createShader(bounds))
        : null;
    if (fill != null) {
      ribbonPaint.shader = fill;
    } else {
      ribbonPaint.color = mono!;
    }
    canvas.drawPath(ribbon, ribbonPaint);

    // 2. The fold: the crossbar's end tucks over the bowl's left side.
    //    Shadow under it, the same fill on top (seamless), then a darker
    //    tint toward the tip so it reads as the ribbon's underside.
    // One closed outline: a flat start (no visible edge on the bar) and a
    // rounded tip, filled once so the shading never doubles up.
    final foldStart = Offset.lerp(corner, _barEnd, _foldFrom)!;
    final along = _barEnd - foldStart;
    final dir = along / along.distance;
    final hw = _stroke / 2;
    final normal = Offset(-dir.dy, dir.dx) * hw;
    final fold = Path()
      ..moveTo(foldStart.dx + normal.dx, foldStart.dy + normal.dy)
      ..lineTo(_barEnd.dx + normal.dx, _barEnd.dy + normal.dy)
      ..arcTo(
        Rect.fromCircle(center: _barEnd, radius: hw),
        math.atan2(normal.dy, normal.dx),
        -math.pi,
        false,
      )
      ..lineTo(foldStart.dx - normal.dx, foldStart.dy - normal.dy)
      ..close();
    void drawFold(Paint paint) => canvas.drawPath(fold, paint);

    if (mono == null) {
      // Shadow falls only on the bowl ring, where the bar tucks over it.
      canvas.save();
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCircle(center: c, radius: r + _stroke / 2))
          ..addOval(Rect.fromCircle(center: c, radius: r - _stroke / 2)),
      );
      drawFold(
        Paint()
          ..color = BrandColors.royalDeep.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.018),
      );
      canvas.restore();
      drawFold(Paint()..shader = fill);
      drawFold(
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(foldStart.dx * 2 - 1, foldStart.dy * 2 - 1),
            end: Alignment(_barEnd.dx * 2 - 1, _barEnd.dy * 2 - 1),
            colors: [
              BrandColors.royalDeep.withValues(alpha: 0),
              BrandColors.royalDeep.withValues(alpha: 0.5),
            ],
          ).createShader(bounds),
      );
    } else {
      drawFold(Paint()..color = mono);
    }

    // 3. Drop in the mouth of the "e".
    const dropCenter = Offset(0.77, 0.675);
    const dw = 0.165;
    const dh = 0.245;
    final top = Offset(dropCenter.dx, dropCenter.dy - dh / 2);
    final bottom = dropCenter.dy + dh / 2;
    final drop = Path()
      ..moveTo(top.dx, top.dy)
      ..cubicTo(
        top.dx + dw * 0.18,
        top.dy + dh * 0.22,
        top.dx + dw / 2,
        top.dy + dh * 0.45,
        top.dx + dw / 2,
        top.dy + dh * 0.66,
      )
      ..cubicTo(
        top.dx + dw / 2,
        bottom - dh * 0.06,
        top.dx + dw * 0.24,
        bottom,
        top.dx,
        bottom,
      )
      ..cubicTo(
        top.dx - dw * 0.24,
        bottom,
        top.dx - dw / 2,
        bottom - dh * 0.06,
        top.dx - dw / 2,
        top.dy + dh * 0.66,
      )
      ..cubicTo(
        top.dx - dw / 2,
        top.dy + dh * 0.45,
        top.dx - dw * 0.18,
        top.dy + dh * 0.22,
        top.dx,
        top.dy,
      )
      ..close();
    final dropPaint = Paint();
    if (mono != null) {
      dropPaint.color = mono;
    } else {
      dropPaint.shader = LinearGradient(
        begin: Alignment(0, (top.dy) * 2 - 1),
        end: Alignment(0, bottom * 2 - 1),
        colors: const [BrandColors.sky, BrandColors.royal],
      ).createShader(bounds);
    }
    canvas.drawPath(drop, dropPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(ERefillMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
