import 'package:flutter/material.dart';

import '../motion/motion.dart';

/// Staggered slide and fade-in entry animation for list items and cards.
/// Each [index] waits [delayPerItem] longer (capped at 10 items). Respects
/// reduced motion through [Reveal].
class StaggeredEntrance extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration delayPerItem;
  final Duration duration;
  final double offsetDistance;

  const StaggeredEntrance({
    super.key,
    required this.child,
    required this.index,
    this.delayPerItem = const Duration(milliseconds: 35),
    this.duration = const Duration(milliseconds: 320),
    this.offsetDistance = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return Reveal(
      delay: delayPerItem * index.clamp(0, 10),
      duration: duration,
      offset: offsetDistance,
      child: child,
    );
  }
}
