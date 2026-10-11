import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/widgets/account/account_ui.dart';
import 'package:erefill/core/water_types.dart';
import 'package:erefill/features/account/saved_addresses_screen.dart';

void main() {
  group('Customer Profile Tiles and Account Group Tests', () {
    testWidgets('AccountNavTile renders custom titleColor and iconColor for destructive actions',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountGroup(
              children: [
                AccountNavTile(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFEF4444),
                  title: 'Sign out',
                  titleColor: const Color(0xFFEF4444),
                  subtitle: 'Log out of your account on this device',
                  onTap: () => tapped = true,
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
          ),
        ),
      );

      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Log out of your account on this device'), findsOneWidget);
      expect(find.text('Permanently remove your account and data'), findsOneWidget);

      final signOutText = tester.widget<Text>(find.text('Sign out'));
      expect(signOutText.style?.color, const Color(0xFFEF4444));

      final deleteText = tester.widget<Text>(find.text('Delete account'));
      expect(deleteText.style?.color, const Color(0xFFDC2626));

      await tester.tap(find.text('Sign out'));
      expect(tapped, isTrue);
    });

    testWidgets('AccountGroup renders single saved addresses tile in Delivery section',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountGroup(
              children: [
                const AccountNavTile(
                  icon: Icons.location_on_outlined,
                  title: 'Saved addresses',
                  subtitle: 'Manage or add delivery addresses',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Saved addresses'), findsOneWidget);
      expect(find.text('Manage or add delivery addresses'), findsOneWidget);
      expect(find.text('Delivery address'), findsNothing);
    });

    test('SavedAddressLaunchContext maps data back and forth properly', () {
      const launch = SavedAddressLaunchContext(
        address: 'Purok 2, Main Street',
        landmark: 'Near Water Tower',
        town: 'Prosperidad',
        barangay: 'Poblacion',
        latitude: 8.5,
        longitude: 125.9,
      );

      final map = launch.toMap();
      expect(map['address'], 'Purok 2, Main Street');
      expect(map['landmark'], 'Near Water Tower');
      expect(map['town'], 'Prosperidad');
      expect(map['barangay'], 'Poblacion');
      expect(map['latitude'], 8.5);
      expect(map['longitude'], 125.9);

      final reconstituted = SavedAddressLaunchContext.fromMap(map);
      expect(reconstituted.address, launch.address);
      expect(reconstituted.landmark, launch.landmark);
      expect(reconstituted.town, launch.town);
      expect(reconstituted.barangay, launch.barangay);
      expect(reconstituted.latitude, launch.latitude);
      expect(reconstituted.longitude, launch.longitude);
    });

    test('WaterTypes includes expected standard preferences', () {
      final names = WaterTypes.all.map((t) => t.name.toLowerCase()).toList();
      expect(names, contains('purified water'));
      expect(names, contains('mineral water'));
      expect(names, contains('alkaline water'));
    });
  });
}
