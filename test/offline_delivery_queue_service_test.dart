import 'package:erefill/features/dashboard/rider/services/offline_delivery_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final queue = OfflineDeliveryQueueService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Offline delivery queue persistence', () {
    test(
      'enqueues and deduplicates updates without losing proof data',
      () async {
        final createdAt = DateTime.utc(2026, 10, 16, 1);
        await queue.enqueueDelivery(
          QueuedDelivery(
            orderId: 'order-1',
            status: 'delivered',
            localPhotoPath: r'C:\proofs\delivery.jpg',
            deliveryNote: 'Left at the door',
            createdAt: createdAt,
          ),
        );
        await queue.enqueueDelivery(
          QueuedDelivery(
            orderId: 'order-1',
            status: 'delivered',
            emptyGallonsReturned: 2,
          ),
        );

        final pending = await queue.getPendingDeliveries();

        expect(pending, hasLength(1));
        expect(pending.single.localPhotoPath, r'C:\proofs\delivery.jpg');
        expect(pending.single.deliveryNote, 'Left at the door');
        expect(pending.single.emptyGallonsReturned, 2);
        expect(pending.single.createdAt, createdAt);
        expect(await queue.getPendingCount(), 1);
      },
    );

    test('rejects updates without an order ID', () async {
      await expectLater(
        queue.enqueueDelivery(QueuedDelivery(orderId: ' ')),
        throwsArgumentError,
      );
    });

    test('removes an update after successful synchronization', () async {
      await queue.enqueueDelivery(QueuedDelivery(orderId: 'order-2'));

      await queue.removeDelivery('order-2');

      expect(await queue.getPendingDeliveries(), isEmpty);
    });
  });
}
