import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/local_data_cache.dart';
import '../models/loyalty_model.dart';

class LoyaltyService {
  final SupabaseClient _supabase;
  final LocalDataCache _cache = LocalDataCache.instance;

  LoyaltyService([SupabaseClient? client])
      : _supabase = client ?? Supabase.instance.client;

  /// Default catalog of redeemable reward voucher templates
  static final List<LoyaltyRewardVoucher> rewardCatalog = [
    LoyaltyRewardVoucher(
      id: 'template_20_off',
      userId: '',
      code: 'REWARD-20OFF',
      title: '₱20 Off Water Refill',
      description: 'Deduct ₱20 from your next delivery order',
      discountAmount: 20.0,
      pointsCost: 100,
      isDeliveryDiscount: false,
      isUsed: false,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    ),
    LoyaltyRewardVoucher(
      id: 'template_free_delivery',
      userId: '',
      code: 'REWARD-FREEDELIVERY',
      title: 'Free Delivery Voucher',
      description: 'Waives the delivery fee up to ₱25 on your order',
      discountAmount: 25.0,
      pointsCost: 150,
      isDeliveryDiscount: true,
      isUsed: false,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    ),
    LoyaltyRewardVoucher(
      id: 'template_50_off',
      userId: '',
      code: 'REWARD-50OFF',
      title: '₱50 Super Saver Voucher',
      description: 'Deduct ₱50 from refill orders of 2 or more bottles',
      discountAmount: 50.0,
      pointsCost: 250,
      isDeliveryDiscount: false,
      isUsed: false,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    ),
    LoyaltyRewardVoucher(
      id: 'template_100_off',
      userId: '',
      code: 'REWARD-100OFF',
      title: '₱100 Family Pack Voucher',
      description: 'Deduct ₱100 from bulk refill orders',
      discountAmount: 100.0,
      pointsCost: 450,
      isDeliveryDiscount: false,
      isUsed: false,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    ),
  ];

  static String _generateReferralCode(String userId) {
    final cleanId = userId.replaceAll('-', '').toUpperCase();
    final suffix = cleanId.length >= 6
        ? cleanId.substring(0, 6)
        : '${cleanId}123456'.substring(0, 6);
    return 'EREF-$suffix';
  }

  /// Get or create the user's loyalty profile
  Future<LoyaltyProfile> getLoyaltyProfile(String userId) async {
    final cacheKey = 'loyalty_profile_$userId';
    final cached = await _cache.get<Map<String, dynamic>>(cacheKey);
    LoyaltyProfile? profile;
    if (cached != null) {
      profile = LoyaltyProfile.fromJson(cached);
    }

    try {
      final res = await _supabase
          .from('customer_loyalty_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (res != null) {
        final loaded = LoyaltyProfile.fromJson(Map<String, dynamic>.from(res));
        await _cache.set(cacheKey, loaded.toJson());
        return loaded;
      } else {
        // Create initial profile with welcome bonus
        final referralCode = _generateReferralCode(userId);
        final initialProfile = LoyaltyProfile(
          userId: userId,
          referralCode: referralCode,
          pointsBalance: 50, // 50 pts welcome bonus
          totalEarned: 50,
          totalRedeemed: 0,
          updatedAt: DateTime.now(),
        );

        await _cache.set(cacheKey, initialProfile.toJson());

        try {
          await _supabase
              .from('customer_loyalty_profiles')
              .insert(initialProfile.toJson());

          await _recordTransaction(
            userId: userId,
            points: 50,
            description: 'Welcome to eRefill Loyalty Bonus',
          );
        } catch (e) {
          debugPrint('Supabase initial loyalty profile insert fallback: $e');
        }

        return initialProfile;
      }
    } catch (e) {
      debugPrint('Supabase getLoyaltyProfile fallback: $e');
    }

    if (profile != null) return profile;

    // Fallback if completely offline
    final defaultProfile = LoyaltyProfile(
      userId: userId,
      referralCode: _generateReferralCode(userId),
      pointsBalance: 50,
      totalEarned: 50,
      totalRedeemed: 0,
      updatedAt: DateTime.now(),
    );
    await _cache.set(cacheKey, defaultProfile.toJson());
    return defaultProfile;
  }

