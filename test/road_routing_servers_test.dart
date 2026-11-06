import 'dart:convert';

import 'package:erefill/core/services/road_routing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

String _osrm(List<List<double>> coords) => jsonEncode({
  'code': 'Ok',
  'routes': [
    {
      'geometry': {'type': 'LineString', 'coordinates': coords},
    },
  ],
});

void main() {
  const a = LatLng(9.33, 125.97);
  const b = LatLng(9.34, 125.98);

  test('builds an OSRM route URL for any base, trailing slash or not', () {
    final u = RoadRoutingService.routeUrl('https://x.test/routed-car/', a, b);
    expect(
      u.toString(),
      'https://x.test/routed-car/route/v1/driving/125.97,9.33;125.98,9.34'
      '?overview=full&geometries=geojson',
    );
  });

  test('parses OSRM geometry as lat/lng and rejects error answers', () {
    final pts = RoadRoutingService.parseRoute(
      _osrm([
        [125.97, 9.33],
        [125.98, 9.34],
      ]),
    )!;
    expect(pts.first, a);
    expect(pts.last, b);
    expect(
      RoadRoutingService.parseRoute('{"code":"NoRoute","routes":[]}'),
      isNull,
    );
    expect(RoadRoutingService.parseRoute('not json'), isNull);
  });

  test(
    'falls through to the next server and skips a failing one later',
    () async {
      final calls = <String>[];
      final svc = RoadRoutingService(
        servers: ['https://down.test', 'https://up.test'],
        fetch: (url) async {
          calls.add(url.host);
          if (url.host == 'down.test') return (503, '');
          return (
            200,
            _osrm([
              [125.97, 9.33],
              [125.975, 9.335],
              [125.98, 9.34],
            ]),
          );
        },
      );
      final first = await svc.getRoadRoute(start: a, end: b);
      expect(first, hasLength(3));
      expect(calls, ['down.test', 'up.test']);

      calls.clear();
      await svc.getRoadRoute(start: const LatLng(9.30, 125.90), end: b);
      expect(calls, ['up.test'], reason: 'down server is backed off');
    },
  );

  test(
    'caches routes and falls back to a straight line when all fail',
    () async {
      var n = 0;
      final svc = RoadRoutingService(
        servers: ['https://only.test'],
        fetch: (url) async {
          n++;
          return (
            200,
            _osrm([
              [125.97, 9.33],
              [125.98, 9.34],
            ]),
          );
        },
      );
      await svc.getRoadRoute(start: a, end: b);
      await svc.getRoadRoute(start: a, end: b);
      expect(n, 1, reason: 'second call served from cache');

      final dead = RoadRoutingService(
        servers: ['https://dead.test'],
        fetch: (url) async => throw const SocketExceptionLike(),
      );
      expect(await dead.getRoadRoute(start: a, end: b), [a, b]);
    },
  );
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
