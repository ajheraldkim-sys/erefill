import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/core/widgets/app_ui_kit.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/features/dashboard/customer/cart_screen.dart';
import 'package:erefill/core/models/cart_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  double width,
  Widget child, {
  ThemeData? theme,
  double textScale = 1.3,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: child,
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final width in [320.0, 360.0, 768.0, 1280.0]) {
    testWidgets('cart with items lays out at ${width.toInt()}px', (
      tester,
    ) async {
      final cart = CartProvider();
      cart.setStation('stn-1', 'Aqua Pure Refilling Station Poblacion');
      cart.addItem('a', '5-Gallon Purified Water (Round, with cap)', 35);
      cart.addItem('b', 'Alkaline Water Slim Container', 45);
      cart.updateQuantity('a', 12);

      await _pumpAt(
        tester,
        width,
        ChangeNotifierProvider<CartProvider>.value(
          value: cart,
          child: const CartScreen(
            station: {'id': 'stn-1', 'station_name': 'Aqua Pure'},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Order summary'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Order summary'), findsOneWidget);
      // ₱35 × 12 + ₱45 = ₱465.00, formatted consistently.
      expect(find.text('₱465.00'), findsWidgets);
      // Every stepper button meets the 48 dp target.
      final plus = tester.getSize(find.byTooltip('Increase quantity').first);
      expect(plus.height, greaterThanOrEqualTo(48));
      expect(plus.width, greaterThanOrEqualTo(48));
    });
  }

  testWidgets('shared status components fit a 320px row in dark mode', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      320,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in [
                    'pending',
                    'accepted',
                    'preparing',
                    'ready_for_pickup',
                    'out_for_delivery',
                    'delivered',
                    'cancelled',
                    'rejected',
                  ])
                    OrderStatusBadge(status: s),
                  AppStatusPill.payment('paid'),
                  AppStatusPill.payment('failed'),
                  AppStatusPill.account('suspended'),
                  const AvailabilityBadge(availability: 'busy'),
                ],
              ),
              const SizedBox(height: 16),
              const PriceBreakdown(
                lines: [
                  PriceLine(label: 'Subtotal (3 items)', amount: 105),
                  PriceLine(
                    label: 'Delivery fee',
                    placeholder: 'from ₱20.00',
                    note: '₱10.00/km from the station',
                  ),
                  PriceLine(
                    label: 'Voucher',
                    amount: 20,
                    isDiscount: true,
                  ),
                ],
                total: 105,
              ),
            ],
          ),
        ),
      ),
      theme: AppTheme.darkTheme,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Out for Delivery'), findsOneWidget);
    expect(find.text('−₱20.00'), findsOneWidget);
  });

  testWidgets('QuantitySelector turns minus into remove at the minimum', (
    tester,
  ) async {
    var value = 1;
    var removed = false;
    await _pumpAt(
      tester,
      360,
      Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => QuantitySelector(
              value: value,
              itemLabel: 'Purified',
              onChanged: (v) => setState(() => value = v),
              onRemove: () => removed = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    expect(value, 2);
    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pump();
    expect(value, 1);
    await tester.tap(find.byTooltip('Remove Purified'));
    expect(removed, isTrue);
  });

  test('formatPeso is consistent everywhere', () {
    expect(formatPeso(1234.5), '₱1,234.50');
    expect(formatPeso(0), '₱0.00');
    expect(formatPeso(null), '₱0.00');
    expect(formatPeso(1500, whole: true), '₱1,500');
  });

  testWidgets('confirm dialog only resolves true on confirm', (tester) async {
    late BuildContext ctx;
    await _pumpAt(
      tester,
      360,
      Builder(
        builder: (c) {
          ctx = c;
          return const Scaffold();
        },
      ),
    );
    final future = showAppConfirmDialog(
      ctx,
      title: 'Clear cart?',
      message: 'All items will be removed.',
      destructive: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await future, isFalse);
  });
}
