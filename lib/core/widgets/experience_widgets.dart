import 'package:flutter/material.dart';

import '../constants.dart';
import 'brand/axo_states.dart';

enum ExperienceRole { customer, owner, rider, support }

enum ExperienceScene {
  discover,
  setup,
  station,
  delivery,
  reports,
  success,
  empty,
  error,
}

class ExperienceStep {
  final String label;
  final String? helper;
  final bool isComplete;
  final VoidCallback? onTap;

  const ExperienceStep({
    required this.label,
    this.helper,
    required this.isComplete,
    this.onTap,
  });
}

class PressableScale extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius ?? AppUi.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? AppUi.cardRadius,
        child: child,
      ),
    );
  }
}

class ExperienceIllustration extends StatelessWidget {
  final ExperienceScene scene;
  final ExperienceRole role;
  final double height;
  final bool animate;

  const ExperienceIllustration({
    super.key,
    this.scene = ExperienceScene.discover,
    this.role = ExperienceRole.customer,
    this.height = 150,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = CustomPaint(
      painter: _ExperiencePainter(
        scene: scene,
        role: role,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
      child: SizedBox(width: double.infinity, height: height),
    );

    return child;
  }
}

class FriendlyHeroCard extends StatelessWidget {
  final ExperienceRole role;
  final ExperienceScene scene;
  final String eyebrow;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const FriendlyHeroCard({
    super.key,
    required this.role,
    required this.scene,
    required this.eyebrow,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(role);
    return PressableScale(
      onTap: onAction,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: AppUi.cardDecorationOf(
          context,
          color: roleColor.withValues(alpha: 0.08),
          borderColor: roleColor.withValues(alpha: 0.18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: TextStyle(
                      color: roleColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppUi.textSecondaryOf(context),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (actionIcon != null) ...[
                          Icon(actionIcon, size: 16, color: roleColor),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          actionLabel!,
                          style: TextStyle(
                            color: roleColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 112,
              child: ExperienceIllustration(
                role: role,
                scene: scene,
                height: 118,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GuidedSetupCard extends StatelessWidget {
  final ExperienceRole role;
  final String title;
  final String message;
  final List<ExperienceStep> steps;
  final String? actionLabel;
  final VoidCallback? onAction;

  const GuidedSetupCard({
    super.key,
    required this.role,
    required this.title,
    required this.message,
    required this.steps,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final done = steps.where((step) => step.isComplete).length;
    final progress = steps.isEmpty ? 0.0 : done / steps.length;
    final color = _roleColor(role);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppUi.cardDecorationOf(context, elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 88,
                child: ExperienceIllustration(
                  role: role,
                  scene: ExperienceScene.setup,
                  height: 86,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppUi.textSecondaryOf(context),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$done of ${steps.length} steps complete',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...steps.map((step) => _SetupStepRow(step: step, color: color)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SetupStepRow extends StatelessWidget {
  final ExperienceStep step;
  final Color color;

  const _SetupStepRow({required this.step, required this.color});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: step.onTap,
      borderRadius: AppUi.controlRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: step.isComplete ? color : color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                step.isComplete
                    ? Icons.check_rounded
                    : Icons.arrow_forward_rounded,
                color: step.isComplete ? Colors.white : color,
                size: 15,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      color: step.isComplete
                          ? AppUi.textPrimaryOf(context)
                          : AppUi.textSecondaryOf(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (step.helper != null)
                    Text(
                      step.helper!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppUi.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendlyFeedbackBanner extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FriendlyFeedbackBanner({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppUi.cardDecorationOf(
        context,
        color: color.withValues(alpha: 0.08),
        borderColor: color.withValues(alpha: 0.22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: Text(actionLabel!),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: color,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _roleColor(ExperienceRole role) {
  return switch (role) {
    ExperienceRole.customer => AppUi.bluePrimary,
    ExperienceRole.owner => AppUi.accentGreen,
    ExperienceRole.rider => AppUi.accentCyan,
    ExperienceRole.support => const Color(0xFF8B5CF6),
  };
}

class _ExperiencePainter extends CustomPainter {
  final ExperienceScene scene;
  final ExperienceRole role;
  final bool isDark;

  _ExperiencePainter({
    required this.scene,
    required this.role,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final roleColor = _roleColor(role);
    final bg = Paint()
      ..color = isDark
          ? const Color(0xFF0B1220)
          : roleColor.withValues(alpha: 0.1);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, h * 0.08, w * 0.92, h * 0.82),
        Radius.circular(w * 0.12),
      ),
      bg,
    );

    _drawBubbles(canvas, size, roleColor);
    _drawBaseWave(canvas, size, roleColor);

    switch (scene) {
      case ExperienceScene.delivery:
        _drawDelivery(canvas, size, roleColor);
      case ExperienceScene.station:
        _drawStation(canvas, size, roleColor);
      case ExperienceScene.reports:
        _drawReports(canvas, size, roleColor);
      case ExperienceScene.setup:
        _drawSetup(canvas, size, roleColor);
      case ExperienceScene.success:
        _drawSuccess(canvas, size, roleColor);
      case ExperienceScene.error:
        _drawError(canvas, size);
      case ExperienceScene.empty:
        _drawEmpty(canvas, size, roleColor);
      case ExperienceScene.discover:
        _drawDiscover(canvas, size, roleColor);
    }
  }

  void _drawBubbles(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    for (final bubble in [
      (x: 0.16, y: 0.24, r: 0.045),
      (x: 0.82, y: 0.22, r: 0.035),
      (x: 0.73, y: 0.72, r: 0.055),
      (x: 0.29, y: 0.76, r: 0.03),
    ]) {
      canvas.drawCircle(
        Offset(size.width * bubble.x, size.height * bubble.y),
        size.width * bubble.r,
        paint,
      );
    }
  }

  void _drawBaseWave(Canvas canvas, Size size, Color color) {
    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.72)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.63,
        size.width * 0.43,
        size.height * 0.84,
        size.width * 0.62,
        size.height * 0.72,
      )
      ..cubicTo(
        size.width * 0.76,
        size.height * 0.63,
        size.width * 0.88,
        size.height * 0.68,
        size.width * 0.94,
        size.height * 0.71,
      )
      ..lineTo(size.width * 0.94, size.height * 0.88)
      ..lineTo(size.width * 0.08, size.height * 0.88)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.16));
  }

  void _drawDiscover(Canvas canvas, Size size, Color color) {
    _drawMapPin(canvas, Offset(size.width * 0.38, size.height * 0.43), color);
    _drawStation(canvas, size, color, compact: true);
    _drawDrop(
      canvas,
      Offset(size.width * 0.64, size.height * 0.48),
      size.width * 0.12,
      color,
    );
  }

  void _drawStation(
    Canvas canvas,
    Size size,
    Color color, {
    bool compact = false,
  }) {
    final house = Paint()..color = color;
    final roof = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.84);
    final x = compact ? size.width * 0.45 : size.width * 0.22;
    final y = compact ? size.height * 0.45 : size.height * 0.36;
    final width = compact ? size.width * 0.28 : size.width * 0.5;
    final height = compact ? size.height * 0.22 : size.height * 0.34;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        Radius.circular(size.width * 0.035),
      ),
      house,
    );
    final roofPath = Path()
      ..moveTo(x - width * 0.05, y + height * 0.05)
      ..lineTo(x + width * 0.5, y - height * 0.42)
      ..lineTo(x + width * 1.05, y + height * 0.05)
      ..close();
    canvas.drawPath(roofPath, roof);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x + width * 0.12,
          y + height * 0.26,
          width * 0.22,
          height * 0.2,
        ),
        Radius.circular(8),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x + width * 0.58,
          y + height * 0.34,
          width * 0.18,
          height * 0.55,
        ),
        Radius.circular(8),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  void _drawDelivery(Canvas canvas, Size size, Color color) {
    final truck = Paint()..color = color;
    final dark = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.86);
    final x = size.width * 0.2;
    final y = size.height * 0.44;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, size.width * 0.48, size.height * 0.2),
        Radius.circular(size.width * 0.04),
      ),
      truck,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.58,
          y + size.height * 0.05,
          size.width * 0.18,
          size.height * 0.15,
        ),
        Radius.circular(size.width * 0.035),
      ),
      truck,
    );
    for (final cx in [size.width * 0.32, size.width * 0.68]) {
      canvas.drawCircle(
        Offset(cx, y + size.height * 0.22),
        size.width * 0.055,
        dark,
      );
      canvas.drawCircle(
        Offset(cx, y + size.height * 0.22),
        size.width * 0.025,
        Paint()..color = Colors.white,
      );
    }
    _drawDrop(
      canvas,
      Offset(size.width * 0.43, size.height * 0.52),
      size.width * 0.09,
      Colors.white,
    );
  }

  void _drawReports(Canvas canvas, Size size, Color color) {
    final baseX = size.width * 0.24;
    final baseY = size.height * 0.66;
    final widths = size.width * 0.11;
    final values = [0.22, 0.36, 0.28, 0.46];
    for (var i = 0; i < values.length; i++) {
      final h = size.height * values[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(baseX + i * size.width * 0.14, baseY - h, widths, h),
          Radius.circular(10),
        ),
        Paint()
          ..color = i == 1 ? AppUi.accentGreen : color.withValues(alpha: 0.82),
      );
    }
    _drawSuccess(canvas, size, color, small: true);
  }

  void _drawSetup(Canvas canvas, Size size, Color color) {
    final x = size.width * 0.24;
    final y = size.height * 0.32;
    for (var i = 0; i < 3; i++) {
      final top = y + i * size.height * 0.16;
      canvas.drawCircle(
        Offset(x, top),
        size.width * 0.04,
        Paint()
          ..color = i < 2 ? AppUi.accentGreen : color.withValues(alpha: 0.18),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x + size.width * 0.08,
            top - size.height * 0.025,
            size.width * (0.38 + i * 0.08),
            size.height * 0.05,
          ),
          Radius.circular(99),
        ),
        Paint()..color = color.withValues(alpha: i < 2 ? 0.52 : 0.22),
      );
    }
  }

  void _drawSuccess(
    Canvas canvas,
    Size size,
    Color color, {
    bool small = false,
  }) {
    final center = Offset(
      size.width * (small ? 0.76 : 0.56),
      size.height * (small ? 0.32 : 0.46),
    );
    final radius = size.width * (small ? 0.08 : 0.14);
    canvas.drawCircle(center, radius, Paint()..color = AppUi.accentGreen);
    final check = Path()
      ..moveTo(center.dx - radius * 0.45, center.dy)
      ..lineTo(center.dx - radius * 0.12, center.dy + radius * 0.34)
      ..lineTo(center.dx + radius * 0.5, center.dy - radius * 0.36);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.18
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawError(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.55, size.height * 0.46);
    final radius = size.width * 0.14;
    canvas.drawCircle(center, radius, Paint()..color = AppUi.error);
    canvas.drawLine(
      center.translate(0, -radius * 0.45),
      center.translate(0, radius * 0.15),
      Paint()
        ..color = Colors.white
        ..strokeWidth = radius * 0.16
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      center.translate(0, radius * 0.48),
      radius * 0.08,
      Paint()..color = Colors.white,
    );
  }

  void _drawEmpty(Canvas canvas, Size size, Color color) {
    _drawDrop(
      canvas,
      Offset(size.width * 0.48, size.height * 0.46),
      size.width * 0.16,
      color.withValues(alpha: 0.55),
    );
    _drawMapPin(
      canvas,
      Offset(size.width * 0.66, size.height * 0.38),
      color.withValues(alpha: 0.7),
    );
  }

  void _drawMapPin(Canvas canvas, Offset center, Color color) {
    final r = center.dx * 0.12;
    final path = Path()
      ..moveTo(center.dx, center.dy + r * 1.55)
      ..cubicTo(
        center.dx - r,
        center.dy + r * 0.45,
        center.dx - r,
        center.dy - r * 0.8,
        center.dx,
        center.dy - r,
      )
      ..cubicTo(
        center.dx + r,
        center.dy - r * 0.8,
        center.dx + r,
        center.dy + r * 0.45,
        center.dx,
        center.dy + r * 1.55,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(center, r * 0.34, Paint()..color = Colors.white);
  }

  void _drawDrop(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..cubicTo(
        center.dx + radius,
        center.dy,
        center.dx + radius * 0.72,
        center.dy + radius,
        center.dx,
        center.dy + radius,
      )
      ..cubicTo(
        center.dx - radius * 0.72,
        center.dy + radius,
        center.dx - radius,
        center.dy,
        center.dx,
        center.dy - radius,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ExperiencePainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.role != role ||
        oldDelegate.isDark != isDark;
  }
}

class QuickGuide extends StatelessWidget {
  final AxoPose pose;
  final String message;

  const QuickGuide({
    super.key,
    this.pose = AxoPose.happy,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppUi.blueSoft,
          ),
          child: Icon(
            pose == AxoPose.success
                ? Icons.check_circle_rounded
                : pose == AxoPose.delivery
                ? Icons.local_shipping_rounded
                : Icons.water_drop_rounded,
            color: AppUi.bluePrimary,
            size: 24,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppUi.textSecondaryOf(context),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

@Deprecated('Use QuickGuide instead')
typedef AxoMiniGuide = QuickGuide;
