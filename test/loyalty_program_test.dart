import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/loyalty/models/loyalty_model.dart';
import 'package:erefill/features/loyalty/services/loyalty_service.dart';

void main() {
  group('Customer Loyalty & Referral Program', () {
    test('LoyaltyProfile model serialization and copyWith', () {
      final now = DateTime.now();
      final profile = LoyaltyProfile(
        userId: 'user_loyalty_1',
        referralCode: 'EREF-ABC123',
        pointsBalance: 120,
        totalEarned: 170,
        totalRedeemed: 50,
        referredBy: 'EREF-FRIEND',
        updatedAt: now,
      );

      final map = profile.toJson();
      expect(map['user_id'], equals('user_loyalty_1'));
      expect(map['referral_code'], equals('EREF-ABC123'));
      expect(map['points_balance'], equals(120));
      expect(map['total_earned'], equals(170));
      expect(map['total_redeemed'], equals(50));
      expect(map['referred_by'], equals('EREF-FRIEND'));

      final recovered = LoyaltyProfile.fromJson(map);
      expect(recovered.userId, equals(profile.userId));
      expect(recovered.pointsBalance, equals(120));

      final updated = recovered.copyWith(pointsBalance: 180, totalEarned: 230);
      expect(updated.pointsBalance, equals(180));
      expect(updated.totalEarned, equals(230));
      expect(updated.referralCode, equals('EREF-ABC123'));
    });

    test('LoyaltyRewardVoucher creation, redemption validity, and serialization', () {
      final now = DateTime.now();
      final voucher = LoyaltyRewardVoucher(
        id: 'vouch_1',
        userId: 'user_test',
        code: 'REWARD-20OFF-1234',
        title: '₱20 Off Water Refill',
        description: 'Deduct ₱20 from order',
        discountAmount: 20.0,
        pointsCost: 100,
        isDeliveryDiscount: false,
        isUsed: false,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 30)),
      );

      final json = voucher.toJson();
      expect(json['code'], equals('REWARD-20OFF-1234'));
      expect(json['discount_amount'], equals(20.0));
      expect(json['points_cost'], equals(100));
      expect(json['is_used'], isFalse);

      final recovered = LoyaltyRewardVoucher.fromJson(json);
      expect(recovered.id, equals('vouch_1'));
      expect(recovered.isUsed, isFalse);
      expect(recovered.expiresAt.isAfter(now), isTrue);
    });

    test('LoyaltyTransaction model tracking points', () {
      final now = DateTime.now();
      final tx = LoyaltyTransaction(
        id: 'tx_1',
        userId: 'user_1',
        points: 50,
        description: 'Welcome Bonus',
        createdAt: now,
      );

      final map = tx.toJson();
      expect(map['points'], equals(50));
      expect(map['description'], equals('Welcome Bonus'));

      final recovered = LoyaltyTransaction.fromJson(map);
      expect(recovered.points, equals(50));
    });

    test('Reward catalog contains valid redemption items', () {
      final catalog = LoyaltyService.rewardCatalog;
      expect(catalog.isNotEmpty, isTrue);
      for (final reward in catalog) {
        expect(reward.title.isNotEmpty, isTrue);
        expect(reward.pointsCost, greaterThan(0));
        expect(reward.discountAmount, greaterThan(0));
      }
    });
  });
}

