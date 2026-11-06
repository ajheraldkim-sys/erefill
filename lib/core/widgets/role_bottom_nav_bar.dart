import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';

class RoleBottomNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Shown instead of [label] on narrow screens (the tooltip and screen
  /// reader still use [label]).
  final String? shortLabel;
  final int badgeCount;

  const RoleBottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.shortLabel,
    this.badgeCount = 0,
  });
}

/// Docked Material 3 bottom navigation for role dashboards.
///
/// Full-width with a hairline top border (no floating pill or shadows) so
/// the customer, owner and rider apps share one calm, predictable bar.
///
/// Labels follow the user's text size up to [maxTextScale] (pages keep the
/// full scale) and the bar grows with them, so nothing is pushed off-screen.
class RoleBottomNavBar extends StatelessWidget {
  /// Largest text scale used inside the bar.
  static const double maxTextScale = 1.3;

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<RoleBottomNavItem> items;

  const RoleBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 380;
    final isVeryCompact = width < 340;
    // Each destination gets an equal share; long labels switch to their
    // short form when that share is tight.
    final useShortLabels = width / items.length < 76;
    const labelSize = 12.0;
    final labels = [
      for (final item in items)
        useShortLabels ? (item.shortLabel ?? item.label) : item.label,
    ];
    // Grow labels with the user's text size, but never past what keeps the
    // widest (bold, selected) label on one line in its slot.
    final userScale =
        MediaQuery.textScalerOf(context).scale(labelSize) / labelSize;
    final slot = width / items.length - 8;
    // Measure in the app's real label font so the fit check matches the screen.
    final measureStyle =
        (Theme.of(context).textTheme.labelMedium ?? const TextStyle()).copyWith(
          fontSize: labelSize,
          fontWeight: FontWeight.w700,
        );
    var widest = 0.0;
    var lineHeight = labelSize * 1.4;
    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(text: l, style: measureStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, tp.width);
      lineHeight = math.max(lineHeight, tp.height);
      tp.dispose();
    }
    // Normal (1x) labels fit thanks to [shortLabel]; only growth is capped.
    final fitScale = widest > 0 ? math.max(slot / widest, 1.0) : maxTextScale;
    final scale = math.min(math.min(userScale, maxTextScale), fitScale);
    // If a label still cannot fit on one line (unusual fonts or a label with
    // no short form), make room for a second line instead of clipping it.
    final lines = widest * scale > slot ? 2 : 1;
    final barHeight =
        (isVeryCompact ? 62.0 : 66.0) +
        lineHeight * (scale - 1) +
        (lines - 1) * lineHeight * scale;
    final isDark = AppUi.isDark(context);
    final primary = isDark ? AppUi.accentCyan : AppUi.bluePrimary;
    final indicatorColor = isDark
        ? AppUi.accentCyan.withValues(alpha: 0.16)
        : AppUi.blueSoft;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(top: BorderSide(color: AppUi.borderOf(context))),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            indicatorColor: indicatorColor,
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                color: selected ? primary : AppUi.textSecondaryOf(context),
                size: isCompact ? 22 : 24,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                color: selected ? primary : AppUi.textSecondaryOf(context),
                fontSize: labelSize,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              );
            }),
          ),
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) {
                if (index != currentIndex) {
                  HapticFeedback.selectionClick();
                }
                onTap(index);
              },
              height: barHeight,
              elevation: 0,
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: indicatorColor,
              animationDuration: AppUi.motion(context),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final item in items)
                  NavigationDestination(
                    icon: _NavIcon(
                      icon: item.icon,
                      badgeCount: item.badgeCount,
                    ),
                    selectedIcon: _NavIcon(
                      icon: item.activeIcon,
                      badgeCount: item.badgeCount,
                    ),
                    label: useShortLabels
                        ? (item.shortLabel ?? item.label)
                        : item.label,
                    tooltip: item.badgeCount > 0
                        ? '${item.label}, ${item.badgeCount} new'
                        : item.label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final int badgeCount;

  const _NavIcon({required this.icon, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon);

    if (badgeCount <= 0) return child;

    final badgeText = badgeCount > 99 ? '99+' : '$badgeCount';

    return RepaintBoundary(
      child: Semantics(
        label: '$badgeCount unread notifications',
        child: Badge(
          label: Text(
            badgeText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          backgroundColor: AppUi.error,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: child,
        ),
      ),
    );
  }
}
