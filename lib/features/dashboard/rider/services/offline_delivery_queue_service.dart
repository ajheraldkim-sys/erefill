import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/utils/safe_supabase.dart';

class QueuedDelivery {
  final String orderId;
  final String status;
  final double? latitude;
  final double? longitude;
  final String? localPhotoPath;
  final String? localSignaturePath;
  final String? deliveryNote;
  final int emptyGallonsReturned;
  final DateTime createdAt;
  int retryCount;

  QueuedDelivery({
    required this.orderId,
    this.status = 'delivered',
    this.latitude,
    this.longitude,
    this.localPhotoPath,
    this.localSignaturePath,
    this.deliveryNote,
    this.emptyGallonsReturned = 0,
    DateTime? createdAt,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'status': status,
        'latitude': latitude,
        'longitude': longitude,
        'localPhotoPath': localPhotoPath,
        'localSignaturePath': localSignaturePath,
        'deliveryNote': deliveryNote,
        'emptyGallonsReturned': emptyGallonsReturned,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory QueuedDelivery.fromJson(Map<String, dynamic> json) => QueuedDelivery(
        orderId: json['orderId']?.toString() ?? '',
        status: json['status']?.toString() ?? 'delivered',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        localPhotoPath: json['localPhotoPath']?.toString(),
        localSignaturePath: json['localSignaturePath']?.toString(),
        deliveryNote: json['deliveryNote']?.toString(),
        emptyGallonsReturned: (json['emptyGallonsReturned'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      );
}

class OfflineDeliveryQueueService {
  static final OfflineDeliveryQueueService _instance = OfflineDeliveryQueueService._internal();
  factory OfflineDeliveryQueueService() => _instance;
  OfflineDeliveryQueueService._internal();

  static const String _queueKeyPrefix = 'offline_delivery_queue_';

  String get _storageKey {
    final riderId = SafeSupabase.currentUserId ?? 'anonymous_rider';
    return '$_queueKeyPrefix$riderId';
  }

  /// Add a delivery to the offline queue
  Future<void> enqueueDelivery(QueuedDelivery delivery) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getPendingDeliveries();
      
      // Avoid duplicates for the same orderId
      currentList.removeWhere((d) => d.orderId == delivery.orderId);
      currentList.add(delivery);

      final encoded = currentList.map((d) => jsonEncode(d.toJson())).toList();
      await prefs.setStringList(_storageKey, encoded);
      debugPrint('[OfflineDeliveryQueue] Enqueued order ${delivery.orderId}. Total pending: ${currentList.length}');
    } catch (e) {
      debugPrint('[OfflineDeliveryQueue] Error enqueuing delivery: $e');
    }
  }

  /// Get list of pending deliveries for current rider
  Future<List<QueuedDelivery>> getPendingDeliveries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_storageKey);
      if (rawList == null || rawList.isEmpty) return [];

      return rawList.map((item) {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        return QueuedDelivery.fromJson(decoded);
      }).toList();
    } catch (e) {
      debugPrint('[OfflineDeliveryQueue] Error reading pending deliveries: $e');
      return [];
    }
  }

  /// Remove a delivery once synced
  Future<void> removeDelivery(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getPendingDeliveries();
      currentList.removeWhere((d) => d.orderId == orderId);

      final encoded = currentList.map((d) => jsonEncode(d.toJson())).toList();
      await prefs.setStringList(_storageKey, encoded);
      debugPrint('[OfflineDeliveryQueue] Removed order $orderId from queue. Remaining: ${currentList.length}');
    } catch (e) {
      debugPrint('[OfflineDeliveryQueue] Error removing delivery: $e');
    }
  }

  /// Sync all pending deliveries to Supabase backend
  Future<int> syncPendingDeliveries() async {
    final pending = await getPendingDeliveries();
    if (pending.isEmpty) return 0;

    final client = Supabase.instance.client;
    int syncedCount = 0;

    for (final delivery in pending) {
      try {
        String? remotePhotoPath;
        String? remoteSignaturePath;

        // 1. Upload local photo proof if it exists
        if (delivery.localPhotoPath != null) {
          final photoFile = File(delivery.localPhotoPath!);
          if (photoFile.existsSync()) {
            final fileName = '${delivery.orderId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
            remotePhotoPath = 'proofs/${delivery.orderId}/$fileName';
            try {
              await client.storage.from('delivery_proofs').upload(remotePhotoPath, photoFile);
            } catch (storageErr) {
              debugPrint('[OfflineDeliveryQueue] Photo upload skipped: $storageErr');
            }
          }
        }

        // 2. Upload local signature proof if it exists
        if (delivery.localSignaturePath != null) {
          final sigFile = File(delivery.localSignaturePath!);
          if (sigFile.existsSync()) {
            final sigName = 'sig_${delivery.orderId}_${DateTime.now().millisecondsSinceEpoch}.png';
            remoteSignaturePath = 'proofs/${delivery.orderId}/$sigName';
            try {
              await client.storage.from('delivery_proofs').upload(remoteSignaturePath, sigFile);
            } catch (storageErr) {
              debugPrint('[OfflineDeliveryQueue] Signature upload skipped: $storageErr');
            }
          }
        }

        // 3. Confirm delivery on server via RPC or fallback
        bool serverConfirmed = false;
        try {
          final response = await client.rpc(
            'confirm_delivery_safely',
            params: {
              'p_order_id': delivery.orderId,
              'p_lat': delivery.latitude,
              'p_lng': delivery.longitude,
              'p_photo_url': remotePhotoPath,
              'p_signature_url': remoteSignaturePath,
              'p_delivery_note': delivery.deliveryNote,
              'p_empty_gallons_returned': delivery.emptyGallonsReturned,
            },
          );
          if (response is Map && response['success'] == true) {
            serverConfirmed = true;
          }
        } catch (rpcErr) {
          debugPrint('[OfflineDeliveryQueue] confirm_delivery_safely RPC error: $rpcErr');
        }

        if (!serverConfirmed) {
          await SafeSupabase.transitionOrderStatus(
            orderId: delivery.orderId,
            newStatus: delivery.status,
          );
          try {
            await client.from('orders').update({
              'delivery_note': delivery.deliveryNote,
              'empty_gallons_returned': delivery.emptyGallonsReturned,
            }).eq('id', delivery.orderId);
          } catch (_) {}
        }

        // Remove from queue after successful sync
        await removeDelivery(delivery.orderId);
        syncedCount++;
      } catch (e) {
        debugPrint('[OfflineDeliveryQueue] Failed to sync order ${delivery.orderId}: $e');
        delivery.retryCount++;
      }
    }

    return syncedCount;
  }
}

