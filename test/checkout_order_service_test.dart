import 'dart:convert';

import 'package:erefill/features/dashboard/customer/services/checkout_order_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

CheckoutOrderRequest _request({
  List<CheckoutLineItem>? items,
  String paymentMethod = 'cod',
  String userNotes = 'Gate is blue',
  String containerOption = 'swap',
  bool scheduleForNextOpen = false,
  String? voucherId,
}) => CheckoutOrderRequest(
  customerId: 'cust-1',
  stationId: 'owner-1',
  stationName: 'Aqua',
  customerName: 'Juan',
  profile: const {
    'complete_address': '  Purok 1, Bugsukan  ',
    'barangay': 'Bugsukan',
    'town': 'Cantilan',
    'landmark': 'Chapel',
    'phone': '0917',
    'region_id': 'r1',
    'latitude': 9.35,
    'longitude': 125.97,
  },
  paymentMethod: paymentMethod,
  items:
      items ??
      const [
        CheckoutLineItem(productId: 'p2', name: 'Mineral', quantity: 1),
        CheckoutLineItem(productId: 'p1', name: 'Purified', quantity: 2),
      ],
  subtotal: 65,
  deliveryFee: 5,
  deliveryDistanceKm: 1.2,
  deliveryRatePerKm: 4,
  totalAmount: 70,
  voucherId: voucherId,
  containerOption: containerOption,
  scheduleForNextOpen: scheduleForNextOpen,
  stationOpeningTime: '7:00 AM',
  userNotes: userNotes,
);

