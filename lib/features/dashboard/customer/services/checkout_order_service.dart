import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// One cart line as sent to `create_order_atomic`. The server looks up the
/// price itself; the client only says what and how many.
class CheckoutLineItem {
  const CheckoutLineItem({
    required this.productId,
    required this.name,
    required this.quantity,
  });

  final String productId;
  final String name;
  final int quantity;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'product_name': name,
    'quantity': quantity,
  };
}

/// Everything checkout knows when the customer taps "Place order".
///
/// Prices here are the client's estimate for display and offline queueing;
/// `create_order_atomic` recomputes subtotal, fees and total server-side.
class CheckoutOrderRequest {
  const CheckoutOrderRequest({
    required this.customerId,
    required this.stationId,
    required this.stationName,
    required this.customerName,
    required this.profile,
    required this.paymentMethod,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.deliveryDistanceKm,
    required this.deliveryRatePerKm,
    required this.totalAmount,
    required this.voucherId,
    required this.containerOption,
    required this.scheduleForNextOpen,
    required this.stationOpeningTime,
    required this.userNotes,
  });

  final String? customerId;
  final Object? stationId;
  final String stationName;
  final String customerName;

  /// The customer's delivery profile; must already pass
  /// `CheckoutRules.validate` (address and coordinates present).
  final Map<String, dynamic> profile;
  final String paymentMethod;
  final List<CheckoutLineItem> items;
  final double subtotal;
  final double deliveryFee;
  final double? deliveryDistanceKm;
  final double? deliveryRatePerKm;
  final double totalAmount;
  final String? voucherId;

  /// `swap` (1-to-1 bottle exchange) or anything else (new container).
  final String containerOption;
  final bool scheduleForNextOpen;
  final String? stationOpeningTime;
  final String userNotes;

  String get address => profile['complete_address'].toString().trim();
  double get latitude => (profile['latitude'] as num).toDouble();
  double get longitude => (profile['longitude'] as num).toDouble();

  List<Map<String, dynamic>> get itemsData =>
      items.map((item) => item.toJson()).toList();

  /// Identifies "the same order". Checkout reuses its idempotency key while
  /// this is unchanged, so a retry after a dropped response cannot create a
  /// second order. Item order does not matter.
  String get fingerprint {
    final sortedItems = [...itemsData]
      ..sort(
        (a, b) =>
            a['product_id'].toString().compareTo(b['product_id'].toString()),
      );
    return jsonEncode({
      'customer_id': customerId,
      'station_id': stationId,
      'payment_method': paymentMethod,
      'address': address,
      'barangay': profile['barangay'],
      'town': profile['town'],
      'landmark': profile['landmark'],
      'latitude': latitude,
      'longitude': longitude,
      'notes': userNotes.trim(),
      'voucher_id': voucherId,
      'items': sortedItems,
    });
  }

  /// Station-facing note: container handling, schedule, then the customer's
  /// own note.
  String get combinedNotes {
    final note = userNotes.trim();
    return [
      containerOption == 'swap'
          ? '[Container: 1-to-1 Bottle Swap]'
          : '[Container: No Empty Bottle (Deposit / New Container Needed)]',
      if (scheduleForNextOpen)
        '[Scheduled for next station opening (${stationOpeningTime ?? '8:00 AM'})]',
      if (note.isNotEmpty) note,
    ].join(' · ');
  }

  Map<String, dynamic> toOrderData(String idempotencyKey) => {
    'customer_id': customerId,
    'owner_id': stationId,
    'station_name': stationName,
    'customer_name': customerName,
    'customer_phone': profile['phone'],
    'customer_address': address,
    'customer_barangay': profile['barangay'],
    'customer_municipality': profile['town'],
    'customer_landmark': profile['landmark'],
    'idempotency_key': idempotencyKey,
    'voucher_id': voucherId,
    'subtotal': subtotal,
    'delivery_fee': deliveryFee,
    'delivery_distance_km': deliveryDistanceKm,
    'delivery_rate_per_km': deliveryRatePerKm,
    'total_amount': totalAmount,
    'payment_method': paymentMethod,
    'payment_proof_url': null,
    'notes': combinedNotes,
    'region_id': profile['region_id'],
    'customer_latitude': latitude,
    'customer_longitude': longitude,
    'container_exchange_type': containerOption,
    if (scheduleForNextOpen) 'scheduled_for_next_open': true,
  };
}

class PlacedOrder {
  const PlacedOrder({required this.id, required this.totalAmount});

  final String id;

  /// Server-computed total (falls back to the client estimate if absent).
  final double totalAmount;
}

/// Places customer orders through the authoritative `create_order_atomic`.
class CheckoutOrderService {
  CheckoutOrderService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<PlacedOrder> placeOrder(
    CheckoutOrderRequest request, {
    required String idempotencyKey,
  }) async {
    final response = await _client.rpc(
      'create_order_atomic',
      params: {
        'p_order_data': request.toOrderData(idempotencyKey),
        'p_items_data': request.itemsData,
      },
    );
    if (response is! Map) {
      throw StateError('Order creation failed: invalid server response.');
    }
    final id = response['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Order creation failed: missing order ID.');
    }
    final serverTotal = response['total_amount'];
    return PlacedOrder(
      id: id,
      totalAmount: serverTotal is num
          ? serverTotal.toDouble()
          : request.totalAmount,
    );
  }

  Future<Map<String, dynamic>> fetchOrder(String id) =>
      _client.from('orders').select().eq('id', id).single();

  /// True when [error] looks like the device is offline rather than the
  /// server rejecting the order; checkout may then queue a COD order locally.
  static bool isNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return const [
      'socket',
      'network',
      'timeout',
      'connection',
      'failed host lookup',
      'clientexception',
    ].any(text.contains);
  }

  /// Customer-facing message for a failed checkout.
  static String friendlyError(Object error) {
    if (error is PostgrestException) {
      final msg = error.message.trim();
      if (msg.isNotEmpty) {
        if (msg.contains('Only customer accounts can place orders')) {
          return 'Only customer accounts can place orders.';
        }
        if (msg.contains('closed or unavailable')) {
          return 'This water station is currently closed or unavailable.';
        }
        if (msg.contains('payment method is not available') ||
            msg.contains('payment method')) {
          return 'This payment method is not available for this station.';
        }
        if (msg.contains('unavailable at this station') ||
            msg.contains('Product not found')) {
          return 'One or more items in your cart are unavailable at this station.';
        }
        return msg;
      }
    }
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('Not authorized')) {
      return 'Please sign in again to place your order.';
    }
    if (message.contains('payment method')) {
      return 'Cash on delivery is available for this station. Online payment is not set up yet.';
    }
    if (message.contains('Product not found') ||
        message.contains('Product id is required')) {
      return 'Ordering is unavailable for this station right now. Please choose another station.';
    }
    if (message.contains('Station is not available') ||
        message.contains('not available')) {
      return message;
    }
    if (message.contains('customer_latitude') ||
        message.contains('customer_longitude')) {
      return 'The checkout database schema is incomplete. Please sync the Supabase orders table with the latest delivery-location columns.';
    }
    if (message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('NetworkImage') ||
        message.contains('ClientException')) {
      return 'Could not reach the server. Check your connection and try again.';
    }
    return message.isNotEmpty
        ? message
        : 'We could not place your order. Please try again.';
  }
}
