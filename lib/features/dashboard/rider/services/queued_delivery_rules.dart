enum QueuedDeliveryOperation { transitionStatus, confirmDelivery }

QueuedDeliveryOperation queuedDeliveryOperation(String status) =>
    status == 'delivered'
    ? QueuedDeliveryOperation.confirmDelivery
    : QueuedDeliveryOperation.transitionStatus;

bool isRetryableNetworkError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('socket') ||
      message.contains('network') ||
      message.contains('timeout') ||
      message.contains('connection') ||
      message.contains('failed host lookup') ||
      message.contains('clientexception');
}

bool hasRequiredDeliveryEvidence({
  required String? photoPath,
  required String? signaturePath,
}) =>
    photoPath != null &&
    photoPath.trim().isNotEmpty &&
    signaturePath != null &&
    signaturePath.trim().isNotEmpty;
