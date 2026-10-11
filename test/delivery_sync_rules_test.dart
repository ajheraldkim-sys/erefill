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
}
