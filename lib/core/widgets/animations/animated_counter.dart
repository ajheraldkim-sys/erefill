import 'package:flutter/material.dart';

/// Smooth numeric roll animation for metrics, revenue, and telemetry cards.
///
/// Rolls from initial value to [value] over [duration] using [curve].
class AnimatedCounter extends StatelessWidget {
  final num value;
  final Duration duration;
  final Curve curve;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final int fractionDigits;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 800),
    this.curve = Curves.easeOutCubic,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.fractionDigits = 0,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (context, animatedValue, child) {
        final formattedNumber = fractionDigits > 0
            ? animatedValue.toStringAsFixed(fractionDigits)
            : animatedValue.round().toString();
        return Text(
          '$prefix$formattedNumber$suffix',
          style: style,
        );
      },
    );
  }
}

