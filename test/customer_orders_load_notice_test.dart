import 'package:erefill/features/dashboard/customer/widgets/customer_orders_load_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains cached orders may be stale and retries on request', (
    tester,
  ) async {
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerOrdersLoadNotice(
            hasSavedOrders: true,
            onRetry: () => retryCount++,
          ),
        ),
      ),
    );

    expect(find.text('Showing saved orders'), findsOneWidget);
    expect(find.textContaining('may be out of date'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retryCount, 1);
  });

  testWidgets('clearly reports a failed load when no saved orders exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerOrdersLoadNotice(hasSavedOrders: false, onRetry: () {}),
        ),
      ),
    );

    expect(find.text('Could not load your orders'), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsOneWidget);
  });
}
