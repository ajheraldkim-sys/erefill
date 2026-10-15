import 'package:erefill/features/dashboard/customer/checkout_rules.dart';
import 'package:erefill/features/dashboard/customer/widgets/payment_method_selector.dart';
import 'package:erefill/features/dashboard/customer/widgets/payment_status_banner.dart';
import 'package:erefill/core/models/order_model.dart';
import 'package:erefill/core/widgets/rider_active_delivery_card.dart';
import 'package:erefill/core/widgets/refill_components.dart';
import 'package:erefill/models/cart_model.dart';
import 'package:erefill/core/services/payment_launch_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkout preflight', () {
    test('blocks empty refill orders before checkout', () {
      final result = CheckoutRules.validate(
        cart: CartProvider(),
        customerId: 'customer-id',
        isStationOpen: true,
        customerProfile: _completeProfile,
      );

      expect(result.canSubmit, isFalse);
      expect(
        result.message,
        'Your refill order is empty. Choose a water type first.',
      );
    });

    test('blocks missing delivery address and map location', () {
      final cart = CartProvider()..addItem('gallon', 'Water Gallon', 25);

      final missingAddress = CheckoutRules.validate(
        cart: cart,
        customerId: 'customer-id',
        isStationOpen: true,
        customerProfile: {
          'complete_address': '',
          'latitude': 9.33,
          'longitude': 125.98,
        },
      );
      expect(missingAddress.canSubmit, isFalse);
      expect(
        missingAddress.message,
        'Add your delivery address below to continue.',
      );

      final missingMapPin = CheckoutRules.validate(
        cart: cart,
        customerId: 'customer-id',
        isStationOpen: true,
        customerProfile: {'complete_address': 'Purok 1'},
      );
      expect(missingMapPin.canSubmit, isFalse);
      expect(
        missingMapPin.message,
        'Pin your map location on your delivery address to continue.',
      );

      final zeroCoordinatePin = CheckoutRules.validate(
        cart: cart,
        customerId: 'customer-id',
        isStationOpen: true,
        customerProfile: {
          'complete_address': 'Purok 1',
          'latitude': 0.0,
          'longitude': 0.0,
        },
      );
      expect(zeroCoordinatePin.canSubmit, isFalse);
      expect(
        zeroCoordinatePin.message,
        'Pin your map location on your delivery address to continue.',
      );
    });

    test('allows complete checkout details in test mode payment methods', () {
      final cart = CartProvider()..addItem('gallon', 'Water Gallon', 25);
      final result = CheckoutRules.validate(
        cart: cart,
        customerId: 'customer-id',
        isStationOpen: true,
        customerProfile: _completeProfile,
      );

      expect(result.canSubmit, isTrue);
      expect(result.message, isNull);
      expect(CheckoutRules.isOnlinePayment('gcash'), isTrue);
      expect(CheckoutRules.isOnlinePayment('maya'), isTrue);
      expect(CheckoutRules.isOnlinePayment('card'), isTrue);
      expect(CheckoutRules.isOnlinePayment('cod'), isFalse);
    });

    test('selected saved address replaces the delivery snapshot', () {
      final selected = CheckoutRules.useSavedAddress(_completeProfile, const {
        'complete_address': 'Market Road',
        'barangay': 'Poblacion',
        'town': 'Madrid',
        'landmark': 'Beside hall',
        'latitude': 9.21,
        'longitude': 125.88,
        'map_pin_town': 'Madrid',
      });

      expect(selected['complete_address'], 'Market Road');
      expect(selected['barangay'], 'Poblacion');
      expect(selected['latitude'], 9.21);
      expect(selected['longitude'], 125.88);
      expect(CheckoutRules.deliveryProfileIssue(selected), isNull);

      final mismatchedPinTown = {
        ...selected,
        'map_pin_town': 'Cantilan',
      };
      expect(
        CheckoutRules.deliveryProfileIssue(mismatchedPinTown),
        'Confirm this address on the map before using it for delivery.',
      );
    });
  });

  group('checkout payment availability', () {
    test('cash is available when backend returns no methods', () {
      final methods = CheckoutRules.normalizePaymentOptions(const []);

      expect(methods, hasLength(1));
      expect(methods.single.type, 'cod');
      expect(CheckoutRules.isPaymentAvailable('cod', methods), isTrue);
      expect(CheckoutRules.isPaymentAvailable('gcash', methods), isFalse);
    });

    test(
      'marks owner-configured wallets as selectable only when available',
      () {
        final methods = CheckoutRules.normalizePaymentOptions(const [
          {'type': 'cod', 'label': 'Cash', 'available': true},
          {'type': 'gcash', 'label': 'GCash', 'available': true},
          {
            'type': 'maya',
            'label': 'Maya',
            'available': false,
            'reason': 'Not set up by this station',
          },
        ]);

        expect(CheckoutRules.isPaymentAvailable('cod', methods), isTrue);
        expect(CheckoutRules.isPaymentAvailable('gcash', methods), isTrue);
        expect(CheckoutRules.isPaymentAvailable('maya', methods), isFalse);
        expect(methods.last.reason, 'Not set up by this station');
      },
    );

    testWidgets('shows GCash and Maya cards with their setup status', (
      tester,
    ) async {
      final methods = CheckoutRules.selectableMethods(
        CheckoutRules.normalizePaymentOptions(const [
          {'type': 'cod', 'label': 'Cash', 'available': true},
          {
            'type': 'gcash',
            'label': 'GCash',
            'available': false,
            'reason': 'Not set up by this station',
          },
          {
            'type': 'maya',
            'label': 'Maya',
            'available': false,
            'reason': 'Not set up by this station',
          },
        ]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentMethodSelector(
              selectedMethod: 'cod',
              methods: methods,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('Not set up by this station'), findsNWidgets(2));
    });

    test('standardPaymentMethods contains cod, gcash, maya, and card all available', () {
      final methods = CheckoutRules.standardPaymentMethods;
      expect(methods, hasLength(4));
      expect(methods.map((m) => m.type).toList(), ['cod', 'gcash', 'maya', 'card']);
      for (final m in methods) {
        expect(m.available, isTrue, reason: '${m.type} should be available by default');
      }
      expect(CheckoutRules.isPaymentAvailable('cod', methods), isTrue);
      expect(CheckoutRules.isPaymentAvailable('gcash', methods), isTrue);
      expect(CheckoutRules.isPaymentAvailable('maya', methods), isTrue);
      expect(CheckoutRules.isPaymentAvailable('card', methods), isTrue);
    });

    testWidgets('renders all 4 payment methods and allows selection', (tester) async {
      String selected = 'cod';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return PaymentMethodSelector(
                  selectedMethod: selected,
                  methods: CheckoutRules.standardPaymentMethods,
                  onSelected: (val) => setState(() => selected = val),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Cash on Delivery'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('Credit/Debit Card'), findsOneWidget);

      await tester.tap(find.text('GCash'));
      await tester.pumpAndSettle();
      expect(selected, 'gcash');

      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();
      expect(selected, 'maya');

      await tester.tap(find.text('Credit/Debit Card'));
      await tester.pumpAndSettle();
      expect(selected, 'card');
    });
  });

  group('payment retry banner', () {
    testWidgets('shows retry action for failed online payment', (tester) async {
      var retryTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentStatusBanner(
              order: const {
                'payment_method': 'gcash',
                'payment_status': 'failed',
              },
              onRetry: () => retryTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Payment failed'), findsOneWidget);
      expect(
        find.text('Your GCash payment did not complete. You can try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retryTapped, isTrue);
    });

    testWidgets('expired online payment is surfaced as retryable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentStatusBanner(
              order: const {
                'payment_method': 'card',
                'payment_status': 'expired',
              },
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('hides retry after payment is confirmed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusBanner(
              order: {'payment_method': 'maya', 'payment_status': 'success'},
            ),
          ),
        ),
      );

      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(find.text('Maya payment has been confirmed.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows Pay now action for pending online payment', (
      tester,
    ) async {
      var payTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentStatusBanner(
              order: const {
                'payment_method': 'gcash',
                'payment_status': 'pending',
              },
              onRetry: () => payTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.text('Pay now'), findsOneWidget);

      await tester.tap(find.text('Pay now'));
      expect(payTapped, isTrue);
    });

    testWidgets('shows loading spinner when isLoading is true and disables tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentStatusBanner(
              order: const {
                'payment_method': 'gcash',
                'payment_status': 'pending',
              },
              isLoading: true,
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
    });

    testWidgets('does not render for cash on delivery orders', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusBanner(
              order: {'payment_method': 'cod', 'payment_status': 'pending'},
            ),
          ),
        ),
      );

      expect(find.byType(PaymentStatusBanner), findsOneWidget);
      expect(find.text('Awaiting payment'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('PaymentLaunchService validation', () {
    test('returns false for empty URL', () async {
      final result = await PaymentLaunchService.launchCheckoutUrl('');
      expect(result, isFalse);
    });

    test('returns false for non-http/https URL', () async {
      final result = await PaymentLaunchService.launchCheckoutUrl(
        'file:///path/to/something',
      );
      expect(result, isFalse);
    });
  });

  group('order status display labels', () {
    test('maps known order statuses to customer-facing labels', () {
      expect(CheckoutRules.statusTitle('pending'), 'Order Placed');
      expect(CheckoutRules.statusTitle('accepted'), 'Accepted');
      expect(CheckoutRules.statusTitle('preparing'), 'Preparing');
      expect(CheckoutRules.statusTitle('ready_for_pickup'), 'Ready for Pickup');
      expect(
        CheckoutRules.statusTitle('assigned_to_rider'),
        'Assigned to Rider',
      );
      expect(CheckoutRules.statusTitle('out_for_delivery'), 'Out for Delivery');
      expect(CheckoutRules.statusTitle('delivered'), 'Delivered');
      expect(CheckoutRules.statusTitle('cancelled'), 'Cancelled');
    });

    test('shared order model exposes dispatch lifecycle states', () {
      final ready = OrderModel(id: 'one', status: 'ready_for_pickup');
      final assigned = OrderModel(id: 'two', status: 'assigned_to_rider');

      expect(ready.isReadyForPickup, isTrue);
      expect(ready.displayStatus, 'Ready for Pickup');
      expect(assigned.isAssignedToRider, isTrue);
      expect(assigned.displayStatus, 'Assigned to Rider');
    });
  });

  group('payment status clarity in cards', () {
    testWidgets('RiderActiveDeliveryCard displays PAID ONLINE for paid orders', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RiderActiveDeliveryCard(
              order: {
                'id': 'test-1',
                'status': 'out_for_delivery',
                'total_amount': 150.0,
                'payment_method': 'gcash',
                'payment_status': 'success',
              },
            ),
          ),
        ),
      );

      expect(find.text('PAID ONLINE'), findsOneWidget);
      expect(find.text('COLLECT CASH'), findsNothing);
    });

    testWidgets('RiderActiveDeliveryCard displays COLLECT CASH for cod orders', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RiderActiveDeliveryCard(
              order: {
                'id': 'test-2',
                'status': 'out_for_delivery',
                'total_amount': 200.0,
                'payment_method': 'cod',
                'payment_status': 'pending',
              },
            ),
          ),
        ),
      );

      expect(find.text('COLLECT CASH'), findsOneWidget);
      expect(find.text('PAID ONLINE'), findsNothing);
    });

    testWidgets(
      'ActiveOrderCard displays awaiting online payment for pending online orders',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ActiveOrderCard(
                order: {
                  'id': 'test-3',
                  'status': 'pending',
                  'total_amount': 250.0,
                  'payment_method': 'maya',
                  'payment_status': 'pending',
                },
                statusLabel: 'Pending',
              ),
            ),
          ),
        );

        expect(find.text('Awaiting online payment'), findsOneWidget);
      },
    );
  });
}

const _completeProfile = {
  'complete_address': 'Purok 1',
  'latitude': 9.3333,
  'longitude': 125.9833,
};
