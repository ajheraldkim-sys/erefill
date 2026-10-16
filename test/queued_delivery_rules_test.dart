import 'package:erefill/features/dashboard/rider/services/queued_delivery_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Queued delivery operations', () {
    test('only completed deliveries use proof confirmation', () {
      expect(
        queuedDeliveryOperation('delivered'),
        QueuedDeliveryOperation.confirmDelivery,
      );
      expect(
        queuedDeliveryOperation('out_for_delivery'),
        QueuedDeliveryOperation.transitionStatus,
      );
      expect(
        queuedDeliveryOperation('assigned_to_rider'),
        QueuedDeliveryOperation.transitionStatus,
      );
    });

    test('only likely transport errors are queued for retry', () {
      expect(isRetryableNetworkError(Exception('SocketException')), isTrue);
      expect(isRetryableNetworkError(Exception('request timeout')), isTrue);
      expect(
        isRetryableNetworkError(StateError('invalid status transition')),
        isFalse,
      );
      expect(isRetryableNetworkError(StateError('permission denied')), isFalse);
    });
  });
}
