import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/dashboard/customer/checkout_rules.dart';
import 'package:erefill/features/account/saved_addresses_screen.dart';

void main() {
  group('Saved Addresses & Checkout Delivery Rules Tests', () {
    test('legacy saved address without map municipality needs confirmation', () {
      expect(
        savedAddressNeedsPinConfirmation({
          'town': 'Cantilan',
          'map_pin_town': null,
          'latitude': 9.3517,
          'longitude': 125.9784,
        }),
        isTrue,
      );
    });

    test('saved address with matching confirmed map pin needs no confirmation', () {
      expect(
        savedAddressNeedsPinConfirmation({
          'town': 'Madrid',
          'map_pin_town': 'Madrid',
          'latitude': 9.2745,
          'longitude': 125.9643,
        }),
        isFalse,
      );
    });

    test('legacy address with null map_pin_town and valid coordinates is allowed', () {
      final profile = {
        'complete_address': 'Purok 3, Consuelo',
        'town': 'Cantilan',
        'barangay': 'Consuelo',
        'latitude': 9.3517,
        'longitude': 125.9784,
        'map_pin_town': null,
      };

      final issue = CheckoutRules.deliveryProfileIssue(profile);
      expect(issue, isNull);
      expect(CheckoutRules.isDeliveryProfileReady(profile), isTrue);
    });

    test('address with matching map_pin_town and valid coordinates is allowed', () {
      final profile = {
        'complete_address': 'Purok 1, Bagsac',
        'town': 'Madrid',
        'barangay': 'Bagsac',
        'latitude': 9.2745,
        'longitude': 125.9643,
        'map_pin_town': 'Madrid',
      };

      final issue = CheckoutRules.deliveryProfileIssue(profile);
      expect(issue, isNull);
      expect(CheckoutRules.isDeliveryProfileReady(profile), isTrue);
    });

    test('address with mismatched map_pin_town is blocked until confirmed', () {
      final profile = {
        'complete_address': 'Purok 2, Bugsukan',
        'town': 'Cantilan',
        'barangay': 'Bugsukan',
        'latitude': 9.2745,
        'longitude': 125.9643,
        'map_pin_town': 'Madrid', // Mismatched town
      };

      final issue = CheckoutRules.deliveryProfileIssue(profile);
      expect(issue, equals('Confirm this address on the map before using it for delivery.'));
      expect(CheckoutRules.isDeliveryProfileReady(profile), isFalse);
    });

    test('address with missing or zero coordinates is blocked with pin message', () {
      final profileZero = {
        'complete_address': 'Purok 1, Consuelo',
        'town': 'Cantilan',
        'barangay': 'Consuelo',
        'latitude': 0.0,
        'longitude': 0.0,
      };
      expect(
        CheckoutRules.deliveryProfileIssue(profileZero),
        equals('Pin your map location on your delivery address to continue.'),
      );

      final profileNull = {
        'complete_address': 'Purok 1, Consuelo',
        'town': 'Cantilan',
        'barangay': 'Consuelo',
        'latitude': null,
        'longitude': null,
      };
      expect(
        CheckoutRules.deliveryProfileIssue(profileNull),
        equals('Pin your map location on your delivery address to continue.'),
      );
    });

    test('address with empty complete_address is blocked with address prompt', () {
      final profile = {
        'complete_address': '   ',
        'town': 'Cantilan',
        'barangay': 'Consuelo',
        'latitude': 9.3517,
        'longitude': 125.9784,
      };
      expect(
        CheckoutRules.deliveryProfileIssue(profile),
        equals('Add your delivery address below to continue.'),
      );
    });

    test('missing profile is blocked with address prompt', () {
      expect(
        CheckoutRules.deliveryProfileIssue(null),
        equals('Add your delivery address below to continue.'),
      );
    });

    test('CheckoutRules.useSavedAddress overwrites profile location with saved address', () {
      final profile = {
        'id': 'cust-123',
        'full_name': 'Juan Dela Cruz',
        'town': 'Cantilan',
        'barangay': 'Consuelo',
        'complete_address': 'Old Address',
        'latitude': 9.35,
        'longitude': 125.97,
      };

      final savedAddress = {
        'id': 'addr-456',
        'complete_address': 'New Madrid Street',
        'barangay': 'Bagsac',
        'town': 'Madrid',
        'landmark': 'Near Market',
        'latitude': 9.27,
        'longitude': 125.96,
        'map_pin_town': 'Madrid',
      };

      final merged = CheckoutRules.useSavedAddress(profile, savedAddress);
      expect(merged['id'], equals('cust-123'));
      expect(merged['full_name'], equals('Juan Dela Cruz'));
      expect(merged['town'], equals('Madrid'));
      expect(merged['barangay'], equals('Bagsac'));
      expect(merged['complete_address'], equals('New Madrid Street'));
      expect(merged['landmark'], equals('Near Market'));
      expect(merged['latitude'], equals(9.27));
      expect(merged['longitude'], equals(125.96));
      expect(merged['map_pin_town'], equals('Madrid'));
    });

    test('SavedAddressLaunchContext serializes and deserializes cleanly', () {
      const launch = SavedAddressLaunchContext(
        address: '123 Main St',
        landmark: 'Near Chapel',
        town: 'Cantilan',
        barangay: 'Lininti-an',
        latitude: 9.352,
        longitude: 125.979,
      );

      final map = launch.toMap();
      final reconstructed = SavedAddressLaunchContext.fromMap(map);

      expect(reconstructed.address, equals(launch.address));
      expect(reconstructed.landmark, equals(launch.landmark));
      expect(reconstructed.town, equals(launch.town));
      expect(reconstructed.barangay, equals(launch.barangay));
      expect(reconstructed.latitude, equals(launch.latitude));
      expect(reconstructed.longitude, equals(launch.longitude));
    });
  });
}
