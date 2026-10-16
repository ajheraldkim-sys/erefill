import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'queued_delivery_rules.dart';

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
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
  );
}

class OfflineDeliveryQueueService {
  static final OfflineDeliveryQueueService _instance =
      OfflineDeliveryQueueService._internal();
  factory OfflineDeliveryQueueService() => _instance;
  static OfflineDeliveryQueueService get instance => _instance;

  Future<int> Function()? onSyncTriggered;
  bool _isSyncing = false;

  OfflineDeliveryQueueService._internal() {
    onSyncTriggered = syncPendingDeliveries;
  }

  Future<int> getPendingCount() async {
    final list = await getPendingDeliveries();
    return list.length;
  }

  static const String _queueKeyPrefix = 'offline_delivery_queue_';

  String get _storageKey {
    final riderId = SafeSupabase.currentUserId ?? 'anonymous_rider';
    return '$_queueKeyPrefix$riderId';
  }

  /// Add a delivery to the offline queue
  Future<void> enqueueDelivery(QueuedDelivery delivery) async {
    if (delivery.orderId.trim().isEmpty) {
      throw ArgumentError.value(
        delivery.orderId,
        'orderId',
        'Cannot be empty.',
      );
    }
    final currentList = await getPendingDeliveries();
    final existingIndex = currentList.indexWhere(
      (item) => item.orderId == delivery.orderId,
    );
    if (existingIndex == -1) {
      currentList.add(delivery);
    } else {
      final existing = currentList[existingIndex];
      currentList[existingIndex] = QueuedDelivery(
        orderId: delivery.orderId,
        status: delivery.status,
        latitude: delivery.latitude ?? existing.latitude,
        longitude: delivery.longitude ?? existing.longitude,
        localPhotoPath: delivery.localPhotoPath ?? existing.localPhotoPath,
        localSignaturePath:
            delivery.localSignaturePath ?? existing.localSignaturePath,
        deliveryNote: delivery.deliveryNote ?? existing.deliveryNote,
        emptyGallonsReturned: delivery.emptyGallonsReturned,
        createdAt: existing.createdAt,
        retryCount: existing.retryCount,
      );
    }
    await _savePendingDeliveries(currentList);
    debugPrint(
      '[OfflineDeliveryQueue] Enqueued order ${delivery.orderId}. Total pending: ${currentList.length}',
    );
  }

