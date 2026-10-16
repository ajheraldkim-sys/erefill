import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/services/receipt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptService tests', () {
    test('generateReceiptPdf creates valid non-empty PDF byte array', () async {
      final order = {
        'id': 'abc12345-6789-0000-0000-1234567890ab',
        'status': 'delivered',
        'customer_name': 'Juan Dela Cruz',
        'customer_phone': '09123456789',
        'customer_address': 'Poblacion, Madrid, Surigao del Sur',
        'customer_barangay': 'Poblacion',
        'station_name': 'Crystal Clear Water Station',
        'subtotal': 150.0,
        'delivery_fee': 20.0,
        'total_amount': 170.0,
        'payment_method': 'cod',
        'payment_status': 'success',
        'created_at': '2026-10-08T08:30:00Z',
      };

      final items = [
        {
          'product_name': 'Mineral Water (Round Gallon)',
          'quantity': 3,
          'price_at_purchase': 50.0,
          'subtotal': 150.0,
        },
      ];

      final pdfBytes = await ReceiptService.generateReceiptPdf(
        order: order,
        items: items,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      // PDF header starts with '%PDF'
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, equals('%PDF'));
    });

    test(
      'generateReceiptPdf handles missing items and fallbacks gracefully',
      () async {
        final order = {
          'id': '11111111-2222-3333-4444-555555555555',
          'status': 'pending',
          'total_amount': 50.0,
          'payment_method': 'gcash',
          'payment_status': 'pending',
        };

        final pdfBytes = await ReceiptService.generateReceiptPdf(
          order: order,
          items: [],
        );

        expect(pdfBytes, isNotNull);
        expect(pdfBytes.isNotEmpty, isTrue);
        final header = String.fromCharCodes(pdfBytes.take(4));
        expect(header, equals('%PDF'));
      },
    );

    test(
      'generateReceiptPdf includes a frozen delivery receipt snapshot',
      () async {
        final receipt = {
          'receipt_number': 'ER-2026-ABC12345',
          'delivery_status': 'Delivered',
          'rider_name': 'Rider Name',
          'delivered_at': '2026-10-16T11:30:00Z',
          'delivery_address': 'Poblacion, Madrid',
          'amount_paid': 0.0,
          'outstanding_balance': 170.0,
        };
        final pdfBytes = await ReceiptService.generateReceiptPdf(
          order: {
            'id': 'abc12345-6789-0000-0000-1234567890ab',
            'status': 'delivered',
            'customer_name': 'Juan Dela Cruz',
            'station_name': 'Crystal Clear Water Station',
            'subtotal': 150.0,
            'delivery_fee': 20.0,
            'total_amount': 170.0,
            'payment_method': 'cod',
            'payment_status': 'pending',
          },
          items: const [
            {
              'product_name': 'Mineral Water',
              'quantity': 3,
              'unit_price': 50.0,
              'total_price': 150.0,
            },
          ],
          deliveryReceipt: receipt,
        );

        expect(String.fromCharCodes(pdfBytes.take(4)), equals('%PDF'));
        expect(pdfBytes.length, greaterThan(100));
      },
    );
  });
}
