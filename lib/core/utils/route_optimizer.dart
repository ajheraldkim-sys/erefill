import 'package:latlong2/latlong.dart';

import 'tracking_eta.dart';

/// One delivery stop.
class RouteStop {
  const RouteStop({required this.id, required this.point, this.label});

  final String id;
  final LatLng point;
  final String? label;

  @override
  bool operator ==(Object other) => other is RouteStop && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class RoutePlan {
  const RoutePlan({
    required this.stops,
    required this.totalKm,
    required this.arrivalMinutes,
  });

  final List<RouteStop> stops;
  final double totalKm;

  /// Minutes from now until each stop, in route order (includes handover).
  final List<int> arrivalMinutes;
}

/// Orders a rider's stops to minimise total distance (open route that
/// starts at the rider and ends at the last stop).
///
/// Up to [exactLimit] stops are solved exactly; larger batches use
/// nearest-neighbour followed by 2-opt improvement. Distances are
/// straight-line km times the same road factor used for delivery fees.
abstract final class RouteOptimizer {
  static const int exactLimit = 7;
  static const double _roadFactor = 1.3;
  static const _distance = Distance();

  static double km(LatLng a, LatLng b) => _distance(a, b) / 1000 * _roadFactor;

  static double totalKm(LatLng start, List<RouteStop> order) {
    var sum = 0.0;
    var prev = start;
    for (final s in order) {
      sum += km(prev, s.point);
      prev = s.point;
    }
    return sum;
  }

  static RoutePlan plan(LatLng start, List<RouteStop> stops) {
    final order = stops.length <= exactLimit
        ? _exact(start, stops)
        : _twoOpt(start, _nearestNeighbour(start, stops));
    final minutes = <int>[];
    var travelled = 0.0;
    var prev = start;
    for (var i = 0; i < order.length; i++) {
      travelled += km(prev, order[i].point);
      prev = order[i].point;
      // Each earlier stop adds its handover time.
      minutes.add(TrackingEta.minutes(travelled) +
          i * TrackingEta.handoverMinutes);
    }
    return RoutePlan(
      stops: order,
      totalKm: totalKm(start, order),
      arrivalMinutes: minutes,
    );
  }

  static List<RouteStop> _exact(LatLng start, List<RouteStop> stops) {
    var best = List<RouteStop>.of(stops);
    var bestKm = totalKm(start, best);
    final current = <RouteStop>[];
    final used = List<bool>.filled(stops.length, false);

    void search(LatLng from, double soFar) {
      if (soFar >= bestKm) return; // prune
      if (current.length == stops.length) {
        bestKm = soFar;
        best = List.of(current);
        return;
      }
      for (var i = 0; i < stops.length; i++) {
        if (used[i]) continue;
        used[i] = true;
        current.add(stops[i]);
        search(stops[i].point, soFar + km(from, stops[i].point));
        current.removeLast();
        used[i] = false;
      }
    }

    if (stops.isNotEmpty) {
      bestKm = double.infinity;
      search(start, 0);
    }
    return best;
  }

  static List<RouteStop> _nearestNeighbour(LatLng start, List<RouteStop> stops) {
    final left = List<RouteStop>.of(stops);
    final order = <RouteStop>[];
    var at = start;
    while (left.isNotEmpty) {
      left.sort((a, b) => km(at, a.point).compareTo(km(at, b.point)));
      final next = left.removeAt(0);
      order.add(next);
      at = next.point;
    }
    return order;
  }

  static List<RouteStop> _twoOpt(LatLng start, List<RouteStop> order) {
    var route = List<RouteStop>.of(order);
    var improved = true;
    while (improved) {
      improved = false;
      for (var i = 0; i < route.length - 1; i++) {
        for (var j = i + 1; j < route.length; j++) {
          final candidate = [
            ...route.sublist(0, i),
            ...route.sublist(i, j + 1).reversed,
            ...route.sublist(j + 1),
          ];
          if (totalKm(start, candidate) + 1e-9 < totalKm(start, route)) {
            route = candidate;
            improved = true;
          }
        }
      }
    }
    return route;
  }
}
