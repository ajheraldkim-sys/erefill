import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/widgets/account/account_ui.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';

void main() {
  group('Profile and Station Consistency Tests', () {
    testWidgets('AccountIdentityBlock keeps identity clean without an edit action',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountIdentityBlock(
              name: 'Juan Dela Cruz',
              email: 'juan@example.com',
            ),
          ),
        ),
      );

      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(find.text('juan@example.com'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      // Verify Orders and Total spent stats are not rendered
      expect(find.text('Orders'), findsNothing);
      expect(find.text('Total spent'), findsNothing);
    });

    testWidgets('TabScreenHeroHeader provides close icon when configured for popup modal',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabScreenHeroHeader(
              title: 'Refill pricing',
              subtitle: 'Purified water',
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      // Verify the close icon is present for popups
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('Refill pricing'), findsOneWidget);
    });

    testWidgets('Station and About Owner separated navigation tiles render as distinct tiles',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const AccountSectionLabel('Station'),
                AccountGroup(
                  children: [
                    AccountNavTile(
                      icon: Icons.storefront_outlined,
                      title: 'Station details',
                      subtitle: 'Poblacion, San Francisco',
                      onTap: () {},
                    ),
                    AccountNavTile(
                      icon: Icons.person_outline_rounded,
                      title: 'About owner',
                      subtitle: 'John Doe',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('STATION'), findsOneWidget);
      expect(find.text('Station details'), findsOneWidget);
      expect(find.text('Poblacion, San Francisco'), findsOneWidget);
      expect(find.text('About owner'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      // Rating, Orders, Riders stats grid items should not be part of station
      expect(find.text('Rating'), findsNothing);
      expect(find.text('Riders'), findsNothing);
    });

    testWidgets('Unified Sign out and Delete account group renders consistently with correct styles',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const AccountSectionLabel('Account'),
                AccountGroup(
                  children: [
                    AccountNavTile(
                      icon: Icons.logout_rounded,
                      iconColor: const Color(0xFFEF4444),
                      title: 'Sign out',
                      titleColor: const Color(0xFFEF4444),
                      subtitle: 'Log out of your account on this device',
                      onTap: () {},
                    ),
                    AccountNavTile(
                      icon: Icons.delete_outline_rounded,
                      iconColor: const Color(0xFFDC2626),
                      title: 'Delete account',
                      titleColor: const Color(0xFFDC2626),
                      subtitle: 'Permanently remove your account and data',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Log out of your account on this device'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Permanently remove your account and data'), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });
  });
}
