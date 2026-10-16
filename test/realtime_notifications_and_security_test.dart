import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/role_bottom_nav_bar.dart';

void main() {
  group('Real-Time Notification Badges in RoleBottomNavBar', () {
    const homeItem = RoleBottomNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    );

    testWidgets('badgeCount <= 0 renders icon with no badge label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: RoleBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                homeItem,
                RoleBottomNavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_rounded,
                  label: 'Chat',
                  badgeCount: 0,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    });

    testWidgets('badgeCount = 1 renders "1" inside red Badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: RoleBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                homeItem,
                RoleBottomNavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_rounded,
                  label: 'Chat',
                  badgeCount: 1,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.backgroundColor, equals(AppUi.error));
    });

    testWidgets('badgeCount = 5 renders "5"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: RoleBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                homeItem,
                RoleBottomNavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: 'Orders',
                  badgeCount: 5,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('badgeCount > 99 renders "99+"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: RoleBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                homeItem,
                RoleBottomNavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_rounded,
                  label: 'Chat',
                  badgeCount: 125,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('125'), findsNothing);
    });
  });
}
