List<Map<String, dynamic>> prioritizeOwnerOrders(
  Iterable<Map<String, dynamic>> orders,
) {
  final prioritized = orders.toList();
  prioritized.sort((a, b) {
    final priorityDifference =
        _actionPriority(a['status']) - _actionPriority(b['status']);
    if (priorityDifference != 0) return priorityDifference;

    final aCreated = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final bCreated = DateTime.tryParse(b['created_at']?.toString() ?? '');
    if (aCreated != null && bCreated != null) {
      final ageDifference = aCreated.compareTo(bCreated);
      if (ageDifference != 0) return ageDifference;
    } else if (aCreated != null) {
      return -1;
    } else if (bCreated != null) {
      return 1;
    }

    return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
  });
  return prioritized;
}

int _actionPriority(dynamic status) {
  return switch ((status ?? '').toString().toLowerCase()) {
    'pending' => 0,
    'accepted' => 1,
    'preparing' => 2,
    'ready_for_pickup' => 3,
    'assigned_to_rider' => 4,
    'out_for_delivery' => 5,
    _ => 6,
  };
}
