import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Wraps any bottom navigation bar to smoothly slide down out of view when scrolling down,
/// and slide back up into view when scrolling up or near scroll boundaries.
class AutoHidingBottomBar extends StatelessWidget {
  final Widget child;
  final bool isVisible;
  final Duration duration;

  const AutoHidingBottomBar({
    super.key,
    required this.child,
    required this.isVisible,
    this.duration = const Duration(milliseconds: 240),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: duration,
      offset: isVisible ? Offset.zero : const Offset(0, 1.4),
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        duration: duration,
        opacity: isVisible ? 1.0 : 0.0,
        curve: Curves.easeInOut,
        child: IgnorePointer(
          ignoring: !isVisible,
          child: ExcludeFocus(
            excluding: !isVisible,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Helper function to handle [ScrollNotification]s and toggle bottom navigation bar visibility.
/// Hides the navigation bar when scrolling down, and ONLY shows it when scrolling up or at the very top.
/// Never reveals automatically at the bottom boundary.
bool onBottomBarScrollNotification({
  required ScrollNotification notification,
  required bool isCurrentlyVisible,
  required ValueChanged<bool> onVisibilityChanged,
}) {
  if (notification.metrics.axis == Axis.vertical) {
    // 1. User gesture direction changed (drag started / reversed)
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse) {
        // Scrolling down: hide immediately
        if (isCurrentlyVisible) onVisibilityChanged(false);
      } else if (notification.direction == ScrollDirection.forward) {
        // Scrolling up: reveal
        if (!isCurrentlyVisible) onVisibilityChanged(true);
      }
    }

    // 2. Continuous scroll updates for immediate responsiveness
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta != null && delta.abs() > 2) {
        if (delta > 0) {
          // Scrolling down: hide immediately
          if (isCurrentlyVisible) onVisibilityChanged(false);
        } else if (delta < 0) {
          // Scrolling up: reveal immediately
          if (!isCurrentlyVisible) onVisibilityChanged(true);
        }
      }
    }

    // 3. Only reveal when user has scrolled all the way back to the very top (pixels <= 0)
    // Never auto-reveal near the bottom boundary (extentAfter < 20)
    if (notification.metrics.pixels <= 0) {
      if (!isCurrentlyVisible) onVisibilityChanged(true);
    }
  }
  return false;
}
