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

    test('delivery confirmation requires both photo and signature paths', () {
      expect(
        hasRequiredDeliveryEvidence(
          photoPath: r'C:\proofs\delivery.jpg',
          signaturePath: r'C:\proofs\signature.png',
        ),
        isTrue,
      );
      expect(
        hasRequiredDeliveryEvidence(
          photoPath: r'C:\proofs\delivery.jpg',
          signaturePath: null,
        ),
        isFalse,
      );
      expect(
        hasRequiredDeliveryEvidence(photoPath: ' ', signaturePath: 'proof.png'),
        isFalse,
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
