import 'package:erefill/features/dashboard/customer/checkout_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors supabase/tests/delivery_quote_test.sql so the offline estimate
/// matches what the server charges.
void main() {
  DeliveryQuote quote({
    double? km,
    double radius = 1.0,
    List<String> barangays = const [],
    String? barangay,
    int? minGallons,
    int gallons = 1,
  }) =>
      CheckoutRules.quoteDelivery(
        straightLineKm: km,
        freeRadiusKm: radius,
        freeBarangays: barangays,
        customerBarangay: barangay,
        freeMinGallons: minGallons,
        gallons: gallons,
        ratePerKm: 10,
        minimumFee: 20,
        minBillableDistanceKm: 1,
        roundingRule: 'exact',
      );

  test('road distance is straight line x 1.3', () {
    expect(CheckoutRules.roadDistanceKm(5.559), closeTo(7.23, 0.01));
  });

  test('inside the free radius is free', () {
    final q = quote(km: 0.5);
    expect(q.isFree, isTrue);
    expect(q.freeReason, 'radius');
    expect(q.fee, 0);
  });

  test('outside the radius pays per km', () {
    final q = quote(km: 5.559);
    expect(q.isFree, isFalse);
    expect(q.fee, 72);
    expect(q.distanceKm, closeTo(7.23, 0.01));
  });

  test('just outside the radius pays the minimum', () {
    expect(quote(km: 1.0007).fee, 20);
  });

  test('listed barangay is free, case-insensitive', () {
    final q = quote(km: 5.559, barangays: ['Poblacion'], barangay: ' poblacion ');
    expect(q.freeReason, 'barangay');
  });

  test('enough gallons is free', () {
    expect(quote(km: 5.559, minGallons: 5, gallons: 4).isFree, isFalse);
    expect(quote(km: 5.559, minGallons: 5, gallons: 5).freeReason, 'min_gallons');
  });

  test('unknown location pays the minimum fee', () {
    final q = quote(km: null);
    expect(q.fee, 20);
    expect(q.distanceKm, isNull);
  });

  test('fromServer reads the RPC response', () {
    final q = DeliveryQuote.fromServer({
      'distance_km': 2.4,
      'is_free': false,
      'free_reason': null,
      'fee': 24,
      'rate_per_km': 10,
      'free_radius_km': 1.0,
    });
    expect(q.fee, 24);
    expect(q.distanceKm, 2.4);
    expect(q.isEstimate, isFalse);
  });

  test('label explains the fee', () {
    expect(quote(km: 0.5).label, 'Free delivery · within 1 km');
    expect(quote(km: 5.559).label, '₱72 · 7.2 km');
  });
}
