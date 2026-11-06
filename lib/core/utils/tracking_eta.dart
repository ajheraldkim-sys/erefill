import 'package:latlong2/latlong.dart';

/// Rough arrival estimate for a rider on a motorbike in town traffic.
abstract final class TrackingEta {
  /// Average delivery speed including stops (km/h).
  static const double averageKmh = 20;

  /// Parking and handing over the gallons.
  static const int handoverMinutes = 2;

  static const _distance = Distance();

  /// Length of a road route polyline in km.
  static double routeKm(List<LatLng> points) {
    var meters = 0.0;
    for (var i = 1; i < points.length; i++) {
      meters += _distance(points[i - 1], points[i]);
    }
    return meters / 1000;
  }

  static int minutes(double km) =>
      (km / averageKmh * 60).round() + handoverMinutes;

  static String label(double km) {
    if (km < 0.1) return 'Arriving now';
    final m = minutes(km);
    if (m < 60) return 'Arriving in ~$m min';
    return 'Arriving in ~${m ~/ 60} hr ${m % 60} min';
  }
}
