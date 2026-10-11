import 'package:flutter/material.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = AppUi.surfaceOf(context);
    final indicatorColor = isDark
        ? AppUi.bluePrimary.withValues(alpha: 0.22)
        : AppUi.blueSoft;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: AppUi.bluePrimary.withValues(alpha: isDark ? 0.12 : 0.06),
                blurRadius: 12,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
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
                    color: selected
                        ? AppUi.bluePrimary
                        : AppUi.textSecondaryOf(context),
                    size: 22,
                  );
                }),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    color: selected
                        ? AppUi.bluePrimary
                        : AppUi.textSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: currentIndex,
                onDestinationSelected: onTap,
                height: 64,
                elevation: 0,
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                indicatorColor: indicatorColor,
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
                      label: item.label,
                    ),
                ],
              ),
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
    final child = Icon(icon, size: 22);

    if (badgeCount <= 0) return child;

    return RepaintBoundary(
      child: Badge(
        label: Text(badgeCount > 9 ? '9+' : '$badgeCount'),
        backgroundColor: AppUi.error,
        child: child,
      ),
    );
  }
}
