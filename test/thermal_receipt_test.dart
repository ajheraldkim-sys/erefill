import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/services/receipt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Thermal Receipt & ESC/POS Mobile Printer Engine', () {
    final sampleOrder = {
      'id': 'abc12345-6789-0000-1111-222233334444',
      'created_at': '2026-10-12T14:30:00Z',
      'station_name': 'Madrid Pure Spring',
      'customer_name': 'Maria Santos',
      'customer_address': 'Purok 1, Madrid, Surigao del Sur',
      'subtotal': 120.0,
      'delivery_fee': 25.0,
      'total_amount': 145.0,
      'payment_method': 'cod',
      'order_items': [
        {
          'product_name': 'Mineral Water Refill',
          'quantity': 4,
          'total_price': 120.0,
        }
      ],
    };

    test('generateThermalReceiptPdf creates valid PDF bytes for 58mm roll', () async {
      final bytes = await ReceiptService.generateThermalReceiptPdf(
        order: sampleOrder,
        is58mm: true,
      );

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(100));
      // PDF file magic header
      expect(bytes.sublist(0, 4), equals(utf8.encode('%PDF')));
    });

    test('generateThermalReceiptPdf creates valid PDF bytes for 80mm roll', () async {
      final bytes = await ReceiptService.generateThermalReceiptPdf(
        order: sampleOrder,
        is58mm: false,
      );

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(100));
      expect(bytes.sublist(0, 4), equals(utf8.encode('%PDF')));
    });

    test('generateEscPosBytes creates valid ESC/POS byte sequence with POS commands', () {
      final escPos = ReceiptService.generateEscPosBytes(
        order: sampleOrder,
        is58mm: true,
      );

      expect(escPos, isNotNull);
      expect(escPos.length, greaterThan(50));

      // ESC @ (Initialize printer): 0x1B, 0x40
      expect(escPos[0], equals(0x1B));
      expect(escPos[1], equals(0x40));

      // Checks that station name is encoded in bytes
      final asString = String.fromCharCodes(escPos);
      expect(asString.toUpperCase(), contains('MADRID PURE SPRING'));
      expect(asString, contains('Maria Santos'));
      expect(asString, contains('TOTAL:'));

      // Ends with paper cut command: GS V 66 0 (0x1D, 0x56, 0x42, 0x00)
      final len = escPos.length;
      expect(escPos[len - 4], equals(0x1D));
      expect(escPos[len - 3], equals(0x56));
      expect(escPos[len - 2], equals(0x42));
      expect(escPos[len - 1], equals(0x00));
    });
  });
}

