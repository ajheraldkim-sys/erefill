import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/dashboard/owner/owner_order_queue.dart';

void main() {
  group('Owner order queue', () {
    test('prioritizes orders by the next operational action', () {
      final orders = [
        {'id': 'delivery', 'status': 'out_for_delivery'},
        {'id': 'ready', 'status': 'ready_for_pickup'},
        {'id': 'preparing', 'status': 'preparing'},
        {'id': 'new', 'status': 'pending'},
        {'id': 'accepted', 'status': 'accepted'},
        {'id': 'assigned', 'status': 'assigned_to_rider'},
      ];

      final result = prioritizeOwnerOrders(orders);

      expect(result.map((order) => order['id']), [
        'new',
        'accepted',
        'preparing',
        'ready',
        'assigned',
        'delivery',
      ]);
    });

    test('shows oldest order first within the same action priority', () {
      final orders = [
        {
          'id': 'newest',
          'status': 'pending',
          'created_at': '2026-10-16T09:00:00Z',
        },
        {
          'id': 'oldest',
          'status': 'pending',
          'created_at': '2026-10-16T08:00:00Z',
        },
      ];

      final result = prioritizeOwnerOrders(orders);

      expect(result.map((order) => order['id']), ['oldest', 'newest']);
    });
  });
}
