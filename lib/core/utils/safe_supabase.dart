import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../services/local_data_cache.dart';

/// Safe Supabase helper with proper null safety and error handling
class SafeSupabase {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Get current user ID safely - returns null if not logged in
  static String? get currentUserId {
    try {
      return _client.auth.currentUser?.id;
    } catch (e) {
      debugPrint('Error getting current user: $e');
      return null;
    }
  }

  /// Check if user is logged in
  static bool get isLoggedIn => currentUserId != null;

  /// Safe query execution with error handling
  static Future<List<Map<String, dynamic>>> query(
    String table, {
    String? columns,
    Map<String, dynamic>? eq,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    try {
      dynamic query = _client.from(table).select(columns ?? '*');

      if (eq != null) {
        for (final entry in eq.entries) {
          if (entry.value != null) {
            query = query.eq(entry.key, entry.value);
          }
        }
      }

      if (orderBy != null) {
        query = query.order(orderBy, ascending: ascending);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final response = await query;
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('SafeSupabase query error: $e');
      return [];
    }
  }

  /// Safe single row fetch - returns null if not found
  static Future<Map<String, dynamic>?> querySingle(
    String table, {
    required String eqColumn,
    required dynamic eqValue,
    String? columns,
  }) async {
    try {
      if (eqValue == null) return null;

      final response = await _client
          .from(table)
          .select(columns ?? '*')
          .eq(eqColumn, eqValue)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('SafeSupabase querySingle error: $e');
      return null;
    }
  }

  /// Safe insert with error handling
  static Future<Map<String, dynamic>?> insert(
    String table,
    Map<String, dynamic> data, {
    bool returnData = true,
  }) async {
    try {
      dynamic query = _client.from(table).insert(data);

      if (returnData) {
        query = query.select();
      }

      final response = await query;

      if (response is List && response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('SafeSupabase insert error: $e');
      return null;
    }
  }

  /// Safe update with error handling
  static Future<bool> update(
    String table,
    Map<String, dynamic> data, {
    required String eqColumn,
    required dynamic eqValue,
  }) async {
    try {
      if (eqValue == null) return false;

      await _client.from(table).update(data).eq(eqColumn, eqValue);

      return true;
    } catch (e) {
      debugPrint('SafeSupabase update error: $e');
      return false;
    }
  }

  /// Safe delete with error handling
  static Future<bool> delete(
    String table, {
    required String eqColumn,
    required dynamic eqValue,
  }) async {
    try {
      if (eqValue == null) return false;

      await _client.from(table).delete().eq(eqColumn, eqValue);

      return true;
    } catch (e) {
      debugPrint('SafeSupabase delete error: $e');
      return false;
    }
  }

  /// Safe RPC call with error handling
  static Future<dynamic> rpc(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    try {
      return await _client.rpc(function, params: params);
    } catch (e) {
      debugPrint('SafeSupabase RPC error: $e');
      return null;
    }
  }

  /// Changes an order's status through `transition_order_status_safely`,
  /// which enforces the allowed transitions per role and notifies the
  /// customer.
  ///
  /// There is deliberately no direct-update fallback: a transition the server
  /// rejects (it raises, e.g. "Invalid station order status transition") must
  /// stay rejected. Errors propagate; a `success: false` reply is returned.
  static Future<Map<String, dynamic>> transitionOrderStatus({
    required String orderId,
    required String newStatus,
    SupabaseClient? client,
  }) async {
    final db = client ?? _client;
    final response = await db.rpc(
      'transition_order_status_safely',
      params: {'p_order_id': orderId, 'p_new_status': newStatus},
    );
    final result = response is Map
        ? Map<String, dynamic>.from(response)
        : <String, dynamic>{
            'success': false,
            'message': 'Unexpected response from the order status service.',
          };

    // Invalidate cached order overviews and lists across all roles
    unawaited(LocalDataCache.instance.invalidatePattern('owner_overview_'));
    unawaited(LocalDataCache.instance.invalidatePattern('owner_orders_'));
    unawaited(LocalDataCache.instance.invalidatePattern('customer_home_'));
    unawaited(LocalDataCache.instance.invalidatePattern('customer_orders_'));
    unawaited(LocalDataCache.instance.invalidatePattern('rider_stats_'));

    return result;
  }

  /// Completes a station pickup through its audited server-side workflow.
  static Future<Map<String, dynamic>> completePickupOrder({
    required String orderId,
    SupabaseClient? client,
  }) async {
    final result = await _requireSuccess(
      (client ?? _client).rpc(
        'complete_pickup_order_safely',
        params: {'p_order_id': orderId},
      ),
      'Pickup order could not be completed.',
    );
    unawaited(LocalDataCache.instance.invalidatePattern('owner_overview_'));
    unawaited(LocalDataCache.instance.invalidatePattern('owner_orders_'));
    unawaited(LocalDataCache.instance.invalidatePattern('customer_home_'));
    unawaited(LocalDataCache.instance.invalidatePattern('customer_orders_'));
    return result;
  }

  /// Like [transitionOrderStatus] but throws when the server refuses, for
  /// callers that only need to know whether the change happened.
  static Future<void> requireOrderTransition({
    required String orderId,
    required String newStatus,
    SupabaseClient? client,
  }) async {
    final result = await transitionOrderStatus(
      orderId: orderId,
      newStatus: newStatus,
      client: client,
    );
    if (result['success'] != true) {
      throw StateError(
        result['message']?.toString() ?? 'Order status update was rejected.',
      );
    }
  }

  /// Detaches a rider from the caller's station via `owner_unlink_rider`,
  /// which checks the rider belongs to the caller. Throws unless the server
  /// confirms (a direct profiles update cannot work: RLS only allows editing
  /// your own profile, so it would silently change nothing).
  static Future<Map<String, dynamic>> unlinkRider({
    required String riderId,
    SupabaseClient? client,
  }) => _requireSuccess(
    (client ?? _client).rpc(
      'owner_unlink_rider',
      params: {'p_rider_id': riderId},
    ),
    'Rider could not be unlinked.',
  );

  /// Suspends or reactivates a rider via `owner_set_rider_status`. Throws
  /// unless the server confirms; see [unlinkRider].
  static Future<Map<String, dynamic>> setRiderStatus({
    required String riderId,
    required bool isSuspended,
    String? reason,
    SupabaseClient? client,
  }) => _requireSuccess(
    (client ?? _client).rpc(
      'owner_set_rider_status',
      params: {
        'p_rider_id': riderId,
        'p_is_suspended': isSuspended,
        'p_reason': reason,
      },
    ),
    'Rider status could not be changed.',
  );

  static Future<Map<String, dynamic>> _requireSuccess(
    Future<dynamic> call,
    String fallbackMessage,
  ) async {
    final response = await call;
    final result = response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
    if (result['success'] != true) {
      throw StateError(result['message']?.toString() ?? fallbackMessage);
    }
    return result;
  }

  /// Safe stream with error handling
  static Stream<List<Map<String, dynamic>>> stream(
    String table, {
    required List<String> primaryKey,
    String? eqColumn,
    dynamic eqValue,
  }) {
    try {
      dynamic query = _client.from(table).stream(primaryKey: primaryKey);

      if (eqColumn != null && eqValue != null) {
        query = query.eq(eqColumn, eqValue);
      }

      return query.handleError((error, stackTrace) {
        debugPrint('SafeSupabase stream error: $error');
        if (stackTrace != null) {
          debugPrint('SafeSupabase stream stack: $stackTrace');
        }
        return <Map<String, dynamic>>[];
      });
    } catch (e) {
      debugPrint('SafeSupabase stream setup error: $e');
      return Stream.value([]);
    }
  }

  static DateTime? _lastStreamErrorLog;
  static String? _lastStreamErrorMsg;

  static void _logStreamError(Object error) {
    final now = DateTime.now();
    final msg = error.toString();
    if (_lastStreamErrorMsg == msg &&
        _lastStreamErrorLog != null &&
        now.difference(_lastStreamErrorLog!).inSeconds < 15) {
      return;
    }
    _lastStreamErrorMsg = msg;
    _lastStreamErrorLog = now;
    debugPrint(
      'SafeSupabase realtime stream error: $error (resilient fallback active)',
    );
  }

  static StreamSubscription<List<Map<String, dynamic>>> listen(
    Stream<List<Map<String, dynamic>>> stream,
    FutureOr<void> Function(List<Map<String, dynamic>>) onData, {
    void Function(Object error, StackTrace stackTrace)? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return stream.listen(
      (data) async {
        await onData(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        _logStreamError(error);
        onError?.call(error, stackTrace);
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// Safe value parsers
class SafeParse {
  static String string(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    if (value is String) return value.isEmpty ? defaultValue : value;
    return value.toString();
  }

  static int integer(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static double decimal(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static bool boolean(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }
    return defaultValue;
  }

  static DateTime? dateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static List<T> list<T>(
    dynamic value,
    T Function(dynamic) parser, {
    List<T> defaultValue = const [],
  }) {
    if (value == null) return defaultValue;
    if (value is List) {
      return value.map(parser).where((e) => e != null).cast<T>().toList();
    }
    return defaultValue;
  }

  static Map<String, dynamic>? map(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
