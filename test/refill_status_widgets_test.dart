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
}
