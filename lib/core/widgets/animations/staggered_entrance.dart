import 'package:flutter/material.dart';

/// Staggered slide and fade-in entry animation for list items and cards.
class StaggeredEntrance extends StatefulWidget {
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
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, widget.offsetDistance / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    // Stagger delay based on index (capped at 10 items to prevent long waits)
    final effectiveIndex = widget.index.clamp(0, 10);
    Future.delayed(widget.delayPerItem * effectiveIndex, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
    );
  }
}

