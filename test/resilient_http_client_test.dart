import 'dart:async';

import 'package:erefill/core/services/resilient_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _base = 'https://example.supabase.co';

ResilientHttpClient _client(
  MockClientHandler handler, {
  List<Duration>? waits,
  Duration timeout = const Duration(seconds: 20),
}) => ResilientHttpClient(
  inner: MockClient(handler),
  defaultTimeout: timeout,
  longTimeout: timeout * 6,
  sleep: (d) async => waits?.add(d),
);

void main() {
  group('ResilientHttpClient retries', () {
    test('retries an idempotent read on a gateway error', () async {
      var calls = 0;
      final waits = <Duration>[];
      final client = _client((_) async {
        calls++;
        return http.Response('', calls < 3 ? 504 : 200);
      }, waits: waits);

      final res = await client.get(Uri.parse('$_base/rest/v1/products'));

      expect(res.statusCode, 200);
      expect(calls, 3);
      expect(waits, hasLength(2));
      expect(waits[1], greaterThan(waits[0]));
    });

    test('gives up after the retry limit and returns the last error', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        return http.Response('', 522);
      });

      final res = await client.get(Uri.parse('$_base/rest/v1/orders'));

      expect(res.statusCode, 522);
      expect(calls, 1 + ResilientHttpClient.maxRetries);
    });

    test('never retries writes, so an order is not created twice', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        return http.Response('', 504);
      });

      final res = await client.post(
        Uri.parse('$_base/rest/v1/rpc/create_order_safely'),
        body: '{}',
      );

      expect(res.statusCode, 504);
      expect(calls, 1);
    });

    test('leaves auth retries to gotrue', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        return http.Response('', 503);
      });

      await client.get(Uri.parse('$_base/auth/v1/user'));

      expect(calls, 1);
    });

    test('does not retry client errors such as 404 or 429', () async {
      for (final status in [400, 404, 429]) {
        var calls = 0;
        final client = _client((_) async {
          calls++;
          return http.Response('', status);
        });
        await client.get(Uri.parse('$_base/rest/v1/profiles'));
        expect(calls, 1, reason: 'status $status');
      }
    });

    test('retries a read after a dropped connection', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('Connection reset');
        return http.Response('[]', 200);
      });

      final res = await client.get(Uri.parse('$_base/rest/v1/favorites'));

      expect(res.statusCode, 200);
      expect(calls, 2);
    });
  });

  group('ResilientHttpClient timeouts', () {
    test('a hung request fails with a timeout instead of spinning', () async {
      var calls = 0;
      final client = _client((_) {
        calls++;
        return Completer<http.Response>().future;
      }, timeout: const Duration(milliseconds: 20));

      await expectLater(
        client.get(Uri.parse('$_base/rest/v1/orders')),
        throwsA(
          isA<RequestTimeoutException>().having(
            (e) => e.toString().toLowerCase(),
            'message',
            contains('timeout'),
          ),
        ),
      );
      // A request that already hung is not retried: that only adds load
      // and doubles the wait.
      expect(calls, 1);
    });

    test('storage gets the longer timeout for uploads', () async {
      final client = _client((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response('', 200);
      }, timeout: const Duration(milliseconds: 20));

      final res = await client.post(
        Uri.parse('$_base/storage/v1/object/avatars/a.png'),
        body: 'x',
      );

      expect(res.statusCode, 200);
    });
  });
}
