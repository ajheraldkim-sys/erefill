import 'package:erefill/core/utils/route_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const start = LatLng(9.000, 126.000);
  // Stops along a line north of the station, given out of order.
  const a = RouteStop(id: 'a', point: LatLng(9.030, 126.0));
  const b = RouteStop(id: 'b', point: LatLng(9.010, 126.0));
  const c = RouteStop(id: 'c', point: LatLng(9.020, 126.0));

  test('visits stops in the shortest order', () {
    final plan = RouteOptimizer.plan(start, [a, b, c]);
    expect(plan.stops.map((s) => s.id), ['b', 'c', 'a']);
  });

  test('optimized route is never longer than the given order', () {
    const stops = [
      RouteStop(id: '1', point: LatLng(9.05, 126.02)),
      RouteStop(id: '2', point: LatLng(9.00, 126.05)),
      RouteStop(id: '3', point: LatLng(9.04, 126.00)),
      RouteStop(id: '4', point: LatLng(9.01, 126.03)),
      RouteStop(id: '5', point: LatLng(9.06, 126.06)),
    ];
    final naive = RouteOptimizer.totalKm(start, stops);
    final plan = RouteOptimizer.plan(start, stops);
    expect(plan.totalKm, lessThanOrEqualTo(naive + 1e-9));
    expect(plan.stops.toSet(), stops.toSet());
  });

  test('2-opt fixes a crossing that nearest-neighbour leaves', () {
    // Nearest-neighbour from start goes to p1 then p2 (crossing); best
    // order is p1, p3, p2... verify the result is optimal by brute force.
    const stops = [
      RouteStop(id: 'p1', point: LatLng(9.001, 126.010)),
      RouteStop(id: 'p2', point: LatLng(9.020, 126.000)),
      RouteStop(id: 'p3', point: LatLng(9.020, 126.020)),
      RouteStop(id: 'p4', point: LatLng(9.000, 126.030)),
    ];
    final plan = RouteOptimizer.plan(start, stops);
    final best = _bruteForce(start, stops);
    expect(plan.totalKm, closeTo(best, 1e-6));
  });

  test('cumulative arrival minutes grow along the route', () {
    final plan = RouteOptimizer.plan(start, [a, b, c]);
    expect(plan.arrivalMinutes.length, 3);
    expect(plan.arrivalMinutes[0] < plan.arrivalMinutes[1], isTrue);
    expect(plan.arrivalMinutes[1] < plan.arrivalMinutes[2], isTrue);
  });

  test('large batches (2-opt path) still beat the given order', () {
    final stops = [
      for (var i = 0; i < 10; i++)
        RouteStop(
          id: '$i',
          point: LatLng(9.0 + ((i * 7) % 10) / 200, 126.0 + ((i * 3) % 10) / 200),
        ),
    ];
    final plan = RouteOptimizer.plan(start, stops);
    expect(plan.totalKm, lessThan(RouteOptimizer.totalKm(start, stops)));
    expect(plan.stops.toSet(), stops.toSet());
  });

  test('empty and single stop are trivial', () {
    expect(RouteOptimizer.plan(start, const []).stops, isEmpty);
    expect(RouteOptimizer.plan(start, const [a]).stops.single.id, 'a');
  });
}

double _bruteForce(LatLng start, List<RouteStop> stops) {
  var best = double.infinity;
  void perm(List<RouteStop> done, List<RouteStop> rest) {
    if (rest.isEmpty) {
      final d = RouteOptimizer.totalKm(start, done);
      if (d < best) best = d;
      return;
    }
    for (var i = 0; i < rest.length; i++) {
      perm([...done, rest[i]], [...rest]..removeAt(i));
    }
  }

  perm([], stops);
  return best;
}
