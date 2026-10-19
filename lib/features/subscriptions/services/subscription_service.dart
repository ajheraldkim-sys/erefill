import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/local_data_cache.dart';
import '../models/subscription_model.dart';

class SubscriptionService {
  final SupabaseClient _supabase;
  final LocalDataCache _cache = LocalDataCache.instance;

  SubscriptionService([SupabaseClient? client])
    : _supabase = client ?? Supabase.instance.client;

  /// Fetch all auto-refill subscriptions for a customer
  Future<List<CustomerSubscription>> getCustomerSubscriptions(
    String customerId,
  ) async {
    final cacheKey = 'customer_subscriptions_$customerId';
    final cached = await _cache.get<List<dynamic>>(cacheKey);
    List<CustomerSubscription> localList = [];
    if (cached != null) {
      localList = cached
          .map(
            (item) => CustomerSubscription.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    }

    try {
      final res = await _supabase
          .from('customer_subscriptions')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      final freshList = (res as List)
          .map(
            (item) => CustomerSubscription.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      await _cache.set(cacheKey, res);
      return freshList;
    } catch (e) {
      debugPrint('Supabase getCustomerSubscriptions fallback: $e');
    }

    return localList;
  }

  /// Create a recurring subscription
  Future<CustomerSubscription> createSubscription({
    required String customerId,
    required String stationId,
    required String stationName,
    String? stationPhotoUrl,
    String? productId,
    required int quantity,
    required String waterType,
    required double estimatedPrice,
    required String frequency,
    required String preferredTimeSlot,
    required String deliveryAddress,
    String paymentMethod = 'cod',
  }) async {
    final nextDate = CustomerSubscription.computeNextDeliveryDate(
      DateTime.now(),
      frequency,
    );

    final sub = CustomerSubscription(
      id: const Uuid().v4(),
      customerId: customerId,
      stationId: stationId,
      stationName: stationName,
      stationPhotoUrl: stationPhotoUrl,
      productId: productId,
      quantity: quantity,
      waterType: waterType,
      estimatedPrice: estimatedPrice,
      frequency: frequency,
      preferredTimeSlot: preferredTimeSlot,
      deliveryAddress: deliveryAddress,
      paymentMethod: paymentMethod,
      isActive: true,
      nextDeliveryDate: nextDate,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Save locally first for 0ms offline responsiveness
    final cacheKey = 'customer_subscriptions_$customerId';
    final cached = (await _cache.get<List<dynamic>>(cacheKey)) ?? [];
    final updatedList = [sub.toJson(), ...cached];
    await _cache.set(cacheKey, updatedList);

    try {
      await _supabase.from('customer_subscriptions').insert(sub.toJson());
    } catch (_) {
      // Nothing syncs a cache-only routine later and the server generator
      // never sees it, so undo the optimistic entry and let the caller show
      // the failure instead of a false "scheduled".
      await _cache.set(cacheKey, cached);
      rethrow;
    }

    return sub;
  }

  /// Pause or resume subscription
  Future<void> toggleSubscription({
    required String subscriptionId,
    required String customerId,
    required bool isActive,
  }) async {
    final cacheKey = 'customer_subscriptions_$customerId';
    final cached = await _cache.get<List<dynamic>>(cacheKey);
    if (cached != null) {
      final updated = cached.map((item) {
        if (item is Map && item['id'] == subscriptionId) {
          return {
            ...item,
            'is_active': isActive,
            'updated_at': DateTime.now().toIso8601String(),
          };
        }
        return item;
      }).toList();
      await _cache.set(cacheKey, updated);
    }

    try {
      await _supabase
          .from('customer_subscriptions')
          .update({
            'is_active': isActive,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', subscriptionId);
    } catch (_) {
      // The server keeps generating orders for a routine it still sees as
      // active, so never leave the app showing a pause that did not happen.
      if (cached != null) await _cache.set(cacheKey, cached);
      rethrow;
    }
  }

  /// Delete a subscription
  Future<void> deleteSubscription({
    required String subscriptionId,
    required String customerId,
  }) async {
    final cacheKey = 'customer_subscriptions_$customerId';
    final cached = await _cache.get<List<dynamic>>(cacheKey);
    if (cached != null) {
      final updated = cached
          .where((item) => item is Map && item['id'] != subscriptionId)
          .toList();
      await _cache.set(cacheKey, updated);
    }

    try {
      await _supabase
          .from('customer_subscriptions')
          .delete()
          .eq('id', subscriptionId);
    } catch (_) {
      if (cached != null) await _cache.set(cacheKey, cached);
      rethrow;
    }
  }

  /// Generates orders for subscriptions that are due, scoped to one customer
  /// or one station.
  ///
  /// Pricing, idempotency and schedule roll-forward all happen server-side in
  /// `generate_due_subscription_orders`, which prices each order like checkout
  /// (live product price, station delivery fee, platform fee). A subscription
  /// that cannot be fulfilled (product or station unavailable) is reported in
  /// [SubscriptionRunResult.skipped] and stays due. Errors propagate: there is
  /// deliberately no client-side fallback that writes orders.
  Future<SubscriptionRunResult> processDueSubscriptions({
    String? customerId,
    String? stationId,
  }) async {
    final response = await _supabase.rpc(
      'generate_due_subscription_orders',
      params: {'p_customer_id': ?customerId, 'p_station_id': ?stationId},
    );
    return SubscriptionRunResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}

/// Outcome of one [SubscriptionService.processDueSubscriptions] run.
class SubscriptionRunResult {
  const SubscriptionRunResult({required this.created, required this.skipped});

  /// Orders created in this run (`id`, `subscription_id`, `total_amount`, ...).
  final List<Map<String, dynamic>> created;
  final List<SkippedSubscription> skipped;

  factory SubscriptionRunResult.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(Object? value) =>
        (value as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
    return SubscriptionRunResult(
      created: maps(json['created']),
      skipped: maps(json['skipped']).map(SkippedSubscription.fromJson).toList(),
    );
  }
}

/// A due subscription the server could not fulfil this run.
class SkippedSubscription {
  const SkippedSubscription({
    required this.subscriptionId,
    required this.reason,
  });

  final String subscriptionId;

  /// `product_unavailable`, `station_unavailable` or `payment_method_unavailable`.
  final String reason;

  factory SkippedSubscription.fromJson(Map<String, dynamic> json) =>
      SkippedSubscription(
        subscriptionId: json['subscription_id']?.toString() ?? '',
        reason: json['reason']?.toString() ?? 'unknown',
      );

  String get message {
    switch (reason) {
      case 'product_unavailable':
        return 'the refill product is no longer available at this station';
      case 'station_unavailable':
        return 'the station is currently closed';
      case 'payment_method_unavailable':
        return 'the station no longer accepts this payment method';
      default:
        return 'the station could not accept the order';
    }
  }
}
