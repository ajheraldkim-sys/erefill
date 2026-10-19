import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/models/cart_model.dart';
import 'package:erefill/features/dashboard/owner/services/station_setup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StationSetupStatus Models & Parsing', () {
    test('StationSetupStatus.empty() has default incomplete state', () {
      final empty = StationSetupStatus.empty();
      expect(empty.isComplete, isFalse);
      expect(empty.percentage, 0);
      expect(empty.completedCount, 0);
      expect(empty.totalSections, 5);
      expect(empty.eligibleToOpen, isFalse);
      expect(empty.currentAvailability, 'incomplete_setup');
      expect(empty.isOpen, isFalse);
      expect(empty.missingFields.length, 5);

      expect(empty.profileSection.isComplete, isFalse);
      expect(empty.scheduleSection.isComplete, isFalse);
      expect(empty.deliverySection.isComplete, isFalse);
      expect(empty.productsSection.isComplete, isFalse);
      expect(empty.paymentsSection.isComplete, isFalse);
    });

    test('StationSetupStatus.fromRpc parses complete RPC payload correctly', () {
      final rpcJson = {
        'is_complete': true,
        'completed_count': 5,
        'total_sections': 5,
        'percentage': 100,
        'eligible_to_open': true,
        'current_availability': 'closed',
        'is_open': false,
        'missing_fields': <String>[],
        'sections': {
          'station_profile': {'complete': true, 'missing': null},
          'operating_schedule': {'complete': true, 'missing': null},
          'delivery_rules': {'complete': true, 'missing': null},
          'products_pricing': {'complete': true, 'missing': null},
          'payment_methods': {'complete': true, 'missing': null},
        },
      };

      final status = StationSetupStatus.fromRpc(rpcJson);
      expect(status.isComplete, isTrue);
      expect(status.completedCount, 5);
      expect(status.percentage, 100);
      expect(status.eligibleToOpen, isTrue);
      expect(status.isProfileComplete, isTrue);
      expect(status.isScheduleComplete, isTrue);
      expect(status.isDeliveryComplete, isTrue);
      expect(status.isProductsComplete, isTrue);
      expect(status.isPaymentsComplete, isTrue);
      expect(status.profileSection.badgeText, 'Complete');
      expect(status.scheduleSection.badgeText, 'Complete');
    });

    test('StationSetupStatus.fromRpc parses partial RPC payload correctly', () {
      final rpcJson = {
        'is_complete': false,
        'completed_count': 3,
        'total_sections': 5,
        'percentage': 60,
        'eligible_to_open': false,
        'current_availability': 'incomplete_setup',
        'is_open': false,
        'missing_fields': ['Operating Schedule', 'Products'],
        'sections': {
          'station_profile': {'complete': true, 'missing': null},
          'operating_schedule': {'complete': false, 'missing': 'Set operating hours and days'},
          'delivery_rules': {'complete': true, 'missing': null},
          'products_pricing': {'complete': false, 'missing': 'Add at least 1 orderable product'},
          'payment_methods': {'complete': true, 'missing': null},
        },
      };

      final status = StationSetupStatus.fromRpc(rpcJson);
      expect(status.isComplete, isFalse);
      expect(status.completedCount, 3);
      expect(status.percentage, 60);
      expect(status.eligibleToOpen, isFalse);
      expect(status.isProfileComplete, isTrue);
      expect(status.isScheduleComplete, isFalse);
      expect(status.isDeliveryComplete, isTrue);
      expect(status.isProductsComplete, isFalse);
      expect(status.isPaymentsComplete, isTrue);

      expect(status.scheduleSection.badgeText, 'Required');
      expect(status.productsSection.badgeText, 'Action needed');
    });
  });

  group('CartProvider Operations & Single-Station Rules', () {
    test('Initial cart is empty', () {
      final cart = CartProvider();
      expect(cart.items, isEmpty);
      expect(cart.totalItems, 0);
      expect(cart.totalAmount, 0.0);
      expect(cart.stationId, isNull);
    });

    test('setStation correctly updates station id and name', () {
      final cart = CartProvider();
      cart.setStation('station-001', 'AquaPure Station');
      expect(cart.stationId, 'station-001');
      expect(cart.stationName, 'AquaPure Station');
    });

    test('Adding and removing items updates totals and quantities', () {
      final cart = CartProvider();
      cart.setStation('station-001', 'AquaPure Station');

      // Add 5-gallon purified refill
      cart.addItem('item-1', 'Purified Water Refill', 25.0);
      expect(cart.totalItems, 1);
      expect(cart.totalAmount, 25.0);

      // Add empty container
      cart.addItem('item-2', 'Empty 5 Gallon Round Water Container', 180.0);
      expect(cart.totalItems, 2);
      expect(cart.totalAmount, 205.0);

      // Update quantity of refill to 3
      cart.updateQuantity('item-1', 3);
      expect(cart.totalItems, 4);
      expect(cart.totalAmount, (3 * 25.0) + 180.0);

      // Remove container
      cart.removeItem('item-2');
      expect(cart.totalItems, 3);
      expect(cart.totalAmount, 75.0);

      // Clear cart
      cart.clearCart();
      expect(cart.items, isEmpty);
      expect(cart.totalItems, 0);
      expect(cart.totalAmount, 0.0);
    });

    test('CartItem serialization works correctly', () {
      final item = CartItem(
        id: 'cap-1',
        name: 'Non spill Cap for 5 Gallon Round',
        price: 15.0,
        quantity: 4,
      );

      final json = item.toJson();
      expect(json['id'], 'cap-1');
      expect(json['name'], 'Non spill Cap for 5 Gallon Round');
      expect(json['price'], 15.0);
      expect(json['quantity'], 4);

      final reconstructed = CartItem.fromJson(json);
      expect(reconstructed.id, item.id);
      expect(reconstructed.name, item.name);
      expect(reconstructed.price, item.price);
      expect(reconstructed.quantity, item.quantity);
    });
  });
}

