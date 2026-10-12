import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/payouts/models/payout_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RiderPayoutRequest model tests', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime(2026, 10, 12, 10, 30);
      final req = RiderPayoutRequest(
        id: 'payout-123',
        riderId: 'rider-abc',
        riderName: 'Cardo Dalisay',
        ownerId: 'owner-xyz',
        stationName: 'Cantilan Pure Water',
        amount: 850.50,
        payoutMethod: 'gcash',
        accountNumber: '09123456789',
        accountName: 'Cardo Dalisay',
        status: 'pending',
        createdAt: now,
        updatedAt: now,
      );

      final json = req.toJson();
      expect(json['id'], equals('payout-123'));
      expect(json['amount'], equals(850.50));
      expect(json['payout_method'], equals('gcash'));
      expect(json['status'], equals('pending'));

      final reconstructed = RiderPayoutRequest.fromJson(json);
      expect(reconstructed.id, equals('payout-123'));
      expect(reconstructed.riderName, equals('Cardo Dalisay'));
      expect(reconstructed.amount, equals(850.50));
      expect(reconstructed.accountNumber, equals('09123456789'));
      expect(reconstructed.status, equals('pending'));
    });

    test('copyWith properly updates status and reference number', () {
      final now = DateTime.now();
      final req = RiderPayoutRequest(
        id: 'payout-456',
        riderId: 'rider-abc',
        riderName: 'Cardo Dalisay',
        ownerId: 'owner-xyz',
        amount: 1200.0,
        payoutMethod: 'gcash',
        accountNumber: '09123456789',
        accountName: 'Cardo Dalisay',
        status: 'pending',
        createdAt: now,
        updatedAt: now,
      );

      final disbursed = req.copyWith(
        status: 'disbursed',
        referenceNumber: 'GCASH-REF-998877',
        disbursedAt: now,
      );

      expect(disbursed.status, equals('disbursed'));
      expect(disbursed.referenceNumber, equals('GCASH-REF-998877'));
      expect(disbursed.disbursedAt, equals(now));
      expect(disbursed.amount, equals(1200.0));
    });
  });
}

