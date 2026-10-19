import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';

class RoleBottomNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badgeCount;

  const RoleBottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// Docked Material 3 bottom navigation for role dashboards.
///
/// Full-width with a hairline top border (no floating pill or shadows) so
/// the customer, owner and rider apps share one calm, predictable bar.
class RoleBottomNavBar extends StatelessWidget {
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
                fontSize: isVeryCompact ? 11 : 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) {
              if (index != currentIndex) {
                HapticFeedback.selectionClick();
              }
              onTap(index);
            },
            height: isVeryCompact ? 60 : 64,
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
                  icon: _NavIcon(icon: item.icon, badgeCount: item.badgeCount),
                  selectedIcon: _NavIcon(
                    icon: item.activeIcon,
                    badgeCount: item.badgeCount,
                  ),
                  label: item.label,
                  tooltip: item.badgeCount > 0
                      ? '${item.label}, ${item.badgeCount} new'
                      : item.label,
                ),
            ],
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
              fontSize: 11,
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
