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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = AppUi.surfaceOf(context);
    final indicatorColor = isDark
        ? AppUi.bluePrimary.withValues(alpha: 0.22)
        : AppUi.blueSoft;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 8 : 16,
          isCompact ? 6 : 8,
          isCompact ? 8 : 16,
          isCompact ? 6 : 12,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(isCompact ? 24 : 30),
            border: Border.all(color: AppUi.borderOf(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: AppUi.bluePrimary.withValues(
                  alpha: isDark ? 0.12 : 0.04,
                ),
                blurRadius: 10,
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
                    fontSize: isVeryCompact ? 9 : (isCompact ? 10 : 11),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
                height: isVeryCompact ? 58 : (isCompact ? 60 : 64),
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
                      selectedIcon: _ActiveNavIcon(
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

class _ActiveNavIcon extends StatelessWidget {
  final IconData icon;
  final int badgeCount;

  const _ActiveNavIcon({required this.icon, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(icon),
      tween: Tween<double>(begin: 0.75, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: _NavIcon(icon: icon, badgeCount: badgeCount),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final int badgeCount;

  const _NavIcon({required this.icon, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    final child = Icon(
      icon,
      size: MediaQuery.sizeOf(context).width < 380 ? 20 : 22,
    );

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
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.2,
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
