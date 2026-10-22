import 'dart:convert';

import 'package:erefill/features/fee_wallet/services/fee_wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<Map<String, dynamic>> calls;

  SupabaseClient client(Object Function(Map<String, dynamic> body) respond) {
    calls = [];
    return SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/functions/v1/create-payment-checkout');
        final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        calls.add(body);
        return http.Response(
          jsonEncode(respond(body)),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  }

  test('startTopup asks the edge function for a top-up checkout', () async {
    final service = FeeWalletService(
      client: client(
        (_) => {
          'checkout_url': 'https://pay.example/t',
          'topup_id': 't1',
          'livemode': false,
        },
      ),
    );
    final session = await service.startTopup(amount: 300, paymentMethod: 'qrph');
    expect(calls.single, {
      'action': 'topup',
      'amount': 300,
      'payment_method': 'qrph',
    });
    expect(session.url, 'https://pay.example/t');
    expect(session.topupId, 't1');
    expect(session.livemode, isFalse);
  });

  test('verifyTopup reports whether the top-up was credited', () async {
    final service = FeeWalletService(
      client: client(
        (_) => {'verified': true, 'status': 'paid', 'balance': 400, 'livemode': false},
      ),
    );
    final result = await service.verifyTopup('t1');
    expect(calls.single, {'action': 'verify_topup', 'topup_id': 't1'});
    expect(result.paid, isTrue);
    expect(result.balance, 400);
  });
}
