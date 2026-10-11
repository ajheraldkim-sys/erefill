import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

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

  /// Safely transitions an order status using the RPC if available,
  /// falling back to a direct database update if the RPC is not installed.
  static Future<Map<String, dynamic>> transitionOrderStatus({
    required String orderId,
    required String newStatus,
    String? reason,
  }) async {
    try {
      final response = await _client.rpc(
        'transition_order_status_safely',
        params: {'p_order_id': orderId, 'p_new_status': newStatus},
      );
      if (response is Map) {
        final map = Map<String, dynamic>.from(response);
        if (map['success'] == true) return map;
      }
    } catch (e) {
      debugPrint('transition_order_status_safely RPC fallback triggered: $e');
    }

    // Direct database update fallback
    try {
      final updateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (reason != null && reason.isNotEmpty) {
        updateData['notes'] = 'Declined: $reason';
      }
      if (newStatus == 'delivered') {
        updateData['delivered_at'] = DateTime.now().toIso8601String();
      }
      await _client.from('orders').update(updateData).eq('id', orderId);
      return {'success': true, 'fallback': true};
    } catch (fallbackError) {
      debugPrint('Direct order status update failed: $fallbackError');
      rethrow;
    }
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
        debugPrint('SafeSupabase realtime stream error: $error');
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
