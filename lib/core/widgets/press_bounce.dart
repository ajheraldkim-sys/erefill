import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable tactile spring micro-interaction wrapper.
///
/// Gives cards, buttons, and tiles a responsive, high-end physical bounce
/// feel (scaling to [pressedScale] on tap down, and smoothly springing back
/// on release) with optional tactile haptic feedback.
class PressBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;
  final Duration reverseDuration;
  final bool enableHaptics;
  final HitTestBehavior behavior;

  const PressBounce({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.975,
    this.duration = const Duration(milliseconds: 90),
    this.reverseDuration = const Duration(milliseconds: 140),
    this.enableHaptics = true,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<PressBounce> createState() => _PressBounceState();
}

class _PressBounceState extends State<PressBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.reverseDuration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: widget.behavior,
        onPointerDown: (_) {
          if (widget.onTap != null || widget.onLongPress != null) {
            _controller.forward();
          }
        },
        onPointerUp: (_) {
          _controller.reverse();
        },
        onPointerCancel: (_) {
          _controller.reverse();
        },
        child: GestureDetector(
          behavior: widget.behavior,
          onTap: () {
            if (widget.enableHaptics) {
              HapticFeedback.lightImpact();
            }
            widget.onTap?.call();
          },
          onLongPress: () {
            if (widget.enableHaptics) {
              HapticFeedback.mediumImpact();
            }
            widget.onLongPress?.call();
          },
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
