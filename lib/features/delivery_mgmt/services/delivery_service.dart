import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery_model.dart';
import '../models/rider_model.dart';
import '../models/credit_model.dart';
import '../models/inventory_model.dart';
import 'local_db_service.dart';
import 'sync_service.dart';
import 'commission_service.dart';

/// Facade service — all provider interactions go through here.
/// Writes to SQLite first, then triggers cloud sync if online.
class DeliveryService {
  final LocalDbService local;
  final SyncService sync;
  final SupabaseClient _supabase = Supabase.instance.client;

  DeliveryService({required this.local, required this.sync});

  // ─── RIDERS ──────────────────────────────────────────────────────────────

  Future<List<DmRider>> getRiders(String ownerId) => local.getRiders(ownerId);

  Future<DmRider> addRider(DmRider rider) async {
    final id = await local.insertRider(rider);
    final saved = rider.copyWith(id: id);
    if (await sync.hasConnectivity()) {
      try {
        await _supabase
            .from('dm_riders')
            .upsert(saved.toJson(), onConflict: 'id');
      } catch (_) {}
    }
    return saved;
  }

  Future<void> updateRider(DmRider rider) async {
    await local.updateRider(rider);
    if (await sync.hasConnectivity()) {
      try {
        await _supabase
            .from('dm_riders')
            .upsert(rider.toJson(), onConflict: 'id');
      } catch (_) {}
    }
  }

  Future<void> deleteRider(String id, String ownerId) async {
    await local.deleteRider(id, ownerId);
    if (await sync.hasConnectivity()) {
      await sync.syncAll(ownerId);
    }
  }

  /// Look up a profile by email — used to link rider accounts.
  Future<String?> findUserIdByEmail(String email) async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      return data?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ─── DELIVERIES ──────────────────────────────────────────────────────────

  Future<List<DmDelivery>> getDeliveries({
    required String ownerId,
    String? riderId,
    DateTime? from,
    DateTime? to,
  }) => local.getDeliveries(
    ownerId: ownerId,
    riderId: riderId,
    from: from,
    to: to,
  );

  Future<DmDelivery> addDelivery(DmDelivery delivery) async {
    // 1. Calculate commission with today's milestone context
    double previousGallons = 0;
    if (delivery.riderId != null) {
      previousGallons = await local.getRiderGallonsToday(
        delivery.riderId!,
        delivery.ownerId,
      );
    }
    final commResult = CommissionService.calculate(
      gallons: delivery.gallons,
      commissionPerGallon:
          delivery.commission / (delivery.gallons == 0 ? 1 : delivery.gallons),
      previousGallonsToday: previousGallons,
    );

    final withCommission = delivery.copyWith(commission: commResult.total);

    // 2. Save locally
    final id = await local.insertDelivery(withCommission);
    final saved = withCommission.copyWith(id: id, localId: id);

    // 3. Auto-deduct from inventory
    await local.insertInventoryTx(
      DmInventoryTx(
        id: '',
        ownerId: delivery.ownerId,
        transactionDate: delivery.deliveryDate,
        transactionType: InventoryTxType.deduct,
        gallons: delivery.gallons,
        notes: 'Auto: delivery ${id.substring(0, 8)}',
        deliveryId: id,
        createdAt: DateTime.now(),
      ),
    );

    // 4. Auto-create credit if credit_amount > 0
    if (delivery.creditAmount > 0) {
      await local.insertCredit(
        DmCredit(
          id: '',
          ownerId: delivery.ownerId,
          riderId: delivery.riderId,
          riderName: delivery.riderName,
          deliveryId: id,
          creditType: CreditType.customer,
          debtorName: 'Customer (Delivery ${id.substring(0, 8)})',
          amount: delivery.creditAmount,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    // 5. Cloud push if online
    if (await sync.hasConnectivity()) {
      await sync.syncAll(delivery.ownerId);
    }

    return saved;
  }

  Future<DmDelivery> addDeliveryWithCommission({
    required DmDelivery delivery,
    required double commissionPerGallon,
  }) async {
    double previousGallons = 0;
    if (delivery.riderId != null) {
      previousGallons = await local.getRiderGallonsToday(
        delivery.riderId!,
        delivery.ownerId,
      );
    }
    final commResult = CommissionService.calculate(
      gallons: delivery.gallons,
      commissionPerGallon: commissionPerGallon,
      previousGallonsToday: previousGallons,
    );
    return addDelivery(delivery.copyWith(commission: commResult.total));
  }

  Future<void> updateDelivery(DmDelivery delivery) async {
    await local.updateDelivery(delivery);
    if (await sync.hasConnectivity()) {
      await sync.syncAll(delivery.ownerId);
    }
  }

  Future<void> deleteDelivery(String id, String ownerId) async {
    await local.deleteDelivery(id, ownerId);
    if (await sync.hasConnectivity()) {
      await sync.syncAll(ownerId);
    }
  }

  Future<void> restoreDeletedDelivery(DmDelivery delivery) async {
    await local.restoreDelivery(delivery);
    if (await sync.hasConnectivity()) {
      await sync.syncAll(delivery.ownerId);
    }
  }

  // ─── CREDITS ─────────────────────────────────────────────────────────────

  Future<List<DmCredit>> getCredits({
    required String ownerId,
    String? riderId,
    CreditType? type,
    bool? isPaid,
  }) => local.getCredits(
    ownerId: ownerId,
    riderId: riderId,
    type: type,
    isPaid: isPaid,
  );

  Future<DmCredit> addCredit(DmCredit credit) async {
    final id = await local.insertCredit(credit);
    final saved = credit.copyWith(id: id, localId: id);
    if (await sync.hasConnectivity()) {
      try {
        await _supabase
            .from('dm_credits')
            .upsert(saved.toJson(), onConflict: 'id');
        await local.markCreditSynced(id);
      } catch (_) {}
    }
    return saved;
  }

  Future<void> updateCredit(DmCredit credit) async {
    await local.updateCredit(credit);
    if (await sync.hasConnectivity()) {
      try {
        await _supabase
            .from('dm_credits')
            .upsert(credit.toJson(), onConflict: 'id');
        await local.markCreditSynced(credit.id);
      } catch (_) {}
    }
  }

  Future<void> deleteCredit(String id, String ownerId) async {
    await local.deleteCredit(id, ownerId);
    if (await sync.hasConnectivity()) {
      await sync.syncAll(ownerId);
    }
  }

  // ─── INVENTORY ───────────────────────────────────────────────────────────

  Future<List<DmInventoryTx>> getInventoryTxs(String ownerId) =>
      local.getInventoryTxs(ownerId);

  Future<double> getCurrentStock(String ownerId) =>
      local.getCurrentStock(ownerId);

  Future<DmInventoryTx> addInventoryTx(DmInventoryTx tx) async {
    final id = await local.insertInventoryTx(tx);
    final saved = DmInventoryTx(
      id: id,
      ownerId: tx.ownerId,
      transactionDate: tx.transactionDate,
      transactionType: tx.transactionType,
      gallons: tx.gallons,
      notes: tx.notes,
      deliveryId: tx.deliveryId,
      createdAt: tx.createdAt,
    );
    if (await sync.hasConnectivity()) {
      try {
        await _supabase
            .from('dm_inventory')
            .upsert(saved.toJson(), onConflict: 'id');
      } catch (_) {}
    }
    return saved;
  }
}
