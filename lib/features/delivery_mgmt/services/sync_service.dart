import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery_model.dart';
import '../models/credit_model.dart';
import '../models/rider_model.dart';
import '../models/inventory_model.dart';
import 'local_db_service.dart';

enum SyncStatus { idle, syncing, synced, error }

typedef SyncFailureReporter =
    Future<void> Function(String ownerId, Object error, StackTrace stackTrace);

class SyncService {
  final LocalDbService _local;
  final SupabaseClient _supabase;
  final SyncFailureReporter? _failureReporter;
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  SyncService({
    required LocalDbService local,
    required SupabaseClient supabase,
    SyncFailureReporter? failureReporter,
  }) : _local = local,
       _supabase = supabase,
       _failureReporter = failureReporter;

  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  void startListening(String ownerId) {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final connected =
          !results.contains(ConnectivityResult.none) && results.isNotEmpty;
      if (connected) {
        await syncAll(ownerId);
      }
    });
  }

  void stopListening() {
    _connectivitySub?.cancel();
  }

  Future<bool> hasConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none) && results.isNotEmpty;
  }

  static String? cloudTableForDeletionType(String entityType) {
    return switch (entityType) {
      'delivery' => 'dm_deliveries',
      'credit' => 'dm_credits',
      'rider' => 'dm_riders',
      'inventory' => 'dm_inventory',
      _ => null,
    };
  }

  static Map<String, Object?> syncFailurePayload(String ownerId, Object error) {
    return {'owner_id': ownerId, 'error': error.toString()};
  }

  /// Full sync: push local unsynced → pull cloud → merge
  Future<void> syncAll(String ownerId) async {
    if (_syncStatusController.isClosed) return;
    _syncStatusController.add(SyncStatus.syncing);
    try {
      await _pushDeletions(ownerId);
      await _pushRiders(ownerId);
      await _pushDeliveries(ownerId);
      await _pushCredits(ownerId);
      await _pushInventory(ownerId);
      await _pullDeliveries(ownerId);
      await _pullCredits(ownerId);
      await _pullRiders(ownerId);
      await _pullInventory(ownerId);
      if (!_syncStatusController.isClosed) {
        _syncStatusController.add(SyncStatus.synced);
      }
    } catch (e, stackTrace) {
      debugPrint('[SyncService] Error during sync: $e');
      try {
        await _failureReporter?.call(ownerId, e, stackTrace);
      } catch (reportError) {
        debugPrint('[SyncService] Could not report sync failure: $reportError');
      }
      if (!_syncStatusController.isClosed) {
        _syncStatusController.add(SyncStatus.error);
      }
    }
  }

  // ─── PUSH ────────────────────────────────────────────────────────────────

  Future<void> _pushDeletions(String ownerId) async {
    final deletions = await _local.getPendingDeletions(ownerId);
    for (final deletion in deletions) {
      final table = cloudTableForDeletionType(deletion.entityType);
      if (table == null) {
        throw StateError(
          'Unsupported pending deletion type: ${deletion.entityType}',
        );
      }

      try {
        await _supabase
            .from(table)
            .delete()
            .eq('id', deletion.entityId)
            .eq('owner_id', deletion.ownerId);
        await _local.cancelDeletion(deletion.entityType, deletion.entityId);
      } catch (e) {
        debugPrint('[SyncService] Push deletion failed: $e');
        rethrow;
      }
    }
  }

  Future<void> _pushRiders(String ownerId) async {
    // Riders are always pushed immediately via delivery service when online
    // This is a safety net for any offline-created riders
    final riders = await _local.getRiders(ownerId);
    for (final rider in riders) {
      try {
        await _supabase
            .from('dm_riders')
            .upsert(rider.toJson(), onConflict: 'id');
      } catch (e) {
        debugPrint('[SyncService] Push rider failed: $e');
        rethrow;
      }
    }
  }

  Future<void> _pushDeliveries(String ownerId) async {
    final unsynced = await _local.getUnsyncedDeliveries(ownerId);
    for (final delivery in unsynced) {
      try {
        await _supabase
            .from('dm_deliveries')
            .upsert(delivery.toJson(), onConflict: 'id');
        await _local.markDeliverySynced(delivery.id);
      } catch (e) {
        debugPrint('[SyncService] Push delivery failed: $e');
        rethrow;
      }
    }
  }

  Future<void> _pushCredits(String ownerId) async {
    final unsynced = await _local.getUnsyncedCredits(ownerId);
    for (final credit in unsynced) {
      try {
        await _supabase
            .from('dm_credits')
            .upsert(credit.toJson(), onConflict: 'id');
        await _local.markCreditSynced(credit.id);
      } catch (e) {
        debugPrint('[SyncService] Push credit failed: $e');
        rethrow;
      }
    }
  }

  Future<void> _pushInventory(String ownerId) async {
    final txs = await _local.getInventoryTxs(ownerId);
    for (final tx in txs) {
      try {
        await _supabase
            .from('dm_inventory')
            .upsert(tx.toJson(), onConflict: 'id');
      } catch (e) {
        debugPrint('[SyncService] Push inventory failed: $e');
        // Non-blocking for local tx logs
      }
    }
  }

  // ─── PULL ────────────────────────────────────────────────────────────────

  Future<void> _pullDeliveries(String ownerId) async {
    try {
      final data = await _supabase
          .from('dm_deliveries')
          .select()
          .eq('owner_id', ownerId)
          .order('updated_at', ascending: false)
          .limit(500);
      for (final row in data) {
        final delivery = DmDelivery.fromJson(row);
        await _local.upsertDeliveryFromCloud(delivery);
      }
    } catch (e) {
      debugPrint('[SyncService] Pull deliveries failed: $e');
      rethrow;
    }
  }

  Future<void> _pullCredits(String ownerId) async {
    try {
      final data = await _supabase
          .from('dm_credits')
          .select()
          .eq('owner_id', ownerId)
          .order('updated_at', ascending: false)
          .limit(500);
      for (final row in data) {
        final credit = DmCredit.fromJson(row);
        await _local.upsertCreditFromCloud(credit);
      }
    } catch (e) {
      debugPrint('[SyncService] Pull credits failed: $e');
      rethrow;
    }
  }

  Future<void> _pullRiders(String ownerId) async {
    try {
      final data = await _supabase
          .from('dm_riders')
          .select()
          .eq('owner_id', ownerId);
      for (final row in data) {
        final rider = DmRider.fromJson(row);
        await _local.insertRider(rider); // upsert via conflictAlgorithm.replace
      }
    } catch (e) {
      debugPrint('[SyncService] Pull riders failed: $e');
      rethrow;
    }
  }

  Future<void> _pullInventory(String ownerId) async {
    try {
      final data = await _supabase
          .from('dm_inventory')
          .select()
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false)
          .limit(500);
      for (final row in data) {
        final tx = DmInventoryTx.fromJson(row);
        await _local.upsertInventoryFromCloud(tx);
      }
    } catch (e) {
      debugPrint('[SyncService] Pull inventory failed: $e');
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _syncStatusController.close();
  }
}
