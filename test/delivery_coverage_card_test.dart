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
}
