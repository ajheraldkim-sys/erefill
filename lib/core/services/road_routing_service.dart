import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Fetches a URL and returns (status code, body).
typedef RouteFetch = Future<(int, String)> Function(Uri url);

/// Road routes from open-source OSRM servers (OpenStreetMap data), tried in
/// order:
///   1. your own OSRM server, if built with
///      `--dart-define=ROUTING_URL=https://your-server` (free forever; see
///      docs/self_hosted_routing.md),
///   2. the FOSSGIS community server (routing.openstreetmap.de, fair use),
///   3. the OSRM demo server (last resort; not meant for apps).
/// A failing server is skipped for a few minutes, requests are spaced out,
/// and routes are cached. Falls back to a straight line when all fail.
class RoadRoutingService {
  RoadRoutingService({RouteFetch? fetch, List<String>? servers})
    : _fetch = fetch ?? _httpFetch,
      servers = servers ?? defaultServers;

  static final RoadRoutingService instance = RoadRoutingService();

  static const String _selfHosted = String.fromEnvironment('ROUTING_URL');

  /// OSRM base URLs, ending just before `/route/v1/...`.
  static List<String> get defaultServers => [
    if (_selfHosted.isNotEmpty) _selfHosted,
    'https://routing.openstreetmap.de/routed-car',
    'https://router.project-osrm.org',
  ];

  static const int cacheSize = 200;
  static const Duration backoff = Duration(minutes: 5);
  static const Duration minGap = Duration(milliseconds: 1100);

  final List<String> servers;
  final RouteFetch _fetch;
  // Map literals keep insertion order, which makes this an LRU cache.
  final _cache = <String, List<LatLng>>{};
  final Map<String, DateTime> _downUntil = {};
  DateTime? _lastRequest;

  static Uri routeUrl(String base, LatLng start, LatLng end) => Uri.parse(
    '${base.replaceAll(RegExp(r'/+$'), '')}/route/v1/driving/'
    '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
    '?overview=full&geometries=geojson',
  );

  /// Points of the first route in an OSRM response, or null.
  static List<LatLng>? parseRoute(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['code'] != null && json['code'] != 'Ok') return null;
      final routes = json['routes'] as List<dynamic>?;
      final coords =
          ((routes?.firstOrNull as Map?)?['geometry'] as Map?)?['coordinates']
              as List?;
      if (coords == null || coords.isEmpty) return null;
      final points = [
        for (final c in coords)
          if (c is List && c.length >= 2)
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      return points.isEmpty ? null : points;
    } catch (_) {
      return null;
    }
  }

  /// Road geometry from [start] to [end]; `[start, end]` if no server answers.
  Future<List<LatLng>> getRoadRoute({
    required LatLng start,
    required LatLng end,
  }) async {
    if (start.latitude == 0 && start.longitude == 0) return [start, end];
    if (end.latitude == 0 && end.longitude == 0) return [start, end];

    final key =
        '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->'
        '${end.latitude.toStringAsFixed(4)},${end.longitude.toStringAsFixed(4)}';
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit; // keep as most recent

    // Public OSRM servers do not send CORS headers for browsers.
    if (kIsWeb && _selfHosted.isEmpty) return [start, end];

    for (final base in servers) {
      final down = _downUntil[base];
      if (down != null && DateTime.now().isBefore(down)) continue;
      await _space();
      try {
        final (status, body) = await _fetch(routeUrl(base, start, end));
        final points = status == 200 ? parseRoute(body) : null;
        if (points != null) {
          _cache[key] = points;
          if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
          return points;
        }
        // 4xx with a valid "no route" answer is not the server's fault.
        if (status >= 500 || status == 429 || status == 0) {
          _downUntil[base] = DateTime.now().add(backoff);
        }
      } catch (e) {
        debugPrint('Routing via $base failed: $e');
        _downUntil[base] = DateTime.now().add(backoff);
      }
    }
    return [start, end];
  }

  Future<void> _space() async {
    final last = _lastRequest;
    if (last != null) {
      final wait = minGap - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequest = DateTime.now();
  }

  static Future<(int, String)> _httpFetch(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'eRefill/1.0 (com.erefill.app)');
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      final body = await response.transform(utf8.decoder).join();
      return (response.statusCode, body);
    } finally {
      client.close(force: false);
    }
  }
}
