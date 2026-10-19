import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/features/dashboard/owner/widgets/owner_order_detail_sheet.dart';
import 'package:erefill/features/dashboard/owner/widgets/owner_order_formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness {
  int itemLoads = 0;
  final updates = <String>[];
  final declines = <String>[];

  Widget sheet(Map<String, dynamic> order, {VoidCallback? onBuild}) =>
      OwnerOrderDetailSheet(
        order: order,
        riders: const [],
        isAssigning: false,
        loadItems: (id) async {
          itemLoads++;
          return [
            {
              'product_name': 'Mineral Water',
              'quantity': 2,
              'price_at_purchase': 20,
              'subtotal': 40,
            },
          ];
        },
        onUpdateStatus: (id, status) => updates.add('$id:$status'),
        onAssignRider:
            ({
              required String orderId,
              required String riderId,
              required String riderName,
            }) async {},
        onDecline: declines.add,
      );
}

Map<String, dynamic> _order(String status) => {
  'id': 'abcdef12-0000-0000-0000-000000000000',
  'status': status,
  'customer_name': 'Juan',
  'customer_address': 'Purok 1',
  'payment_method': 'cod',
  'payment_status': 'pending',
  'total_amount': 45,
  'created_at': DateTime.now().toIso8601String(),
};

/// Opens the sheet the way the screen does: inside a modal route.
Future<void> _open(WidgetTester tester, Widget sheet) async {
  // The test font draws every glyph as a full em square, far wider than the
  // app font, so give rows real-device headroom (480 dp wide).
  tester.view.physicalSize = const Size(1440, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => sheet,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('order items load once and render', (tester) async {
    final h = _Harness();
    await _open(tester, h.sheet(_order('pending')));
    expect(find.textContaining('Mineral Water'), findsWidgets);

    // Keyboard open/close changes the route MediaQuery; the items stay loaded.
    for (final inset in [300.0, 0.0, 300.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset * 3);
      await tester.pumpAndSettle();
    }
    expect(h.itemLoads, 1);
  });

  testWidgets('pending order: Accept and Decline reach the screen callbacks', (
    tester,
  ) async {
    final h = _Harness();
    await _open(tester, h.sheet(_order('pending')));
    await tester.ensureVisible(find.text('Accept Order'));
    await tester.tap(find.text('Accept Order'));
    await tester.pumpAndSettle();
    expect(h.updates, ['abcdef12-0000-0000-0000-000000000000:accepted']);
    expect(
      find.byType(OwnerOrderDetailSheet),
      findsNothing,
      reason: 'actions close the sheet first',
    );

    await _open(tester, h.sheet(_order('pending')));
    await tester.ensureVisible(find.text('Decline'));
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(h.declines, ['abcdef12-0000-0000-0000-000000000000']);
  });

  test('shared formatting helpers', () {
    expect(shortOrderId('abcdef12-3456'), '#ABCDEF12');
    expect(shortOrderId('abc'), '#ABC');
    expect(formatOrderPeso('45'), formatOrderPeso(45));
    expect(orderElapsedLabel(null), 'recent');
    expect(
      orderElapsedLabel(
        DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      ),
      '5m ago',
    );
  });
}
