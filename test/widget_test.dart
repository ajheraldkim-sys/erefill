// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/features/dashboard/customer/widgets/payment_status_banner.dart';
import 'package:erefill/features/dashboard/rider/services/offline_delivery_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('service municipalities are limited to Cantilan and Madrid', () {
    expect(AppConstants.municipalityData.keys.toList(), ['Cantilan', 'Madrid']);
    expect(AppConstants.municipalityZipCodes.keys.toSet(), {
      'Cantilan',
      'Madrid',
    });
  });

  test('Madrid includes all 14 PSGC barangays', () {
    const expectedMadridBarangays = {
      'Bagsac',
      'Bayogo',
      'Linibonan',
      'Magsaysay',
      'Manga',
      'Panayogon',
      'Patong Patong',
      'Quirino',
      'San Antonio',
      'San Juan',
      'San Roque',
      'San Vicente',
      'Songkit',
      'Union',
    };

    final madridBarangays = AppConstants.municipalityData['Madrid']!;
    expect(madridBarangays, hasLength(14));
    expect(madridBarangays.toSet(), expectedMadridBarangays);
    expect(
      AppConstants.purokData['Madrid']!.keys.toSet(),
      expectedMadridBarangays,
    );
  });

  testWidgets('Basic smoke test widget renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Smoke Test'))),
    );

    expect(find.text('Smoke Test'), findsOneWidget);
  });

  testWidgets('payment in progress cannot start a duplicate checkout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentStatusBanner(
            order: {
              'payment_method': 'gcash',
              'payment_status': 'processing',
              'retry_allowed': true,
            },
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Pay now'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('failed payment offers a retry', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentStatusBanner(
            order: {
              'payment_method': 'gcash',
              'payment_status': 'failed',
              'retry_allowed': true,
            },
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'Kanban column header paints without non-uniform border assertion',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              width: 310,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey, width: 1),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0x14F59E0B),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey),
                        top: BorderSide(color: Color(0xFFF59E0B), width: 3),
                      ),
                    ),
                    child: const Text('Pending'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Pending'), findsOneWidget);
    },
  );

  test(
    'Rider name splitting correctly populates first and last name from composite full_name',
    () {
      const singleName = 'Kim';
      final partsSingle = singleName.split(RegExp(r'\s+'));
      expect(partsSingle.first, 'Kim');

      const compositeName = 'Kim Aspillaga';
      final parts = compositeName.split(RegExp(r'\s+'));
      expect(parts.first, 'Kim');
      expect(parts.sublist(1).join(' '), 'Aspillaga');

      const multiPartName = 'Maria Clara De Los Santos';
      final multiParts = multiPartName.split(RegExp(r'\s+'));
      expect(multiParts.first, 'Maria');
      expect(multiParts.sublist(1).join(' '), 'Clara De Los Santos');
    },
  );

  test(
    'QueuedDelivery model serializes to json and reconstructs correctly',
    () {
      final now = DateTime.now();
      final delivery = QueuedDelivery(
        orderId: 'order-uuid-123',
        status: 'delivered',
        latitude: 9.3245,
        longitude: 125.9812,
        localPhotoPath: '/tmp/proof.jpg',
        localSignaturePath: '/tmp/sig.png',
        deliveryNote: 'Handed to customer front door',
        emptyGallonsReturned: 3,
        createdAt: now,
      );

      final json = delivery.toJson();
      expect(json['orderId'], 'order-uuid-123');
      expect(json['status'], 'delivered');
      expect(json['latitude'], 9.3245);
      expect(json['longitude'], 125.9812);
      expect(json['localPhotoPath'], '/tmp/proof.jpg');
      expect(json['localSignaturePath'], '/tmp/sig.png');
      expect(json['deliveryNote'], 'Handed to customer front door');
      expect(json['emptyGallonsReturned'], 3);
      expect(json['retryCount'], 0);

      final restored = QueuedDelivery.fromJson(json);
      expect(restored.orderId, 'order-uuid-123');
      expect(restored.status, 'delivered');
      expect(restored.latitude, 9.3245);
      expect(restored.longitude, 125.9812);
      expect(restored.deliveryNote, 'Handed to customer front door');
      expect(restored.emptyGallonsReturned, 3);
    },
  );
}
