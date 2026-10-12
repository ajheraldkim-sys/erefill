import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/subscriptions/models/subscription_model.dart';

void main() {
  group('CustomerSubscription model tests', () {
    test('computes next delivery date correctly across frequencies', () {
      final baseDate = DateTime(2026, 10, 12, 8, 0);

      final next3Days = CustomerSubscription.computeNextDeliveryDate(
        baseDate,
        'every_3_days',
      );
      expect(next3Days.difference(baseDate).inDays, equals(3));

      final nextWeekly = CustomerSubscription.computeNextDeliveryDate(
        baseDate,
        'weekly',
      );
      expect(nextWeekly.difference(baseDate).inDays, equals(7));

      final nextBiWeekly = CustomerSubscription.computeNextDeliveryDate(
        baseDate,
        'bi_weekly',
      );
      expect(nextBiWeekly.difference(baseDate).inDays, equals(14));

      final nextMonthly = CustomerSubscription.computeNextDeliveryDate(
        baseDate,
        'monthly',
      );
      expect(nextMonthly.month, equals(11));
      expect(nextMonthly.day, equals(12));
    });

    test('serializes and deserializes CustomerSubscription correctly', () {
      final now = DateTime(2026, 10, 12);
      final sub = CustomerSubscription(
        id: 'sub-123',
        customerId: 'cust-abc',
        stationId: 'station-xyz',
        stationName: 'Cantilan Aqua Pure',
        quantity: 3,
        waterType: 'Purified',
        estimatedPrice: 90.0,
        frequency: 'every_3_days',
        preferredTimeSlot: 'morning',
        deliveryAddress: 'Purok 2, Pag-antayan, Cantilan',
        paymentMethod: 'cod',
        isActive: true,
        nextDeliveryDate: now.add(const Duration(days: 3)),
        createdAt: now,
        updatedAt: now,
      );

      final json = sub.toJson();
      expect(json['id'], equals('sub-123'));
      expect(json['quantity'], equals(3));
      expect(json['frequency'], equals('every_3_days'));
      expect(json['is_active'], isTrue);

      final reconstructed = CustomerSubscription.fromJson(json);
      expect(reconstructed.id, equals('sub-123'));
      expect(reconstructed.stationName, equals('Cantilan Aqua Pure'));
      expect(reconstructed.quantity, equals(3));
      expect(reconstructed.estimatedPrice, equals(90.0));
      expect(reconstructed.isActive, isTrue);
    });

    test('format labels produce readable strings', () {
      expect(
        CustomerSubscription.formatFrequencyLabel('every_3_days'),
        equals('Every 3 Days'),
      );
      expect(
        CustomerSubscription.formatFrequencyLabel('weekly'),
        equals('Weekly Refill'),
      );
      expect(
        CustomerSubscription.formatTimeSlotLabel('morning'),
        contains('Morning'),
      );
    });
  });
}

