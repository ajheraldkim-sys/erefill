import 'package:erefill/core/utils/money.dart';
import 'package:erefill/features/dashboard/customer/checkout_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors supabase/tests/whole_peso_pricing_test.sql so the checkout preview
// always shows what the server will charge.
void main() {
  group('whole-peso pricing', () {
    test('subtotal rounds to whole pesos', () {
      expect(CheckoutRules.roundSubtotal(119.6), 120);
      expect(CheckoutRules.roundSubtotal(19.4), 19);
    });

    test('delivery fee rounds to whole pesos', () {
      expect(
        CheckoutRules.calculateDeliveryFee(distanceKm: 2.3, ratePerKm: 2),
        5,
      );
    });

    test('service fee keeps its centavos', () {
      expect(
        CheckoutRules.calculatePlatformFee(
          subtotal: 120,
          deliveryFee: 20,
          enabled: true,
          percent: 1,
          fixed: 0,
        ),
        1.40,
      );
      expect(
        CheckoutRules.calculatePlatformFee(
          subtotal: 25,
          deliveryFee: 0,
          enabled: true,
          percent: 1,
          fixed: 0,
        ),
        0.25,
      );
    });

    test('voucher discount rounds to whole pesos', () {
      expect(
        CheckoutRules.calculateOrderTotal(
          subtotal: 120,
          deliveryFee: 20,
          platformFee: 1.40,
          voucherDiscount: 10.5,
        ),
        closeTo(130.40, 1e-9),
      );
    });

    test('total never goes below zero', () {
      expect(
        CheckoutRules.calculateOrderTotal(
          subtotal: 20,
          deliveryFee: 5,
          platformFee: 0.25,
          voucherDiscount: 100,
        ),
        0,
      );
    });
  });

  group('formatPeso', () {
    test('whole amounts drop the decimals', () {
      expect(formatPeso(120), '₱120');
      expect(formatPeso(0), '₱0');
      expect(formatPeso(null), '₱0');
    });

    test('amounts with centavos keep two decimals', () {
      expect(formatPeso(1.4), '₱1.40');
      expect(formatPeso(141.4), '₱141.40');
      expect(formatPeso(1234.5), '₱1,234.50');
    });

    test('whole: true always rounds to pesos', () {
      expect(formatPeso(1234.5, whole: true), '₱1,235');
    });
  });

  group('formatAmount (no symbol, for PDF receipts and exports)', () {
    test('follows the same whole-peso rule', () {
      expect(formatAmount(120), '120');
      expect(formatAmount(141.4), '141.40');
      expect(formatAmount(1234.5), '1,234.50');
      expect(formatAmount(null), '0');
    });
  });
}
