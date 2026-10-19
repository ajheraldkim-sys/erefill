import 'dart:convert';

import 'package:erefill/core/services/local_data_cache.dart';
import 'package:erefill/features/subscriptions/models/subscription_model.dart';
import 'package:erefill/features/subscriptions/services/subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records every request a real [SupabaseClient] sends, answering RPC calls
/// with [rpcStatus]/[rpcBody] and any other call with an empty list.
class _RecordingBackend {
  _RecordingBackend({this.rpcStatus = 200, this.rpcBody});

  final int rpcStatus;
  final Object? rpcBody;
  final List<http.Request> requests = [];

  late final SupabaseClient client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (request.url.path.startsWith('/rest/v1/rpc/')) {
        return http.Response(
          jsonEncode(rpcBody),
          rpcStatus,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );

  Iterable<http.Request> writesTo(String table) => requests.where(
    (r) => r.url.path == '/rest/v1/$table' && r.method != 'GET',
  );
}

void main() {
  group('Auto-refill order generation is server-authoritative', () {
    test(
      'customer run calls generate_due_subscription_orders and never writes orders directly',
      () async {
        final backend = _RecordingBackend(
          rpcBody: {
            'created': [
              {'id': 'o1', 'subscription_id': 's1', 'total_amount': 50.5},
            ],
            'skipped': [],
          },
        );

        final result = await SubscriptionService(
          backend.client,
        ).processDueSubscriptions(customerId: 'cust-1');

        final rpc = backend.requests.singleWhere(
          (r) => r.url.path == '/rest/v1/rpc/generate_due_subscription_orders',
        );
        expect(jsonDecode(rpc.body), {'p_customer_id': 'cust-1'});
        expect(backend.writesTo('orders'), isEmpty);
        expect(backend.writesTo('order_items'), isEmpty);
        expect(
          backend.writesTo('customer_subscriptions'),
          isEmpty,
          reason: 'the server advances next_delivery_date, not the app',
        );
        expect(result.created.single['total_amount'], 50.5);
        expect(result.skipped, isEmpty);
      },
    );

    test('owner run scopes the RPC to the station', () async {
      final backend = _RecordingBackend(
        rpcBody: {'created': [], 'skipped': []},
      );

      await SubscriptionService(
        backend.client,
      ).processDueSubscriptions(stationId: 'owner-1');

      final rpc = backend.requests.singleWhere(
        (r) => r.url.path == '/rest/v1/rpc/generate_due_subscription_orders',
      );
      expect(jsonDecode(rpc.body), {'p_station_id': 'owner-1'});
    });

    test(
      'server failure surfaces as an error with no client-side fallback insert',
      () async {
        final backend = _RecordingBackend(
          rpcStatus: 500,
          rpcBody: {'message': 'boom', 'code': 'XX000'},
        );

        await expectLater(
          SubscriptionService(
            backend.client,
          ).processDueSubscriptions(customerId: 'cust-1'),
          throwsA(isA<PostgrestException>()),
        );
        expect(backend.writesTo('orders'), isEmpty);
        expect(backend.writesTo('order_items'), isEmpty);
        expect(backend.writesTo('customer_subscriptions'), isEmpty);
      },
    );

    test('skipped subscriptions are reported with their reason', () async {
      final backend = _RecordingBackend(
        rpcBody: {
          'created': [],
          'skipped': [
            {'subscription_id': 's1', 'reason': 'product_unavailable'},
          ],
        },
      );

      final result = await SubscriptionService(
        backend.client,
      ).processDueSubscriptions(customerId: 'cust-1');

      expect(result.created, isEmpty);
      expect(result.skipped.single.subscriptionId, 's1');
      expect(result.skipped.single.reason, 'product_unavailable');
    });
  });

  group('createSubscription', () {
    Future<CustomerSubscription> create(SubscriptionService service) =>
        service.createSubscription(
          customerId: 'cust-fail',
          stationId: 'o1',
          stationName: 'Aqua',
          productId: 'p1',
          quantity: 2,
          waterType: 'Mineral',
          estimatedPrice: 40,
          frequency: 'weekly',
          preferredTimeSlot: 'morning',
          deliveryAddress: 'Purok 1',
        );

    test(
      'server rejection surfaces as an error and leaves no local-only routine',
      () async {
        SharedPreferences.setMockInitialValues({});
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode({'message': 'denied', 'code': '42501'}),
              403,
              headers: {'content-type': 'application/json'},
              request: request,
            ),
          ),
        );

        await expectLater(
          create(SubscriptionService(client)),
          throwsA(isA<PostgrestException>()),
        );
        final cached = await LocalDataCache.instance.get<List<dynamic>>(
          'customer_subscriptions_cust-fail',
        );
        expect(
          cached ?? const [],
          isEmpty,
          reason:
              'a routine the server never stored would never generate orders',
        );
      },
    );

    test(
      'successful insert sends product_id and keeps the cached routine',
      () async {
        SharedPreferences.setMockInitialValues({});
        final backend = _RecordingBackend();

        final sub = await create(SubscriptionService(backend.client));

        final insert = backend.writesTo('customer_subscriptions').single;
        expect((jsonDecode(insert.body) as Map)['product_id'], 'p1');
        final cached = await LocalDataCache.instance.get<List<dynamic>>(
          'customer_subscriptions_cust-fail',
        );
        expect((cached!.first as Map)['id'], sub.id);
      },
    );
  });

  group('pause and cancel', () {
    SupabaseClient failingClient() => SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'message': 'offline', 'code': 'XX000'}),
          503,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    const key = 'customer_subscriptions_cust-pause';
    final row = {'id': 's1', 'customer_id': 'cust-pause', 'is_active': true};

    test(
      'a failed pause surfaces and keeps the routine active locally',
      () async {
        SharedPreferences.setMockInitialValues({});
        await LocalDataCache.instance.set(key, [row]);

        await expectLater(
          SubscriptionService(failingClient()).toggleSubscription(
            subscriptionId: 's1',
            customerId: 'cust-pause',
            isActive: false,
          ),
          throwsA(isA<PostgrestException>()),
        );
        final cached = await LocalDataCache.instance.get<List<dynamic>>(key);
        expect(
          (cached!.single as Map)['is_active'],
          isTrue,
          reason: 'the server still generates orders for an active routine',
        );
      },
    );

    test('a failed cancel surfaces and keeps the routine listed', () async {
      SharedPreferences.setMockInitialValues({});
      await LocalDataCache.instance.set(key, [row]);

      await expectLater(
        SubscriptionService(
          failingClient(),
        ).deleteSubscription(subscriptionId: 's1', customerId: 'cust-pause'),
        throwsA(isA<PostgrestException>()),
      );
      final cached = await LocalDataCache.instance.get<List<dynamic>>(key);
      expect(cached, hasLength(1));
    });
  });

  group('CustomerSubscription.productId', () {
    test('round-trips through JSON and is omitted when null', () {
      final json = {
        'id': 's1',
        'customer_id': 'c1',
        'station_id': 'o1',
        'product_id': 'p1',
        'quantity': 2,
        'water_type': 'Mineral',
        'estimated_price': 40,
      };
      final sub = CustomerSubscription.fromJson(json);
      expect(sub.productId, 'p1');
      expect(sub.toJson()['product_id'], 'p1');

      final noProduct = CustomerSubscription.fromJson(
        {...json}..remove('product_id'),
      );
      expect(noProduct.productId, isNull);
      expect(noProduct.toJson().containsKey('product_id'), isFalse);
    });
  });
}
