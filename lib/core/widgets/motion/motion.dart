import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants.dart';

/// Fades and slides its child up into place once, after [delay]. Use a small
/// increasing delay on sibling sections for a staggered entrance. Shows the
/// child immediately when reduced motion is on.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppUi.motionSlow,
    this.offset = 16,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Starting distance below the final position, in logical pixels.
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _delayTimer;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppUi.reduceMotion(context)) {
      _delayTimer?.cancel();
      _controller.value = 1;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * widget.offset),
          child: child,
        ),
      ),
    );
  }
}

/// Scales its child down slightly while pressed, as feedback for a tap.
/// It does not handle the tap itself; wrap a button or an InkWell.
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed && mounted) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !AppUi.reduceMotion(context);
    return Listener(
      onPointerDown: active ? (_) => _set(true) : null,
      onPointerUp: active ? (_) => _set(false) : null,
      onPointerCancel: active ? (_) => _set(false) : null,
      child: AnimatedScale(
        scale: _pressed && active ? widget.pressedScale : 1,
        duration: AppUi.motionFast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
