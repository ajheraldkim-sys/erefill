import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/subscriptions/models/subscription_model.dart';

void main() {
  group('Auto-Order Generation & Subscription Routine Engine', () {
    test('computeNextDeliveryDate rolls forward correctly across frequencies', () {
      final base = DateTime(2026, 10, 1, 10, 0);

      final next3Days = CustomerSubscription.computeNextDeliveryDate(base, 'every_3_days');
      expect(next3Days.difference(base).inDays, equals(3));

      final nextTwiceWeekly = CustomerSubscription.computeNextDeliveryDate(base, 'twice_weekly');
      expect(nextTwiceWeekly.difference(base).inDays, equals(4));

      final nextWeekly = CustomerSubscription.computeNextDeliveryDate(base, 'weekly');
      expect(nextWeekly.difference(base).inDays, equals(7));

      final nextBiWeekly = CustomerSubscription.computeNextDeliveryDate(base, 'bi_weekly');
      expect(nextBiWeekly.difference(base).inDays, equals(14));

      final nextMonthly = CustomerSubscription.computeNextDeliveryDate(base, 'monthly');
      expect(nextMonthly.month, equals(11));
    });

    test('CustomerSubscription serialization and deserialization retains all scheduling fields', () {
      final now = DateTime.now();
      final sub = CustomerSubscription(
        id: 'sub_test_123',
        customerId: 'cust_abc',
        stationId: 'station_xyz',
        stationName: 'Cantilan Aqua Pure',
        quantity: 3,
        waterType: 'Alkaline',
        estimatedPrice: 105.0,
        frequency: 'weekly',
        preferredTimeSlot: 'morning',
        deliveryAddress: 'Purok 2, Magkiangkang, Madrid',
        paymentMethod: 'cod',
        isActive: true,
        nextDeliveryDate: now.add(const Duration(days: 7)),
        createdAt: now,
        updatedAt: now,
      );

      final map = sub.toJson();
      expect(map['id'], equals('sub_test_123'));
      expect(map['customer_id'], equals('cust_abc'));
      expect(map['quantity'], equals(3));
      expect(map['water_type'], equals('Alkaline'));
      expect(map['estimated_price'], equals(105.0));
      expect(map['frequency'], equals('weekly'));
      expect(map['is_active'], isTrue);

      final recovered = CustomerSubscription.fromJson(map);
      expect(recovered.id, equals(sub.id));
      expect(recovered.stationName, equals('Cantilan Aqua Pure'));
      expect(recovered.estimatedPrice, equals(105.0));
      expect(recovered.preferredTimeSlot, equals('morning'));
      expect(recovered.isActive, isTrue);
    });

    test('Subscription frequency and time slot human-readable labels', () {
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
      expect(
        CustomerSubscription.formatTimeSlotLabel('afternoon'),
        contains('Afternoon'),
      );
    });
  });
}

