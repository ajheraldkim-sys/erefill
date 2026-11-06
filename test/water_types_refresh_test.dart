import 'dart:convert';

import 'package:erefill/core/water_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/water_type_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    seedTestWaterTypes();
    WaterTypes.retryDelay = const Duration(milliseconds: 10);
  });

  tearDown(WaterTypes.cancelRetry);

  /// Fails the first [failures] requests with a gateway timeout, then serves
  /// a catalog where Mineral Water has a new photo.
  SupabaseClient flakyClient({required int failures}) {
    var calls = 0;
    return SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        calls++;
        if (calls <= failures) {
          return http.Response(
            jsonEncode({'message': 'Gateway Timeout'}),
            504,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode([
            {...testMineral.toJson(), 'photo_url': 'https://cdn/new.jpg'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  }

  test('a failed catalog fetch retries instead of keeping stale data', () async {
    await WaterTypes.load(client: flakyClient(failures: 1), force: true);

    // The 504 left the stale catalog in place...
    expect(WaterTypes.catalog.value, testWaterTypes);

    // ...and a retry picks up the fresh catalog without a realtime event.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(WaterTypes.catalog.value.single.photoUrl, 'https://cdn/new.jpg');
  });

  test('a successful fetch schedules no retry', () async {
    await WaterTypes.load(client: flakyClient(failures: 0), force: true);
    expect(WaterTypes.hasPendingRetry, isFalse);
  });
}