  /// Get user transaction history
  Future<List<LoyaltyTransaction>> getTransactions(String userId) async {
    final cacheKey = 'loyalty_transactions_$userId';
    final cached = await _cache.get<List<dynamic>>(cacheKey);
    List<LoyaltyTransaction> localList = [];
    if (cached != null) {
      localList = cached
          .map((item) =>
              LoyaltyTransaction.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }

    try {
      final res = await _supabase
          .from('loyalty_transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      final freshList = (res as List)
          .map((item) =>
              LoyaltyTransaction.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      await _cache.set(cacheKey, res);
      return freshList;
    } catch (e) {
      debugPrint('Supabase getTransactions fallback: $e');
    }

    return localList;
  }

  /// Get user's active / unused reward vouchers
  Future<List<LoyaltyRewardVoucher>> getUserVouchers(String userId) async {
    final cacheKey = 'customer_vouchers_$userId';
    final cached = await _cache.get<List<dynamic>>(cacheKey);
    List<LoyaltyRewardVoucher> localList = [];
    if (cached != null) {
      localList = cached
          .map((item) => LoyaltyRewardVoucher.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .where((v) => !v.isUsed && v.expiresAt.isAfter(DateTime.now()))
          .toList();
    }

    try {
      final res = await _supabase
          .from('customer_reward_vouchers')
          .select()
          .eq('user_id', userId)
          .eq('is_used', false)
          .order('created_at', ascending: false);

      final freshList = (res as List)
          .map((item) => LoyaltyRewardVoucher.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .where((v) => v.expiresAt.isAfter(DateTime.now()))
          .toList();
      await _cache.set(cacheKey, res);
      return freshList;
    } catch (e) {
      debugPrint('Supabase getUserVouchers fallback: $e');
    }

    return localList;
  }

  /// Redeem a reward voucher with loyalty points
  Future<LoyaltyRewardVoucher?> redeemReward({
    required String userId,
    required LoyaltyRewardVoucher template,
  }) async {
    final profile = await getLoyaltyProfile(userId);
    if (profile.pointsBalance < template.pointsCost) {
      return null;
    }

    final newBalance = profile.pointsBalance - template.pointsCost;
    final newTotalRedeemed = profile.totalRedeemed + template.pointsCost;

    final voucherCode =
        '${template.code}-${1000 + Random().nextInt(9000)}'.toUpperCase();
    final newVoucher = LoyaltyRewardVoucher(
      id: const Uuid().v4(),
      userId: userId,
      code: voucherCode,
      title: template.title,
      description: template.description,
      discountAmount: template.discountAmount,
      pointsCost: template.pointsCost,
      isDeliveryDiscount: template.isDeliveryDiscount,
      isUsed: false,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

    // Update profile
    final updatedProfile = profile.copyWith(
      pointsBalance: newBalance,
      totalRedeemed: newTotalRedeemed,
    );
    await _cache.set('loyalty_profile_$userId', updatedProfile.toJson());

    // Update vouchers cache
    final vouchersCacheKey = 'customer_vouchers_$userId';
    final cachedVouchers =
        (await _cache.get<List<dynamic>>(vouchersCacheKey)) ?? [];
    await _cache.set(vouchersCacheKey, [newVoucher.toJson(), ...cachedVouchers]);

    // Record transaction
    await _recordTransaction(
      userId: userId,
      points: -template.pointsCost,
      description: 'Redeemed: ${template.title}',
    );

    try {
      await _supabase.from('customer_loyalty_profiles').update({
        'points_balance': newBalance,
        'total_redeemed': newTotalRedeemed,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);

      await _supabase
          .from('customer_reward_vouchers')
          .insert(newVoucher.toJson());
    } catch (e) {
      debugPrint('Supabase redeemReward fallback: $e');
    }

    return newVoucher;
  }

  /// Apply a friend's referral code
  Future<bool> applyReferralCode({
    required String userId,
    required String enteredCode,
  }) async {
    final trimmedCode = enteredCode.trim().toUpperCase();
    final profile = await getLoyaltyProfile(userId);

    if (profile.referralCode.toUpperCase() == trimmedCode) {
      throw StateError('You cannot enter your own referral code.');
    }
    if (profile.referredBy != null && profile.referredBy!.isNotEmpty) {
      throw StateError('You have already redeemed a referral code.');
    }

    // Try finding referrer
    String? referrerUserId;
    try {
      final res = await _supabase
          .from('customer_loyalty_profiles')
          .select('user_id, points_balance, total_earned')
          .eq('referral_code', trimmedCode)
          .maybeSingle();

      if (res != null) {
        referrerUserId = res['user_id']?.toString();
        final refBalance = (res['points_balance'] as num?)?.toInt() ?? 0;
        final refEarned = (res['total_earned'] as num?)?.toInt() ?? 0;

        // Give referrer +50 bonus points
        await _supabase.from('customer_loyalty_profiles').update({
          'points_balance': refBalance + 50,
          'total_earned': refEarned + 50,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('user_id', referrerUserId!);

        await _recordTransaction(
          userId: referrerUserId,
          points: 50,
          description: 'Friend Referral Bonus: Someone joined with your code!',
        );
      }
    } catch (e) {
      debugPrint('Referral lookup fallback: $e');
    }

    // Award user +50 bonus points
    final newBalance = profile.pointsBalance + 50;
    final newEarned = profile.totalEarned + 50;
    final updatedProfile = profile.copyWith(
      pointsBalance: newBalance,
      totalEarned: newEarned,
      referredBy: trimmedCode,
    );

    await _cache.set('loyalty_profile_$userId', updatedProfile.toJson());
    await _recordTransaction(
      userId: userId,
      points: 50,
      description: 'Referral Bonus: Joined using code $trimmedCode',
    );

    try {
      await _supabase.from('customer_loyalty_profiles').update({
        'points_balance': newBalance,
        'total_earned': newEarned,
        'referred_by': trimmedCode,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);
    } catch (e) {
      debugPrint('Update profile referral fallback: $e');
    }

    return true;
  }

  /// Award points for a completed order (1 point per ₱10)
  Future<void> earnPointsForOrder({
    required String userId,
    required double orderAmount,
  }) async {
    final earned = (orderAmount / 10).floor();
    if (earned <= 0) return;

    final profile = await getLoyaltyProfile(userId);
    final newBalance = profile.pointsBalance + earned;
    final newEarned = profile.totalEarned + earned;

    final updated = profile.copyWith(
      pointsBalance: newBalance,
      totalEarned: newEarned,
    );
    await _cache.set('loyalty_profile_$userId', updated.toJson());

    await _recordTransaction(
      userId: userId,
      points: earned,
      description: 'Order Reward: ₱${orderAmount.toStringAsFixed(2)} spent',
    );

    try {
      await _supabase.from('customer_loyalty_profiles').update({
        'points_balance': newBalance,
        'total_earned': newEarned,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);
    } catch (e) {
      debugPrint('Earn points for order fallback: $e');
    }
  }

  /// Mark a voucher as used after order placement
  Future<void> markVoucherUsed({
    required String voucherId,
    required String userId,
  }) async {
    final vouchersCacheKey = 'customer_vouchers_$userId';
    final cached = await _cache.get<List<dynamic>>(vouchersCacheKey);
    if (cached != null) {
      final updated = cached.map((item) {
        if (item is Map && item['id'] == voucherId) {
          return {...item, 'is_used': true};
        }
        return item;
      }).toList();
      await _cache.set(vouchersCacheKey, updated);
    }

    try {
      await _supabase
          .from('customer_reward_vouchers')
          .update({'is_used': true})
          .eq('id', voucherId);
    } catch (e) {
      debugPrint('Supabase markVoucherUsed fallback: $e');
    }
  }

  Future<void> _recordTransaction({
    required String userId,
    required int points,
    required String description,
  }) async {
    final tx = LoyaltyTransaction(
      id: const Uuid().v4(),
      userId: userId,
      points: points,
      description: description,
      createdAt: DateTime.now(),
    );

    final cacheKey = 'loyalty_transactions_$userId';
    final cached = (await _cache.get<List<dynamic>>(cacheKey)) ?? [];
    await _cache.set(cacheKey, [tx.toJson(), ...cached]);

    try {
      await _supabase.from('loyalty_transactions').insert(tx.toJson());
    } catch (e) {
      debugPrint('Supabase recordTransaction fallback: $e');
    }
  }
}
