import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants.dart';

/// A coastal-themed water-fill loading indicator that animates a gentle wave
/// filling up inside a droplet or container silhouette.
///
/// Respects [MediaQueryData.disableAnimations] (system Reduce Motion setting).
class WaterFillLoadingIndicator extends StatefulWidget {
  final double size;
  final String? message;
  final Color? waveColor;
  final Color? dropletColor;

  const WaterFillLoadingIndicator({
    super.key,
    this.size = 64.0,
    this.message,
    this.waveColor,
    this.dropletColor,
  });

  @override
  State<WaterFillLoadingIndicator> createState() =>
      _WaterFillLoadingIndicatorState();
}

class _WaterFillLoadingIndicatorState extends State<WaterFillLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final wave = widget.waveColor ?? AppUi.bluePrimary;
    final droplet = widget.dropletColor ?? AppUi.blueSoft;

    return Semantics(
      label: widget.message ?? 'Loading water refill data',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: reduceMotion
                ? _buildStatic(droplet, wave)
                : AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _WaterFillPainter(
                          progress: _controller.value,
                          waveColor: wave,
                          dropletBgColor: droplet,
                        ),
                      );
                    },
                  ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppUi.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatic(Color bg, Color fill) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.water_drop_rounded,
          color: fill,
          size: widget.size * 0.55,
        ),
      ),
    );
  }
}

class _WaterFillPainter extends CustomPainter {
  final double progress;
  final Color waveColor;
  final Color dropletBgColor;

  _WaterFillPainter({
    required this.progress,
    required this.waveColor,
    required this.dropletBgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw circular droplet background
    final bgPaint = Paint()
      ..color = dropletBgColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Clip to the circle
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(circlePath);

    // Draw the animated wave filling
    final wavePaint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.fill;

    final wavePath = Path();
    // Fill level sits around 55% from the bottom
    final baseHeight = size.height * 0.45;
    final waveAmplitude = size.height * 0.06;
    final waveLength = size.width;

    wavePath.moveTo(0, size.height);
    wavePath.lineTo(0, baseHeight);

    for (double x = 0; x <= size.width; x += 1) {
      final y = baseHeight +
          waveAmplitude *
              math.sin((x / waveLength * 2 * math.pi) + (progress * 2 * math.pi));
      wavePath.lineTo(x, y);
    }

    wavePath.lineTo(size.width, size.height);
    wavePath.close();

    canvas.drawPath(wavePath, wavePaint);
    canvas.restore();

    // Draw subtle border ring
    final borderPaint = Paint()
      ..color = waveColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _WaterFillPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.waveColor != waveColor ||
        oldDelegate.dropletBgColor != dropletBgColor;
  }
}

