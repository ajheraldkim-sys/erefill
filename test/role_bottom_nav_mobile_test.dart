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
}
