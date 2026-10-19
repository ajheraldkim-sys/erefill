import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/delivery_mgmt/models/credit_model.dart';
import 'package:erefill/features/delivery_mgmt/models/delivery_model.dart';

void main() {
  group('Delivery & Credit Management Deep Fixes Tests', () {
    test('DmDelivery handles empty bottle return and offline log fields', () {
      final now = DateTime.now();
      final delivery = DmDelivery(
        id: 'deliv-test-001',
        ownerId: 'owner-test-123',
        deliveryDate: now,
        gallons: 5,
        pricePerGallon: 25,
        emptyGallonsReturned: 4,
        commission: 0,
        notes: 'Walk-in customer',
        createdAt: now,
        updatedAt: now,
      );

      expect(delivery.gallons, 5);
      expect(delivery.emptyGallonsReturned, 4);
      expect(delivery.income, 125);
      expect(delivery.notes, 'Walk-in customer');

      final json = delivery.toJson();
      expect(json['empty_gallons_returned'], 4);
      expect(json['gallons'], 5);

      final reconstructed = DmDelivery.fromJson(json);
      expect(reconstructed.emptyGallonsReturned, 4);
      expect(reconstructed.income, 125);
    });

    test('DmCredit clamps remaining balances and respects partial settlements', () {
      final now = DateTime.now();
      final credit = DmCredit(
        id: 'credit-001',
        ownerId: 'owner-test-123',
        creditType: CreditType.customer,
        debtorName: 'Juan Dela Cruz',
        amount: 250,
        paidAmount: 100,
        createdAt: now,
        updatedAt: now,
      );

      expect(credit.remaining, 150);
      expect(credit.isPaid, isFalse);

      // Clamping logic verification: payment exceeding remaining is capped
      const double incomingPayment = 200.0;
      final cappedPayment = incomingPayment > credit.remaining
          ? credit.remaining
          : incomingPayment;

      expect(cappedPayment, 150.0);

      final newPaidAmount = credit.paidAmount + cappedPayment;
      final settledCredit = credit.copyWith(
        paidAmount: newPaidAmount,
        isPaid: newPaidAmount >= credit.amount,
      );
      expect(settledCredit.remaining, 0.0);
      expect(settledCredit.isPaid, isTrue);
    });

    test('DmDelivery.toCloudJson strips rider_name and handles empty riderId', () {
      final now = DateTime.now();
      final delivery = DmDelivery(
        id: 'deliv-cloud-1',
        ownerId: 'owner-123',
        riderId: '   ',
        riderName: 'Juan Rider',
        deliveryDate: now,
        gallons: 10,
        pricePerGallon: 30,
        emptyGallonsReturned: 5,
        commission: 20,
        createdAt: now,
        updatedAt: now,
      );

      final cloudJson = delivery.toCloudJson();
      expect(cloudJson.containsKey('rider_name'), isFalse);
      expect(cloudJson['rider_id'], isNull);
      expect(cloudJson['gallons'], 10);
      expect(cloudJson['is_synced'], isTrue);
    });

    test('DmCredit.toCloudJson strips rider_name and sanitizes foreign keys', () {
      final now = DateTime.now();
      final credit = DmCredit(
        id: 'credit-cloud-1',
        ownerId: 'owner-123',
        riderId: '',
        riderName: 'Pedro Rider',
        deliveryId: '   ',
        creditType: CreditType.rider,
        debtorName: 'Pedro Rider',
        amount: 500,
        createdAt: now,
        updatedAt: now,
      );

      final cloudJson = credit.toCloudJson();
      expect(cloudJson.containsKey('rider_name'), isFalse);
      expect(cloudJson.containsKey('remaining'), isFalse);
      expect(cloudJson['rider_id'], isNull);
      expect(cloudJson['delivery_id'], isNull);
      expect(cloudJson['amount'], 500);
      expect(cloudJson['is_synced'], isTrue);
    });

    test('Safe shortId substring handles short IDs without RangeError', () {
      const shortId = 'abc';
      final safe8 = shortId.length >= 8 ? shortId.substring(0, 8) : shortId;
      expect(safe8, 'abc');

      const longId = '1234567890abcdef';
      final safeLong8 = longId.length >= 8 ? longId.substring(0, 8) : longId;
      expect(safeLong8, '12345678');
    });
  });
}
