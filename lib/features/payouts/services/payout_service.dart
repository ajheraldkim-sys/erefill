import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/local_data_cache.dart';
import '../models/payout_model.dart';

class PayoutService {
  final SupabaseClient _supabase;
  final LocalDataCache _cache = LocalDataCache.instance;

  PayoutService([SupabaseClient? client])
      : _supabase = client ?? Supabase.instance.client;

  /// Fetch requests for a rider (with instant offline cache fallback)
  Future<List<RiderPayoutRequest>> getRiderPayoutRequests(String riderId) async {
    final cacheKey = 'rider_payouts_$riderId';
    final mem = _cache.getMemory<List<dynamic>>(cacheKey);
    List<RiderPayoutRequest> localList = [];
    if (mem != null) {
      localList = mem
          .map((item) =>
              RiderPayoutRequest.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } else {
      final cached = await _cache.get<List<dynamic>>(cacheKey);
      if (cached != null) {
        localList = cached
            .map((item) =>
                RiderPayoutRequest.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    }

    try {
      final res = await _supabase
          .from('rider_payout_requests')
          .select()
          .eq('rider_id', riderId)
          .order('created_at', ascending: false);
      final freshList = res
          .map((item) => RiderPayoutRequest.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
      await _cache.set(cacheKey, res);
      return freshList;
    } catch (e) {
      if (kDebugMode && !e.toString().contains('PGRST205')) {
        debugPrint('Supabase getRiderPayoutRequests fallback: $e');
      }
    }

    return localList;
  }

  /// Create a new payout request
  Future<RiderPayoutRequest> createPayoutRequest({
    required String riderId,
    required String riderName,
    required String ownerId,
    String? stationName,
    required double amount,
    required String payoutMethod,
    required String accountNumber,
    required String accountName,
  }) async {
    final req = RiderPayoutRequest(
      id: const Uuid().v4(),
      riderId: riderId,
      riderName: riderName,
      ownerId: ownerId,
      stationName: stationName,
      amount: amount,
      payoutMethod: payoutMethod,
      accountNumber: accountNumber,
      accountName: accountName,
      status: 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Save in local cache first (instant offline-first)
    final cacheKey = 'rider_payouts_$riderId';
    final cached = (await _cache.get<List<dynamic>>(cacheKey)) ?? [];
    final updatedList = [req.toJson(), ...cached];
    await _cache.set(cacheKey, updatedList);

    // Also update owner's pending list cache
    final ownerKey = 'owner_payouts_$ownerId';
    final ownerCached = (await _cache.get<List<dynamic>>(ownerKey)) ?? [];
    await _cache.set(ownerKey, [req.toJson(), ...ownerCached]);

    // Try remote insert
    try {
      final payload = Map<String, dynamic>.from(req.toJson());
      if (payload['owner_id'] == null || payload['owner_id'].toString().trim().isEmpty) {
        payload.remove('owner_id');
      }
      await _supabase.from('rider_payout_requests').insert(payload);
    } catch (e) {
      debugPrint('Saved payout request locally. Supabase insert deferred/fallback: $e');
    }

    return req;
  }

  /// Get pending and processed payout requests for station owner
  Future<List<RiderPayoutRequest>> getOwnerPayoutRequests(String ownerId) async {
    final cacheKey = 'owner_payouts_$ownerId';
    final mem = _cache.getMemory<List<dynamic>>(cacheKey);
    List<RiderPayoutRequest> localList = [];
    if (mem != null) {
      localList = mem
          .map((item) =>
              RiderPayoutRequest.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } else {
      final cached = await _cache.get<List<dynamic>>(cacheKey);
      if (cached != null) {
        localList = cached
            .map((item) =>
                RiderPayoutRequest.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    }

    try {
      final res = await _supabase
          .from('rider_payout_requests')
          .select()
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false);
      final freshList = res
          .map((item) => RiderPayoutRequest.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
      await _cache.set(cacheKey, res);
      return freshList;
    } catch (e) {
      if (kDebugMode && !e.toString().contains('PGRST205')) {
        debugPrint('Supabase getOwnerPayoutRequests fallback: $e');
      }
    }

    return localList;
  }

  /// Process payout request (Approve, Disburse, or Reject)
  Future<void> updatePayoutStatus({
    required String requestId,
    required String riderId,
    required String ownerId,
    required String newStatus,
    String? referenceNumber,
    String? rejectionReason,
  }) async {
    final updateData = <String, dynamic>{
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
      'reference_number':? referenceNumber,
      'rejection_reason':? rejectionReason,
      if (newStatus == 'disbursed')
        'disbursed_at': DateTime.now().toIso8601String(),
    };

    // Update in local cache
    for (final key in ['rider_payouts_$riderId', 'owner_payouts_$ownerId']) {
      final cached = await _cache.get<List<dynamic>>(key);
      if (cached != null) {
        final updated = cached.map((item) {
          if (item is Map && item['id'] == requestId) {
            return {...item, ...updateData};
          }
          return item;
        }).toList();
        await _cache.set(key, updated);
      }
    }

    // Try remote update
    try {
      await _supabase
          .from('rider_payout_requests')
          .update(updateData)
          .eq('id', requestId);
    } catch (e) {
      debugPrint('Supabase updatePayoutStatus deferred/fallback: $e');
    }
  }

  /// Get Owner Digital Wallet Summary (digital sales, rider payout obligations, available balance)
  Future<OwnerWalletSummary> getOwnerWalletSummary(String ownerId) async {
    final cacheKey = 'owner_wallet_summary_$ownerId';
    final cached = await _cache.get<Map<String, dynamic>>(cacheKey);
    OwnerWalletSummary summary = cached != null
        ? OwnerWalletSummary.fromJson(cached)
        : OwnerWalletSummary.empty();

    try {
      // 1. Fetch digital orders for this station owner
      final ordersRes = await _supabase
          .from('orders')
          .select('id, total_amount, payment_method, payment_status, status, created_at, customer_address')
          .eq('owner_id', ownerId)
          .neq('payment_method', 'cod')
          .order('created_at', ascending: false)
          .limit(50);

      double digitalEarnings = 0.0;
      int digitalCount = 0;
      final recentTxs = <Map<String, dynamic>>[];

      for (final o in ordersRes) {
        final amt = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        final pStatus = o['payment_status']?.toString().toLowerCase();
        final oStatus = o['status']?.toString().toLowerCase();
        final isDeliveredOrPaid = pStatus == 'paid' || oStatus == 'delivered' || oStatus == 'completed';

        if (isDeliveredOrPaid) {
          digitalEarnings += amt;
          digitalCount++;
        }
        recentTxs.add({
          'id': o['id'],
          'amount': amt,
          'payment_method': o['payment_method'],
          'status': o['status'],
          'payment_status': o['payment_status'],
          'created_at': o['created_at'],
        });
      }

      // 2. Fetch rider payout requests
      final payoutRequests = await getOwnerPayoutRequests(ownerId);
      double pendingRider = 0.0;
      double completedRider = 0.0;

      for (final req in payoutRequests) {
        if (req.status == 'pending') {
          pendingRider += req.amount;
        } else if (req.status == 'disbursed') {
          completedRider += req.amount;
        }
      }

      final available = (digitalEarnings - completedRider - pendingRider).clamp(0.0, double.infinity);

      summary = OwnerWalletSummary(
        totalDigitalEarnings: digitalEarnings,
        pendingRiderDisbursements: pendingRider,
        completedRiderDisbursements: completedRider,
        availableBalance: available,
        totalDigitalOrders: digitalCount,
        recentTransactions: recentTxs,
      );

      await _cache.set(cacheKey, summary.toJson());
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PayoutService getOwnerWalletSummary fallback: $e');
      }
    }

    return summary;
  }
}

