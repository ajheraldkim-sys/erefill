import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/core/widgets/refill_components.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/water_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shared refill status presentation', () {
    test('maps the full delivery lifecycle to user-facing labels', () {
      expect(OrderStatusPresentation.fromStatus('pending').label, 'Pending');
      expect(
        OrderStatusPresentation.fromStatus('ready_for_pickup').label,
        'Ready for Pickup',
      );
      expect(
        OrderStatusPresentation.fromStatus('assigned_to_rider').label,
        'Assigned to Rider',
      );
      expect(
        OrderStatusPresentation.fromStatus('out_for_delivery').label,
        'Out for Delivery',
      );
      expect(
        OrderStatusPresentation.fromStatus('delivered').label,
        'Delivered',
      );
      expect(
        OrderStatusPresentation.fromStatus('cancelled').label,
        'Cancelled',
      );
    });

    test('keeps backward-compatible status aliases readable', () {
      expect(
        OrderStatusPresentation.fromStatus('ready').label,
        'Ready for Pickup',
      );
      expect(
        OrderStatusPresentation.fromStatus('rider_assigned').label,
        'Assigned to Rider',
      );
      expect(
        OrderStatusPresentation.fromStatus('delivering').label,
        'Out for Delivery',
      );
    });

    test('maps all station availability states consistently', () {
      expect(AvailabilityPresentation.fromAvailability('open').label, 'Open');
      expect(AvailabilityPresentation.fromAvailability('busy').label, 'Busy');
      expect(
        AvailabilityPresentation.fromAvailability('maintenance').label,
        'Maintenance',
      );
      expect(
        AvailabilityPresentation.fromAvailability('closed').label,
        'Closed',
      );
    });

    test('normalizes timeline status aliases', () {
      expect(RefillOrderStatusTimeline.statusIndex('pending'), 0);
      expect(RefillOrderStatusTimeline.statusIndex('ready'), 3);
      expect(RefillOrderStatusTimeline.statusIndex('rider_assigned'), 4);
      expect(RefillOrderStatusTimeline.statusIndex('delivering'), 5);
      expect(RefillOrderStatusTimeline.statusIndex('delivered'), 6);
    });
  });

  testWidgets('shared refill widgets render unified labels', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                OrderStatusBadge(status: 'ready_for_pickup'),
                AvailabilityBadge(availability: 'busy'),
                DashboardMetricCard(
                  label: 'Pending orders',
                  value: '4',
                  icon: Icons.receipt_long_outlined,
                  color: Colors.blue,
                ),
                WaterTypeCard(
                  type: WaterTypes.alkaline,
                  price: 45,
                  containerSize: '5 gallon',
                  preparationMinutes: 20,
                ),
                RefillOrderStatusTimeline(status: 'assigned_to_rider'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ready for Pickup'), findsOneWidget);
    expect(find.text('Busy'), findsOneWidget);
    expect(find.text('Pending orders'), findsOneWidget);
    expect(find.text('Alkaline Water'), findsOneWidget);
    expect(find.text('₱45'), findsOneWidget);
    expect(find.text('Assigned to Rider'), findsOneWidget);
    expect(find.text('Order'), findsOneWidget);
    expect(find.text('Preparing'), findsOneWidget);
    expect(find.text('On the way'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
  });

  testWidgets('compact delivery progress fits a short screen area', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 328,
              height: 180,
              child: RefillOrderStatusTimeline(status: 'out_for_delivery'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Out for Delivery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DashboardStatCard renders smoothly with trend and delta', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashboardStatCard(
            label: "Today's revenue",
            value: '₱1,250',
            icon: Icons.payments_outlined,
            delta: '+12%',
            trend: [100.0, 200.0, 150.0, 300.0, 250.0, 400.0, 500.0],
          ),
        ),
      ),
    );

    expect(find.text("Today's revenue"), findsOneWidget);
    expect(find.text('₱1,250'), findsOneWidget);
    expect(find.text('+12%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'DashboardStatCard handles flat trend and single-point list gracefully',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DashboardStatCard(
                  label: 'Flat trend',
                  value: '10',
                  icon: Icons.show_chart,
                  trend: [0.0, 0.0, 0.0],
                ),
                DashboardStatCard(
                  label: 'Single point',
                  value: '5',
                  icon: Icons.show_chart,
                  trend: [1.0],
                ),
                DashboardStatCard(
                  label: 'Empty trend',
                  value: '0',
                  icon: Icons.show_chart,
                  trend: [],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Flat trend'), findsOneWidget);
      expect(find.text('Single point'), findsOneWidget);
      expect(find.text('Empty trend'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('timeline maps every status synonym to a real stage', () {
    int idx(String s) => RefillOrderStatusTimeline.statusIndex(s);
    expect(idx('completed'), idx('delivered'));
    expect(idx('confirmed'), idx('accepted'));
    expect(idx('in_prep'), idx('preparing'));
    expect(idx('dispatched'), idx('out_for_delivery'));
    expect(idx('ready_for_delivery'), idx('ready_for_pickup'));
    expect(idx('rider_assigned'), idx('assigned_to_rider'));
    expect(idx('pending_sync'), idx('pending'));
    for (final s in ['completed', 'confirmed', 'in_prep', 'dispatched']) {
      expect(idx(s), greaterThanOrEqualTo(0), reason: s);
    }
    expect(idx('cancelled'), -1);
    expect(idx('rejected'), -1);
  });

  testWidgets('rejected orders read as declined, not cancelled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefillOrderStatusTimeline(status: 'rejected')),
      ),
    );
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Cancelled'), findsNothing);
  });

  test('status synonyms share one canonical label', () {
    expect(OrderStatusColors.getLabel('confirmed'), 'Accepted');
    expect(OrderStatusColors.getLabel('completed'), 'Delivered');
    expect(
      OrderStatusColors.getLabel('ready_for_delivery'),
      'Ready for Pickup',
    );
    expect(
      OrderStatusPresentation.fromStatus('completed').label,
      OrderStatusStyle.resolve('completed').label,
    );
  });

  for (final waterType in WaterTypes.all) {
    for (final brightness in Brightness.values) {
      for (final compact in [false, true]) {
        testWidgets(
          'WaterTypeCard ${waterType.shortName} text is readable in ${brightness.name} mode (compact: $compact)',
          (tester) async {
            final isDark = brightness == Brightness.dark;
            await tester.pumpWidget(
              MaterialApp(
                theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
                home: Scaffold(
                  body: Center(
                    child: WaterTypeCard(
                      type: waterType,
                      price: 45,
                      containerSize: '5 gallon',
                      preparationMinutes: 20,
                      compact: compact,
                    ),
                  ),
                ),
              ),
            );
            _expectReadableOnSurface(
              tester,
              isDark ? AppUi.darkSurface : AppUi.surface,
            );
          },
        );
      }
    }
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void _expectReadableOnSurface(WidgetTester tester, Color surface) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final color = text.style?.color;
    if (color == null) continue;
    expect(
      _contrast(color, surface),
      greaterThanOrEqualTo(4.5),
      reason: '"${text.data}" is unreadable on its card',
    );
  }
}
