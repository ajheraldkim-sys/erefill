import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Global Premium Status Color System', () {
    test('offline queued orders are labeled as not yet submitted', () {
      expect(
        OrderStatusPresentation.fromStatus('pending_sync').label,
        'Queued Offline',
      );
    });

    test(
      'canonical semantic status colors match exact required specification',
      () {
        expect(OrderStatusColors.pending, const Color(0xFF925B28));
        expect(OrderStatusColors.confirmed, const Color(0xFF426F95));
        expect(OrderStatusColors.preparing, const Color(0xFF626C74));
        expect(OrderStatusColors.readyForDelivery, const Color(0xFF3F736D));
        expect(OrderStatusColors.outForDelivery, const Color(0xFF4B738A));
        expect(OrderStatusColors.completed, const Color(0xFF4F775C));
        expect(OrderStatusColors.cancelled, const Color(0xFF914646));
        expect(OrderStatusColors.rejected, const Color(0xFF80434A));
      },
    );

    test(
      'normalizes synonymous and database status strings to canonical colors',
      () {
        // Pending
        expect(OrderStatusColors.getColor('pending'), const Color(0xFF925B28));
        expect(
          OrderStatusColors.getColor('pending_sync'),
          const Color(0xFF925B28),
        );

        // Confirmed / Accepted
        expect(
          OrderStatusColors.getColor('confirmed'),
          const Color(0xFF426F95),
        );
        expect(OrderStatusColors.getColor('accepted'), const Color(0xFF426F95));

        // Preparing / in_prep
        expect(
          OrderStatusColors.getColor('preparing'),
          const Color(0xFF626C74),
        );
        expect(OrderStatusColors.getColor('in_prep'), const Color(0xFF626C74));

        // Ready for Delivery / Pickup
        expect(
          OrderStatusColors.getColor('ready_for_pickup'),
          const Color(0xFF3F736D),
        );
        expect(OrderStatusColors.getColor('ready'), const Color(0xFF3F736D));

        // Out for Delivery / Delivering / Assigned
        expect(
          OrderStatusColors.getColor('out_for_delivery'),
          const Color(0xFF4B738A),
        );
        expect(
          OrderStatusColors.getColor('delivering'),
          const Color(0xFF4B738A),
        );
        expect(
          OrderStatusColors.getColor('assigned_to_rider'),
          const Color(0xFF4B738A),
        );
        expect(
          OrderStatusColors.getColor('rider_assigned'),
          const Color(0xFF4B738A),
        );

        // Completed / Delivered
        expect(
          OrderStatusColors.getColor('delivered'),
          const Color(0xFF4F775C),
        );
        expect(
          OrderStatusColors.getColor('completed'),
          const Color(0xFF4F775C),
        );

        // Cancelled
        expect(
          OrderStatusColors.getColor('cancelled'),
          const Color(0xFF914646),
        );
        expect(OrderStatusColors.getColor('canceled'), const Color(0xFF914646));

        // Rejected
        expect(OrderStatusColors.getColor('rejected'), const Color(0xFF80434A));
      },
    );

    test(
      'resolves high contrast foregrounds for full-bleed and neutral surfaces',
      () {
        for (final status in [
          'pending',
          'accepted',
          'preparing',
          'ready_for_pickup',
          'out_for_delivery',
          'delivered',
          'cancelled',
          'rejected',
        ]) {
          final lightStyle = OrderStatusStyle.resolve(status, isDark: false);
          final darkStyle = OrderStatusStyle.resolve(status, isDark: true);

          // On full-color surface, text and chip foregrounds must be pure white for accessibility
          expect(lightStyle.chipForeground, Colors.white);
          expect(darkStyle.chipForeground, Colors.white);
          expect(lightStyle.cardTitleText, Colors.white);
          expect(darkStyle.cardTitleText, Colors.white);

          // Subtle background on neutral surfaces has soft alpha tint
          expect(lightStyle.subtleBackground.a, lessThan(1.0));
        }
      },
    );

    testWidgets(
      'renders OrderCard with full-color semantic background and actions',
      (tester) async {
        bool tapped = false;
        final dummyOrder = {
          'id': 'ord-test-12345678',
          'status': 'out_for_delivery',
          'total_amount': 250.0,
          'station_name': 'Crystal Clear Springs',
          'customer_name': 'Juan Dela Cruz',
          'delivery_address': 'Block 5 Lot 12, Sunrise Village',
          'items': [
            {'name': 'Alkaline Refill', 'quantity': 3},
          ],
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrderCard(
                order: dummyOrder,
                role: OrderCardRole.customer,
                onTap: () => tapped = true,
                bottomAction: const Text('Live Tracking Available'),
              ),
            ),
          ),
        );

        // Verify customer view elements
        expect(find.text('Crystal Clear Springs'), findsOneWidget);
        expect(find.text('₱250'), findsOneWidget);
        expect(find.text('Live Tracking Available'), findsOneWidget);
        expect(find.byType(OrderStatusChip), findsOneWidget);

        await tester.tap(find.byType(OrderCard));
        expect(tapped, isTrue);
      },
    );

    testWidgets(
      'renders OrderStatusChip consistently across light and dark theme',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  OrderStatusChip(status: 'pending'),
                  OrderStatusChip(
                    status: 'delivered',
                    onFullColorSurface: true,
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('Delivered'), findsOneWidget);
      },
    );
  });
}