void main() {
  group('CheckoutOrderRequest', () {
    test(
      'fingerprint ignores cart order but tracks what changes the order',
      () {
        final base = _request();
        final reordered = _request(
          items: const [
            CheckoutLineItem(productId: 'p1', name: 'Purified', quantity: 2),
            CheckoutLineItem(productId: 'p2', name: 'Mineral', quantity: 1),
          ],
        );
        expect(
          reordered.fingerprint,
          base.fingerprint,
          reason: 'same cart, same idempotency key on retry',
        );
        expect(
          _request(paymentMethod: 'gcash').fingerprint,
          isNot(base.fingerprint),
        );
        expect(
          _request(userNotes: 'other').fingerprint,
          isNot(base.fingerprint),
        );
        expect(_request(voucherId: 'v1').fingerprint, isNot(base.fingerprint));
      },
    );

    test('fingerprint keeps the exact pre-refactor shape', () {
      expect(jsonDecode(_request().fingerprint), {
        'customer_id': 'cust-1',
        'station_id': 'owner-1',
        'payment_method': 'cod',
        'address': 'Purok 1, Bugsukan',
        'barangay': 'Bugsukan',
        'town': 'Cantilan',
        'landmark': 'Chapel',
        'latitude': 9.35,
        'longitude': 125.97,
        'notes': 'Gate is blue',
        'voucher_id': null,
        'items': [
          {'product_id': 'p1', 'product_name': 'Purified', 'quantity': 2},
          {'product_id': 'p2', 'product_name': 'Mineral', 'quantity': 1},
        ],
      });
    });

    test('notes combine container choice, schedule and the customer note', () {
      expect(
        _request().combinedNotes,
        '[Container: 1-to-1 Bottle Swap] · Gate is blue',
      );
      expect(
        _request(
          containerOption: 'new',
          scheduleForNextOpen: true,
          userNotes: '  ',
        ).combinedNotes,
        '[Container: No Empty Bottle (Deposit / New Container Needed)]'
        ' · [Scheduled for next station opening (7:00 AM)]',
      );
    });

    test('order payload keeps every field the RPC reads', () {
      final data = _request(scheduleForNextOpen: true).toOrderData('key-1');
      expect(data, {
        'customer_id': 'cust-1',
        'owner_id': 'owner-1',
        'station_name': 'Aqua',
        'customer_name': 'Juan',
        'customer_phone': '0917',
        'customer_address': 'Purok 1, Bugsukan',
        'customer_barangay': 'Bugsukan',
        'customer_municipality': 'Cantilan',
        'customer_landmark': 'Chapel',
        'idempotency_key': 'key-1',
        'voucher_id': null,
        'subtotal': 65.0,
        'delivery_fee': 5.0,
        'delivery_distance_km': 1.2,
        'delivery_rate_per_km': 4.0,
        'total_amount': 70.0,
        'payment_method': 'cod',
        'payment_proof_url': null,
        'notes':
            '[Container: 1-to-1 Bottle Swap] · '
            '[Scheduled for next station opening (7:00 AM)] · Gate is blue',
        'region_id': 'r1',
        'customer_latitude': 9.35,
        'customer_longitude': 125.97,
        'container_exchange_type': 'swap',
        'scheduled_for_next_open': true,
      });
      expect(
        _request().toOrderData('k').containsKey('scheduled_for_next_open'),
        isFalse,
      );
    });
  });

  group('CheckoutOrderService.placeOrder', () {
    late List<Map<String, dynamic>> rpcBodies;

    SupabaseClient client(Object responseBody, [int status = 200]) {
      rpcBodies = [];
      return SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/create_order_atomic');
          rpcBodies.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          return http.Response(
            jsonEncode(responseBody),
            status,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
    }

    test('sends order + items and returns the server-computed total', () async {
      final placed = await CheckoutOrderService(
        client({'id': 'order-9', 'total_amount': 71.5}),
      ).placeOrder(_request(), idempotencyKey: 'key-1');

      expect(placed.id, 'order-9');
      expect(placed.totalAmount, 71.5, reason: 'server total is authoritative');
      final body = rpcBodies.single;
      expect(body['p_order_data']['idempotency_key'], 'key-1');
      expect(body['p_items_data'], [
        {'product_id': 'p2', 'product_name': 'Mineral', 'quantity': 1},
        {'product_id': 'p1', 'product_name': 'Purified', 'quantity': 2},
      ]);
    });

    test('falls back to the client total when the server omits it', () async {
      final placed = await CheckoutOrderService(
        client({'id': 'order-9'}),
      ).placeOrder(_request(), idempotencyKey: 'k');
      expect(placed.totalAmount, 70);
    });

    test('a response without an order id is a failure', () async {
      await expectLater(
        CheckoutOrderService(
          client({'total_amount': 70}),
        ).placeOrder(_request(), idempotencyKey: 'k'),
        throwsA(isA<StateError>()),
      );
    });

    test('server rejections propagate as PostgrestException', () async {
      await expectLater(
        CheckoutOrderService(
          client({'message': 'Product x is unavailable at this station.'}, 400),
        ).placeOrder(_request(), idempotencyKey: 'k'),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('error classification', () {
    test('friendlyError maps known server messages', () {
      String msg(String m) =>
          CheckoutOrderService.friendlyError(PostgrestException(message: m));
      expect(
        msg('Only customer accounts can place orders.'),
        'Only customer accounts can place orders.',
      );
      expect(
        msg('This water station is currently closed or unavailable.'),
        'This water station is currently closed or unavailable.',
      );
      expect(
        msg('This payment method is not available for this station.'),
        'This payment method is not available for this station.',
      );
      expect(
        msg('Product Gallon is unavailable at this station.'),
        'One or more items in your cart are unavailable at this station.',
      );
      expect(
        CheckoutOrderService.friendlyError(Exception('SocketException: x')),
        'Could not reach the server. Check your connection and try again.',
      );
    });

    test('isNetworkError recognizes offline failures only', () {
      for (final e in [
        Exception('SocketException: Failed host lookup'),
        Exception('ClientException: Connection closed'),
        Exception('TimeoutException after 0:00:10'),
      ]) {
        expect(CheckoutOrderService.isNetworkError(e), isTrue, reason: '$e');
      }
      expect(
        CheckoutOrderService.isNetworkError(
          PostgrestException(message: 'Cart cannot be empty.'),
        ),
        isFalse,
      );
    });
  });
}
