import 'package:erefill/core/widgets/role_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const items = [
    RoleBottomNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
    ),
    RoleBottomNavItem(
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
      label: 'Stations',
    ),
    RoleBottomNavItem(
      icon: Icons.chat_outlined,
      activeIcon: Icons.chat,
      label: 'Messages',
    ),
    RoleBottomNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Orders',
    ),
    RoleBottomNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets(
      'five-role navigation fits at ${width.toInt()}px with larger text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(1.25),
              ),
              child: Scaffold(
                body: const SizedBox.expand(),
                bottomNavigationBar: RoleBottomNavBar(
                  currentIndex: 0,
                  onTap: (_) {},
                  items: items,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  const ownerItems = [
    RoleBottomNavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Overview',
    ),
    RoleBottomNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Orders',
      badgeCount: 120,
    ),
    RoleBottomNavItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      label: 'Stock & Credits',
      shortLabel: 'Stock',
    ),
    RoleBottomNavItem(
      icon: Icons.two_wheeler_outlined,
      activeIcon: Icons.two_wheeler,
      label: 'Riders',
    ),
    RoleBottomNavItem(
      icon: Icons.store_outlined,
      activeIcon: Icons.store,
      label: 'Station',
    ),
  ];

  for (final scale in [1.5, 1.8]) {
    for (final width in [320.0, 360.0]) {
      testWidgets(
        'owner labels are never pushed out of the bar at ${width.toInt()}px, ${scale}x text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: const SizedBox.expand(),
                  bottomNavigationBar: RoleBottomNavBar(
                    currentIndex: 2,
                    onTap: (_) {},
                    items: ownerItems,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final bar = tester.getRect(find.byType(NavigationBar));
          for (final item in ownerItems) {
            final label = find.text(item.shortLabel ?? item.label);
            expect(label, findsOneWidget);
            final r = tester.getRect(label);
            expect(
              r.bottom <= bar.bottom + 0.5 && r.top >= bar.top - 0.5,
              isTrue,
              reason: '${item.label} is clipped: $r outside $bar',
            );
          }
        },
      );
    }
  }
}
