import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/features/dashboard/owner/widgets/new_order_alert_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _order(String method, String paymentStatus) => {
  'id': 'abcdef12-0000-0000-0000-000000000000',
  'status': 'pending',
  'customer_name': 'Juan',
  'customer_address': 'Purok 1',
  'payment_method': method,
  'payment_status': paymentStatus,
  'total_amount': 45,
  'created_at': DateTime.now().toIso8601String(),
};

Future<VoidCallback?> _acceptHandler(
  WidgetTester tester,
  Map<String, dynamic> order,
) async {
  tester.view.physicalSize = const Size(1440, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: NewOrderAlertSheet(order: order, onAccept: (_) async {}),
      ),
    ),
  );
  await tester.pump();
  final button = tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: find.text('Accept Order'),
      matching: find.bySubtype<ButtonStyleButton>(),
    ),
  );
  // Unmount to stop the sheet's countdown and haptic timers.
  await tester.pumpWidget(const SizedBox());
  return button.onPressed;
}

void main() {
  testWidgets('unpaid online order cannot be accepted from the alert', (
    tester,
  ) async {
    expect(await _acceptHandler(tester, _order('gcash', 'pending')), isNull);
  });

  testWidgets('COD and paid online orders can be accepted from the alert', (
    tester,
  ) async {
    expect(await _acceptHandler(tester, _order('cod', 'pending')), isNotNull);
    expect(await _acceptHandler(tester, _order('qrph', 'success')), isNotNull);
  });
}
