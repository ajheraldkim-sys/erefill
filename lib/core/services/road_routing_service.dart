import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Road routing service using the OpenStreetMap OSRM driving engine.
/// Computes actual street and road geometry for rider and delivery tracking.
class RoadRoutingService {
  RoadRoutingService._();
  static final RoadRoutingService instance = RoadRoutingService._();

  final Map<String, List<LatLng>> _cache = {};

  /// Fetches road geometry points between [start] and [end].
  /// Returns a list of LatLng coordinates conforming to the road network.
  /// Falls back to a direct line `[start, end]` if offline or on network error.
  Future<List<LatLng>> getRoadRoute({
    required LatLng start,
    required LatLng end,
  }) async {
    // Basic coordinate validation
    if (start.latitude == 0 && start.longitude == 0) return [start, end];
    if (end.latitude == 0 && end.longitude == 0) return [start, end];

    final cacheKey =
        '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->'
        '${end.latitude.toStringAsFixed(4)},${end.longitude.toStringAsFixed(4)}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    if (kIsWeb) {
      // In web, return direct line to avoid CORS restrictions on public demo OSRM
      return [start, end];
    }

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson',
      );

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);

      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'eRefill-Flutter-App/1.0');
      final response = await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        final routes = json['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0] as Map<String, dynamic>;
          final geometry = firstRoute['geometry'] as Map<String, dynamic>?;
          final coordinates = geometry?['coordinates'] as List<dynamic>?;

          if (coordinates != null && coordinates.isNotEmpty) {
            final points = <LatLng>[];
            for (final coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                final lng = (coord[0] as num).toDouble();
                final lat = (coord[1] as num).toDouble();
                points.add(LatLng(lat, lng));
              }
            }

            if (points.isNotEmpty) {
              _cache[cacheKey] = points;
              return points;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('RoadRoutingService error (falling back to direct line): $e');
    }

    return [start, end];
  }
}

