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
          .map((item) =>
              CustomerSubscription.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }

    try {
      final res = await _supabase
          .from('customer_subscriptions')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      final freshList = (res as List)
          .map((item) => CustomerSubscription.fromJson(
              Map<String, dynamic>.from(item as Map)))
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
    } catch (e) {
      debugPrint('Saved subscription locally. Supabase insert deferred/fallback: $e');
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
    } catch (e) {
      debugPrint('Supabase toggleSubscription fallback: $e');
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
    } catch (e) {
      debugPrint('Supabase deleteSubscription fallback: $e');
    }
  }

  /// Update the next delivery date of a subscription
  Future<void> updateSubscriptionNextDeliveryDate({
    required String subscriptionId,
    required String customerId,
    required DateTime nextDate,
  }) async {
    final cacheKey = 'customer_subscriptions_$customerId';
    final cached = await _cache.get<List<dynamic>>(cacheKey);
    if (cached != null) {
      final updated = cached.map((item) {
        if (item is Map && item['id'] == subscriptionId) {
          return {
            ...item,
            'next_delivery_date': nextDate.toIso8601String(),
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
            'next_delivery_date': nextDate.toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', subscriptionId);
    } catch (e) {
      debugPrint('Supabase updateSubscriptionNextDeliveryDate fallback: $e');
    }
  }

  /// Process all subscriptions that are due for delivery
  /// Generates real orders idempotently and rolls forward the next delivery date.
  Future<List<Map<String, dynamic>>> processDueSubscriptions({
    String? customerId,
    String? stationId,
  }) async {
    final generatedOrders = <Map<String, dynamic>>[];
    final now = DateTime.now();

    List<CustomerSubscription> candidates = [];
    if (customerId != null) {
      candidates = await getCustomerSubscriptions(customerId);
    } else {
      try {
        var query = _supabase
            .from('customer_subscriptions')
            .select()
            .eq('is_active', true);
        if (stationId != null) {
          query = query.eq('station_id', stationId);
        }
        final res = await query;
        candidates = (res as List)
            .map((item) => CustomerSubscription.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
      } catch (e) {
        debugPrint('Failed to query all due subscriptions: $e');
      }
    }

    final dueSubs = candidates.where((sub) {
      if (!sub.isActive) return false;
      // If next delivery date is today or in the past (allowing 5 minute buffer)
      return sub.nextDeliveryDate.isBefore(now.add(const Duration(minutes: 5)));
    }).toList();

    for (final sub in dueSubs) {
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final idempotencyKey = 'auto_sub_${sub.id}_$dateKey';

      // Verify idempotency to prevent duplicate orders
      bool alreadyCreated = false;
      try {
        final existing = await _supabase
            .from('orders')
            .select('id')
            .eq('idempotency_key', idempotencyKey)
            .maybeSingle();
        if (existing != null) {
          alreadyCreated = true;
        }
      } catch (_) {}

      final orderId = const Uuid().v4();
      final orderData = {
        'id': orderId,
        'customer_id': sub.customerId,
        'owner_id': sub.stationId,
        'station_name': sub.stationName,
        'customer_address': sub.deliveryAddress,
        'idempotency_key': idempotencyKey,
        'subtotal': sub.estimatedPrice,
        'delivery_fee': 0.0,
        'total_amount': sub.estimatedPrice,
        'payment_method': sub.paymentMethod,
        'status': 'pending',
        'notes':
            'Auto-Refill Routine (${CustomerSubscription.formatFrequencyLabel(sub.frequency)}) - Slot: ${CustomerSubscription.formatTimeSlotLabel(sub.preferredTimeSlot)}',
        'created_at': now.toIso8601String(),
      };

      final itemsData = [
        {
          'order_id': orderId,
          'product_name': '${sub.waterType} Refill',
          'water_type': sub.waterType,
          'quantity': sub.quantity,
          'price_per_gallon':
              sub.quantity > 0 ? (sub.estimatedPrice / sub.quantity) : sub.estimatedPrice,
          'unit_price':
              sub.quantity > 0 ? (sub.estimatedPrice / sub.quantity) : sub.estimatedPrice,
          'total_price': sub.estimatedPrice,
        }
      ];

      if (!alreadyCreated) {
        try {
          await _supabase.rpc('create_order_atomic', params: {
            'p_order_data': orderData,
            'p_items_data': itemsData,
          });
          generatedOrders.add(orderData);
        } catch (e) {
          debugPrint('Atomic order generation fallback: $e');
          try {
            await _supabase.from('orders').insert(orderData);
            await _supabase.from('order_items').insert(itemsData);
            generatedOrders.add(orderData);
          } catch (insertErr) {
            debugPrint('Manual order generation fallback: $insertErr');
          }
        }
      }

      // Roll forward the next delivery date
      DateTime nextDate = CustomerSubscription.computeNextDeliveryDate(
        sub.nextDeliveryDate,
        sub.frequency,
      );
      while (nextDate.isBefore(now)) {
        nextDate = CustomerSubscription.computeNextDeliveryDate(
          nextDate,
          sub.frequency,
        );
      }

      await updateSubscriptionNextDeliveryDate(
        subscriptionId: sub.id,
        customerId: sub.customerId,
        nextDate: nextDate,
      );
    }

    return generatedOrders;
  }
}


