import 'dart:convert';

import 'package:erefill/core/services/payment_checkout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Real SupabaseClient whose edge-function calls hit [respond].
class _Backend {
  _Backend(this.respond);

  final http.Response Function(Map<String, dynamic> body) respond;
  final List<Map<String, dynamic>> calls = [];

  late final SupabaseClient client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      expect(request.url.path, '/functions/v1/create-payment-checkout');
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      calls.add(body);
      final res = respond(body);
      return http.Response(
        res.body,
        res.statusCode,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  group('PaymentCheckoutService.createCheckout', () {
    test(
      'normalizes the method and returns the trimmed checkout URL',
      () async {
        final backend = _Backend(
          (_) => _json({'checkout_url': '  https://pay.example/abc  '}),
        );
        final url = await PaymentCheckoutService(
          backend.client,
        ).createCheckout(orderId: 'o1', paymentMethod: ' PayMaya ');

        expect(url, 'https://pay.example/abc');
        expect(backend.calls.single, {
          'order_id': 'o1',
          'payment_method': 'maya',
        });
      },
    );

    test('sends force_new_checkout only when asked', () async {
      final backend = _Backend((_) => _json({'checkout_url': 'https://x'}));
      await PaymentCheckoutService(backend.client).createCheckout(
        orderId: 'o1',
        paymentMethod: 'gcash',
        forceNewCheckout: true,
      );
      expect(backend.calls.single['force_new_checkout'], isTrue);
    });

    test('surfaces the server error message from a 2xx body', () async {
      final backend = _Backend(
        (_) => _json({
          'error': 'Order is not eligible for this checkout session.',
        }),
      );
      await expectLater(
        PaymentCheckoutService(
          backend.client,
        ).createCheckout(orderId: 'o1', paymentMethod: 'gcash'),
        throwsA(
          isA<PaymentCheckoutException>().having(
            (e) => e.toString(),
            'message',
            contains('not eligible'),
          ),
        ),
      );
    });

    test('surfaces the server error message from a non-2xx response', () async {
      final backend = _Backend(
        (_) => _json({'error': 'PayMongo is not configured.'}, 400),
      );
      await expectLater(
        PaymentCheckoutService(
          backend.client,
        ).createCheckout(orderId: 'o1', paymentMethod: 'gcash'),
        throwsA(
          isA<PaymentCheckoutException>()
              .having((e) => e, 'type', isNot(isA<FunctionException>()))
              .having(
                (e) => e.toString(),
                'message',
                contains('PayMongo is not configured.'),
              ),
        ),
      );
    });

    test('a response with no URL and no error is a failure', () async {
      final backend = _Backend((_) => _json({'ok': true}));
      await expectLater(
        PaymentCheckoutService(
          backend.client,
        ).createCheckout(orderId: 'o1', paymentMethod: 'card'),
        throwsA(isA<PaymentCheckoutException>()),
      );
    });
  });

  group('PaymentCheckoutService.verify', () {
    test('reads both fields the edge function returns', () async {
      final backend = _Backend(
        (_) => _json({'verified': true, 'payment_status': 'success'}),
      );
      final result = await PaymentCheckoutService(backend.client).verify('o1');
      expect(backend.calls.single, {'action': 'verify', 'order_id': 'o1'});
      expect(result.isPaid, isTrue);
      expect(result.paymentStatus, 'success');
    });

    test('an unpaid order is not paid', () async {
      final backend = _Backend(
        (_) => _json({'verified': false, 'payment_status': 'processing'}),
      );
      final result = await PaymentCheckoutService(backend.client).verify('o1');
      expect(result.isPaid, isFalse);
      expect(result.paymentStatus, 'processing');
    });
  });

  test('isPaidStatus accepts every success spelling the app uses', () {
    for (final s in ['success', 'paid', 'succeeded', 'SUCCESS']) {
      expect(PaymentCheckoutService.isPaidStatus(s), isTrue, reason: s);
    }
    for (final s in ['processing', 'failed', '', null]) {
      expect(PaymentCheckoutService.isPaidStatus(s), isFalse, reason: '$s');
    }
  });
}