  /// Get list of pending deliveries for current rider
  Future<List<QueuedDelivery>> getPendingDeliveries() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey);
    if (rawList == null || rawList.isEmpty) return [];

    try {
      return rawList.map((item) {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        return QueuedDelivery.fromJson(decoded);
      }).toList();
    } catch (e) {
      debugPrint('[OfflineDeliveryQueue] Error reading pending deliveries: $e');
      throw StateError(
        'Saved delivery updates could not be read. Data preserved.',
      );
    }
  }

  Future<void> _savePendingDeliveries(List<QueuedDelivery> deliveries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = deliveries
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    if (!await prefs.setStringList(_storageKey, encoded)) {
      throw StateError('Delivery updates could not be saved on this device.');
    }
  }

  /// Remove a delivery once synced
  Future<void> removeDelivery(String orderId) async {
    final currentList = await getPendingDeliveries();
    currentList.removeWhere((item) => item.orderId == orderId);
    await _savePendingDeliveries(currentList);
    debugPrint(
      '[OfflineDeliveryQueue] Removed order $orderId from queue. Remaining: ${currentList.length}',
    );
  }

  /// Sync all pending deliveries to Supabase backend
  Future<int> syncPendingDeliveries() async {
    if (_isSyncing) return 0;
    final pending = await getPendingDeliveries();
    if (pending.isEmpty) return 0;

    _isSyncing = true;
    final client = Supabase.instance.client;
    int syncedCount = 0;
    final failedDeliveries = <QueuedDelivery>[];

    try {
      for (final delivery in pending) {
        try {
          if (queuedDeliveryOperation(delivery.status) ==
              QueuedDeliveryOperation.transitionStatus) {
            final result = await SafeSupabase.transitionOrderStatus(
              orderId: delivery.orderId,
              newStatus: delivery.status,
            );
            if (result['success'] != true) {
              throw StateError(
                result['message']?.toString() ??
                    'Order status update was rejected.',
              );
            }
            await removeDelivery(delivery.orderId);
            syncedCount++;
            continue;
          }

          final currentOrder = await client
              .from('orders')
              .select('status')
              .eq('id', delivery.orderId)
              .maybeSingle();
          if (currentOrder == null) {
            throw StateError('Order is no longer available to this rider.');
          }
          if (currentOrder['status'] == 'delivered') {
            final receipt = await client
                .from('delivery_receipts')
                .select('id')
                .eq('order_id', delivery.orderId)
                .maybeSingle();
            if (receipt == null) {
              throw StateError(
                'Order is already delivered but has no verified receipt. Contact support.',
              );
            }
            await removeDelivery(delivery.orderId);
            await _removeLocalProof(delivery);
            syncedCount++;
            continue;
          }

          if (!hasRequiredDeliveryEvidence(
            photoPath: delivery.localPhotoPath,
            signaturePath: delivery.localSignaturePath,
          )) {
            throw StateError(
              'A delivery photo and recipient signature are required. Reopen the order to capture both.',
            );
          }

          String? remotePhotoPath;
          String? remoteSignaturePath;

          final photoFile = File(delivery.localPhotoPath!);
          if (!photoFile.existsSync()) {
            throw StateError('Saved delivery photo is no longer available.');
          }
          final signatureFile = File(delivery.localSignaturePath!);
          if (!signatureFile.existsSync()) {
            throw StateError(
              'Saved delivery signature is no longer available.',
            );
          }
          if (await photoFile.length() > 10 * 1024 * 1024 ||
              await signatureFile.length() > 10 * 1024 * 1024) {
            throw StateError('Delivery evidence must be smaller than 10 MB.');
          }
          final photoExtension = photoFile.path.split('.').last.toLowerCase();
          if (!{'jpg', 'jpeg', 'png'}.contains(photoExtension)) {
            throw StateError('Saved delivery photo must be a JPEG or PNG.');
          }
          if (!signatureFile.path.toLowerCase().endsWith('.png')) {
            throw StateError('Saved recipient signature must be a PNG.');
          }
          remotePhotoPath =
              '${delivery.orderId}/proof_${photoFile.uri.pathSegments.last}';
          remoteSignaturePath =
              '${delivery.orderId}/signature_${signatureFile.uri.pathSegments.last}';
          await client.storage.from('delivery_proofs').upload(
            remotePhotoPath,
            photoFile,
            fileOptions: FileOptions(
              contentType: photoExtension == 'png' ? 'image/png' : 'image/jpeg',
              upsert: true,
            ),
          );
          await client.storage.from('delivery_proofs').upload(
            remoteSignaturePath,
            signatureFile,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );

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
          if (response is! Map || response['success'] != true) {
            throw StateError(
              response is Map
                  ? response['message']?.toString() ??
                        'Delivery confirmation was rejected.'
                  : 'Delivery confirmation returned an invalid response.',
            );
          }

          // Remove from queue after successful sync
          await removeDelivery(delivery.orderId);
          await _removeLocalProof(delivery);
          syncedCount++;
        } catch (e) {
          debugPrint(
            '[OfflineDeliveryQueue] Failed to sync order ${delivery.orderId}: $e',
          );
          delivery.retryCount++;
          failedDeliveries.add(delivery);
        }
      }

      await _savePendingDeliveries(failedDeliveries);
      return syncedCount;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _removeLocalProof(QueuedDelivery delivery) async {
    for (final path in [
      delivery.localPhotoPath,
      delivery.localSignaturePath,
    ]) {
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[OfflineDeliveryQueue] Could not remove local proof: $error');
      }
    }
  }
}
