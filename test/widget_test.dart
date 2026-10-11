// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/features/dashboard/customer/widgets/payment_status_banner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('service municipalities are limited to Cantilan and Madrid', () {
    expect(AppConstants.municipalityData.keys.toList(), ['Cantilan', 'Madrid']);
    expect(AppConstants.municipalityZipCodes.keys.toSet(), {
      'Cantilan',
      'Madrid',
    });
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

  testWidgets('Kanban column header paints without non-uniform border assertion', (
    WidgetTester tester,
  ) async {
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
  });
}
