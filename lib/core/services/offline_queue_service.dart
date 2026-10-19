import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/utils/safe_supabase.dart';

class OfflineAction {
  final String id;
  final String actionType; // 'CREATE_ORDER', 'ASSIGN_RIDER', 'UPDATE_ORDER_STATUS'
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  OfflineAction({
    required this.id,
    required this.actionType,
    required this.payload,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'actionType': actionType,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
  };

  factory OfflineAction.fromJson(Map<String, dynamic> json) => OfflineAction(
    id: json['id'],
    actionType: json['actionType'],
    payload: json['payload'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class OfflineQueueService {
  static const String _storageKey = 'offline_actions_queue';

  static String _keyForUser(String? userId) =>
      userId == null ? _storageKey : '${_storageKey}_$userId';

  /// Adds a failed action to the local queue
  static Future<void> queueAction(OfflineAction action) async {
    final prefs = await SharedPreferences.getInstance();
    final userId =
        Supabase.instance.client.auth.currentUser?.id ??
        action.payload['customer_id']?.toString() ??
        action.payload['owner_id']?.toString();
    final currentQueue = await getQueue(userId: userId);
    currentQueue.add(action);
    await prefs.setString(
      _keyForUser(userId),
      jsonEncode(currentQueue.map((e) => e.toJson()).toList()),
    );
    debugPrint('OfflineQueueService: Queued action ${action.id} (${action.actionType})');
  }

  /// Retrieves all pending actions
  static Future<List<OfflineAction>> getQueue({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForUser(userId));
    if (raw == null) return [];
    final List<dynamic> decoded = jsonDecode(raw);
    return decoded.map((e) => OfflineAction.fromJson(e)).toList();
  }

  /// Returns total number of pending actions for the current/specified user
  static Future<int> getPendingCount({String? userId}) async {
    final effectiveUserId = userId ?? Supabase.instance.client.auth.currentUser?.id;
    final queue = await getQueue(userId: effectiveUserId);
    return queue.length;
  }

  /// Processes the queue when online
  static Future<void> processQueue(SupabaseClient client) async {
    final userId = client.auth.currentUser?.id;
    final queue = await getQueue(userId: userId);
    if (queue.isEmpty) return;

    debugPrint('OfflineQueueService: Processing ${queue.length} items...');
    final List<OfflineAction> remaining = [];

    for (final action in queue) {
      try {
        if (action.actionType == 'CREATE_ORDER') {
          final orderData = action.payload['order_data'];
          final itemsData = action.payload['items_data'];
          if (orderData is! Map || itemsData is! List) {
            throw StateError('Offline order payload is not RPC-compatible');
          }
          await client.rpc(
            'create_order_atomic',
            params: {
              'p_order_data': Map<String, dynamic>.from(orderData),
              'p_items_data': itemsData,
            },
          );
        } else if (action.actionType == 'ASSIGN_RIDER') {
          final assigned = await client.rpc(
            'assign_rider_safely',
            params: action.payload,
          );
          if (assigned != true) {
            throw StateError('Rider assignment was rejected by the server.');
          }
        } else if (action.actionType == 'UPDATE_ORDER_STATUS' ||
            action.actionType == 'COMPLETE_PICKUP_ORDER') {
          final orderId = action.payload['order_id']?.toString();
          final newStatus = action.payload['new_status']?.toString();
          final reason = action.payload['reason']?.toString();
          if (orderId == null || orderId.isEmpty) {
            throw StateError('Queued status action has no order ID.');
          }
          if (action.actionType == 'COMPLETE_PICKUP_ORDER' ||
              newStatus == 'delivered') {
            await SafeSupabase.completePickupOrder(
              orderId: orderId,
              client: client,
            );
          } else if (newStatus != null) {
            final res = await SafeSupabase.transitionOrderStatus(
              orderId: orderId,
              newStatus: newStatus,
              client: client,
            );
            if (res['success'] != true) {
              throw StateError(
                res['message']?.toString() ?? 'Status update rejected',
              );
            }
          } else {
            throw StateError('Queued status action has no target status.');
          }
          // Same as the online decline path: keep the owner's reason.
          if (reason != null && reason.isNotEmpty) {
            await client
                .from('orders')
                .update({'notes': 'Declined: $reason'})
                .eq('id', orderId);
          }
        }
      } catch (error) {
        debugPrint('OfflineQueueService: Failed to process ${action.id}: $error');
        final isRejected =
            error is StateError ||
            (error is PostgrestException &&
                const {'P0001', '42501', '23514'}.contains(error.code));
        if (!isRejected) remaining.add(action);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyForUser(userId),
      jsonEncode(remaining.map((e) => e.toJson()).toList()),
    );
    debugPrint(
      'OfflineQueueService: ${queue.length - remaining.length} items processed.',
    );
  }
}
