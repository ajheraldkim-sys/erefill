import 'package:erefill/core/utils/tracking_eta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('route length sums the polyline in km', () {
    final km = TrackingEta.routeKm(const [
      LatLng(9.0, 126.0),
      LatLng(9.009, 126.0), // ~1 km north
      LatLng(9.018, 126.0), // ~1 km more
    ]);
    expect(km, closeTo(2.0, 0.05));
  });

  test('minutes at 20 km/h plus 2 min handover, at least 1', () {
    expect(TrackingEta.minutes(5), 17); // 15 min ride + 2
    expect(TrackingEta.minutes(0), 2);
  });

  test('label reads naturally', () {
    expect(TrackingEta.label(0.05), 'Arriving now');
    expect(TrackingEta.label(2.0), 'Arriving in ~8 min');
    expect(TrackingEta.label(30), 'Arriving in ~1 hr 32 min');
  });
}
