import 'dart:convert';

import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Real SupabaseClient; the transition RPC answers [rpcStatus]/[rpcBody] and
/// every request is recorded so the test can prove no direct write happened.
class _Backend {
  _Backend(this.rpcStatus, this.rpcBody, {this.rpcPath});

  final int rpcStatus;
  final Object rpcBody;
  final String? rpcPath;
  final List<http.Request> requests = [];

  late final SupabaseClient client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      final isRpc =
          request.url.path ==
          (rpcPath ?? '/rest/v1/rpc/transition_order_status_safely');
      return http.Response(
        jsonEncode(isRpc ? rpcBody : []),
        isRpc ? rpcStatus : 200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );

  Iterable<http.Request> get directOrderWrites => requests.where(
    (r) => r.url.path == '/rest/v1/orders' && r.method != 'GET',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an allowed transition goes through the server function', () async {
    final backend = _Backend(200, {'success': true, 'status': 'accepted'});
    final result = await SafeSupabase.transitionOrderStatus(
      orderId: 'o1',
      newStatus: 'accepted',
      client: backend.client,
    );
    expect(result['success'], isTrue);
    expect(jsonDecode(backend.requests.single.body), {
      'p_order_id': 'o1',
      'p_new_status': 'accepted',
    });
  });

  test(
    'a transition the server rejects is NOT forced with a direct update',
    () async {
      final backend = _Backend(400, {
        'message':
            'Invalid station order status transition from pending to preparing.',
        'code': 'P0001',
      });
      await expectLater(
        SafeSupabase.transitionOrderStatus(
          orderId: 'o1',
          newStatus: 'preparing',
          client: backend.client,
        ),
        throwsA(
          isA<PostgrestException>().having(
            (e) => e.message,
            'message',
            contains('Invalid station order status transition'),
          ),
        ),
      );
      expect(backend.directOrderWrites, isEmpty);
    },
  );

  test(
    'a success:false reply is returned to the caller, not overridden',
    () async {
      final backend = _Backend(200, {
        'success': false,
        'message': 'Order not found',
      });
      final result = await SafeSupabase.transitionOrderStatus(
        orderId: 'o1',
        newStatus: 'cancelled',
        client: backend.client,
      );
      expect(result['success'], isFalse);
      expect(result['message'], 'Order not found');
      expect(backend.directOrderWrites, isEmpty);
    },
  );

  test('pickup completion uses its dedicated server workflow', () async {
    final backend = _Backend(200, {
      'success': true,
      'status': 'delivered',
    }, rpcPath: '/rest/v1/rpc/complete_pickup_order_safely');

    final result = await SafeSupabase.completePickupOrder(
      orderId: 'pickup-1',
      client: backend.client,
    );

    expect(result['success'], isTrue);
    expect(
      backend.requests.single.url.path,
      endsWith('/complete_pickup_order_safely'),
    );
    expect(jsonDecode(backend.requests.single.body), {
      'p_order_id': 'pickup-1',
    });
  });

  test('pickup completion surfaces a server refusal', () async {
    final backend = _Backend(200, {
      'success': false,
      'message': 'Only pickup orders can be completed here.',
    }, rpcPath: '/rest/v1/rpc/complete_pickup_order_safely');

    await expectLater(
      SafeSupabase.completePickupOrder(
        orderId: 'delivery-1',
        client: backend.client,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Only pickup orders'),
        ),
      ),
    );
    expect(backend.requests, hasLength(1));
  });

  group('rider management never reports a change that did not happen', () {
    SupabaseClient rejecting(List<http.Request> sink) => SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        sink.add(request);
        return http.Response(
          jsonEncode({
            'message': 'Not authorized to unlink this rider',
            'code': 'P0001',
          }),
          400,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );

    test(
      'unlinkRider surfaces the rejection and does not write profiles',
      () async {
        final sent = <http.Request>[];
        await expectLater(
          SafeSupabase.unlinkRider(riderId: 'r1', client: rejecting(sent)),
          throwsA(isA<PostgrestException>()),
        );
        expect(
          sent.map((request) => request.url.path),
          contains('/rest/v1/rpc/owner_unlink_rider'),
        );
        expect(sent.where((r) => r.url.path == '/rest/v1/profiles'), isEmpty);
      },
    );

    test(
      'setRiderStatus surfaces the rejection and does not write profiles',
      () async {
        final sent = <http.Request>[];
        await expectLater(
          SafeSupabase.setRiderStatus(
            riderId: 'r1',
            isSuspended: true,
            client: rejecting(sent),
          ),
          throwsA(isA<PostgrestException>()),
        );
        expect(
          sent.map((request) => request.url.path),
          contains('/rest/v1/rpc/owner_set_rider_status'),
        );
        expect(sent.where((r) => r.url.path == '/rest/v1/profiles'), isEmpty);
      },
    );
  });
}
