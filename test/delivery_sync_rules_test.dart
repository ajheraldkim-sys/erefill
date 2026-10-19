import 'package:erefill/features/delivery_mgmt/models/credit_model.dart';
import 'package:erefill/features/delivery_mgmt/models/inventory_model.dart';
import 'package:erefill/features/delivery_mgmt/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('offline deletion synchronization routing', () {
    test('maps every durable tombstone type to its cloud table', () {
      expect(
        SyncService.cloudTableForDeletionType('delivery'),
        'dm_deliveries',
      );
      expect(SyncService.cloudTableForDeletionType('credit'), 'dm_credits');
      expect(SyncService.cloudTableForDeletionType('rider'), 'dm_riders');
    });

    test('rejects an unknown deletion type instead of silently syncing', () {
      expect(SyncService.cloudTableForDeletionType('unknown'), isNull);
    });
  });

  group('sync failure observability', () {
    test('builds the owner-scoped failure event payload', () {
      final payload = SyncService.syncFailurePayload(
        'owner-123',
        StateError('network unavailable'),
      );

      expect(payload['owner_id'], 'owner-123');
      expect(payload['error'], contains('network unavailable'));
    });
  });

  group('cloud payload contract', () {
    // Columns of public.dm_credits / public.dm_inventory in production
    // (checked 2026-10-19). Cloud upserts must not send any other key, or
    // PostgREST rejects the whole row.
    const dmCreditColumns = {
      'id',
      'owner_id',
      'rider_id',
      'delivery_id',
      'credit_type',
      'debtor_name',
      'amount',
      'paid_amount',
      'remaining',
      'is_paid',
      'payment_date',
      'notes',
      'is_synced',
      'local_id',
      'created_at',
      'updated_at',
    };
    const dmInventoryColumns = {
      'id',
      'owner_id',
      'transaction_date',
      'transaction_type',
      'gallons',
      'notes',
      'delivery_id',
      'created_at',
    };

    test('credit cloud JSON only uses dm_credits columns and nulls blank ids', () {
      final credit = DmCredit(
        id: 'c1',
        ownerId: 'o1',
        riderId: '  ',
        riderName: 'Rider Juan',
        creditType: CreditType.rider,
        debtorName: 'Juan',
        amount: 50,
        createdAt: DateTime(2026, 10, 19),
        updatedAt: DateTime(2026, 10, 19),
      );
      final json = credit.toCloudJson();
      expect(
        dmCreditColumns.containsAll(json.keys),
        isTrue,
        reason:
            'unexpected keys: ${json.keys.toSet().difference(dmCreditColumns)}',
      );
      expect(json['rider_id'], isNull);
      expect(
        credit.toJson().containsKey('rider_name'),
        isTrue,
        reason:
            'toJson is the local SQLite shape and must not be sent to the cloud',
      );
    });

    test('inventory cloud JSON only uses dm_inventory columns', () {
      final tx = DmInventoryTx(
        id: 'i1',
        ownerId: 'o1',
        transactionDate: DateTime(2026, 10, 19),
        transactionType: InventoryTxType.values.first,
        gallons: 10,
        createdAt: DateTime(2026, 10, 19),
      );
      expect(dmInventoryColumns.containsAll(tx.toCloudJson().keys), isTrue);
    });
  });
}
