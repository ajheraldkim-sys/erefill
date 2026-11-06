import 'package:latlong2/latlong.dart';
import 'package:erefill/features/dashboard/customer/widgets/delivery_coverage_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lists every free rule then the paid rate', () {
    final lines = DeliveryCoverageCard.describe(
      radiusKm: 1.5,
      barangays: ['Poblacion', 'Linintian'],
      minGallons: 5,
      ratePerKm: 10,
      minimumFee: 20,
    );
    expect(lines, [
      'Free within 1.5 km of the station',
      'Free to Linintian, Poblacion',
      'Free for orders of 5+ gallons',
      'Elsewhere: ₱10/km, ₱20 minimum',
    ]);
  });

  test('omits rules the station has not set', () {
    final lines = DeliveryCoverageCard.describe(
      radiusKm: 0,
      barangays: const [],
      minGallons: null,
      ratePerKm: 2,
      minimumFee: 0,
    );
    expect(lines, ['Delivery: ₱2/km']);
  });

  test('zone map bounds contain the whole free-delivery circle', () {
    const c = LatLng(9.33, 125.97);
    final b = DeliveryCoverageCard.zoneBounds(c, 2);
    const d = Distance();
    // 2 km north, south, east and west of the station are inside.
    for (final bearing in [0.0, 90.0, 180.0, 270.0]) {
      expect(
        b.contains(d.offset(c, 2000, bearing)),
        isTrue,
        reason: '$bearing',
      );
    }
    // A zero radius still frames the station.
    expect(DeliveryCoverageCard.zoneBounds(c, 0).contains(c), isTrue);
  });
}
