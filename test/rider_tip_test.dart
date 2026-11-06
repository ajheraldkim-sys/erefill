import 'package:erefill/features/dashboard/customer/checkout_rules.dart';
import 'package:erefill/features/dashboard/customer/services/checkout_order_service.dart';
import 'package:erefill/features/dashboard/customer/widgets/tip_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CheckoutRules tips', () {
    test('normalizeTip rounds to pesos and caps at 500', () {
      expect(CheckoutRules.normalizeTip(19.6), 20);
      expect(CheckoutRules.normalizeTip(-5), 0);
      expect(CheckoutRules.normalizeTip(900), 500);
    });

    test('order total adds the tip after any voucher discount', () {
      final total = CheckoutRules.calculateOrderTotal(
        subtotal: 40,
        deliveryFee: 20,
        platformFee: 1,
        voucherDiscount: 100,
        tip: 20,
      );
      // Voucher can zero the order but never eats the rider's tip.
      expect(total, 20);
    });

    test('total without tip is unchanged', () {
      expect(
        CheckoutRules.calculateOrderTotal(
          subtotal: 40,
          deliveryFee: 20,
          platformFee: 1,
          voucherDiscount: 0,
        ),
        61,
      );
    });
  });

  test('order request sends tip_amount', () {
    final req = CheckoutOrderRequest(
      customerId: 'c',
      stationId: 's',
      stationName: 'S',
      customerName: 'C',
      profile: const {'latitude': 9.0, 'longitude': 126.0},
      paymentMethod: 'cod',
      items: const [],
      subtotal: 40,
      deliveryFee: 0,
      deliveryDistanceKm: 0.5,
      deliveryRatePerKm: 10,
      totalAmount: 60,
      voucherId: null,
      containerOption: 'swap',
      scheduleForNextOpen: false,
      stationOpeningTime: null,
      userNotes: '',
      tipAmount: 20,
    );
    expect(req.toOrderData('k')['tip_amount'], 20);
  });

  group('TipSelector', () {
    Future<List<double>> pump(WidgetTester tester, {double value = 0}) async {
      final picked = <double>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TipSelector(value: value, onChanged: picked.add),
        ),
      ));
      return picked;
    }

    testWidgets('offers no tip and preset amounts', (tester) async {
      await pump(tester);
      for (final label in ['No tip', '₱10', '₱20', '₱50', 'Other']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('100% goes to your rider'), findsOneWidget);
    });

    testWidgets('tapping a preset picks it', (tester) async {
      final picked = await pump(tester);
      await tester.tap(find.text('₱20'));
      expect(picked, [20]);
    });

    testWidgets('custom amount is capped at 500', (tester) async {
      final picked = await pump(tester);
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '800');
      await tester.tap(find.text('Add tip'));
      await tester.pumpAndSettle();
      expect(picked.last, 500);
    });
  });
}
