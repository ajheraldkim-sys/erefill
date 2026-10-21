import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants.dart';

/// eRefill drop that fills with water while something loads. The fill rises
/// once, then the surface keeps a slow wave until the widget is removed.
/// With reduced motion it renders a full, still drop.
class WaterFillMark extends StatefulWidget {
  const WaterFillMark({
    super.key,
    this.size = 96,
    this.fillColor = AppUi.accentCyan,
    this.outlineColor = const Color(0x33FFFFFF),
    this.fillDuration = const Duration(milliseconds: 1400),
  });

  final double size;
  final Color fillColor;
  final Color outlineColor;
  final Duration fillDuration;

  @override
  State<WaterFillMark> createState() => _WaterFillMarkState();
}

class _WaterFillMarkState extends State<WaterFillMark>
    with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: widget.fillDuration,
  );
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final Animation<double> _level = CurvedAnimation(
    parent: _fill,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppUi.reduceMotion(context)) {
      _fill.value = 1;
      _wave.stop();
    } else if (!_started) {
      _started = true;
      _fill.forward();
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_fill, _wave]),
          builder: (context, _) => CustomPaint(
            size: Size(widget.size, widget.size * 1.2),
            painter: _WaterFillPainter(
              level: _level.value,
              phase: _wave.value * 2 * math.pi,
              fillColor: widget.fillColor,
              outlineColor: widget.outlineColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaterFillPainter extends CustomPainter {
  _WaterFillPainter({
    required this.level,
    required this.phase,
    required this.fillColor,
    required this.outlineColor,
  });

  final double level;
  final double phase;
  final Color fillColor;
  final Color outlineColor;

  Path _drop(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    return Path()
      ..moveTo(cx, 0)
      ..cubicTo(w * 0.62, h * 0.18, w, h * 0.46, w, h * 0.66)
      ..cubicTo(w, h * 0.86, w * 0.78, h, cx, h)
      ..cubicTo(w * 0.22, h, 0, h * 0.86, 0, h * 0.66)
      ..cubicTo(0, h * 0.46, w * 0.38, h * 0.18, cx, 0)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final drop = _drop(size);
    final w = size.width;
    final h = size.height;

    canvas.save();
    canvas.clipPath(drop);

    // Water surface: a low sine wave that flattens as the drop fills.
    final surface = h * (1 - level);
    final amplitude = h * 0.035 * (1 - level * 0.6);
    final water = Path()..moveTo(0, h);
    for (double x = 0; x <= w; x += 2) {
      final y = surface + math.sin(x / w * 2 * math.pi + phase) * amplitude;
      water.lineTo(x, y);
    }
    water
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(water, Paint()..color = fillColor);

    // Soft highlight on the left so the drop reads as glass, not a flat blob.
    canvas.drawCircle(
      Offset(w * 0.32, h * 0.58),
      w * 0.09,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    canvas.restore();

    canvas.drawPath(
      drop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, w * 0.03)
        ..color = outlineColor,
    );
  }

  @override
  bool shouldRepaint(_WaterFillPainter old) =>
      old.level != level ||
      old.phase != phase ||
      old.fillColor != fillColor ||
      old.outlineColor != outlineColor;
}
