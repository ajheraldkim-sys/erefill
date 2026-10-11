enum InventoryTxType { load, deduct, adjustment }

class DmInventoryTx {
  final String id;
  final String ownerId;
  final DateTime transactionDate;
  final InventoryTxType transactionType;
  final double gallons;
  final String? notes;
  final String? deliveryId;
  final DateTime createdAt;

  const DmInventoryTx({
    required this.id,
    required this.ownerId,
    required this.transactionDate,
    required this.transactionType,
    required this.gallons,
    this.notes,
    this.deliveryId,
    required this.createdAt,
  });

  factory DmInventoryTx.fromJson(Map<String, dynamic> json) {
    return DmInventoryTx(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      transactionDate: json['transaction_date'] != null
          ? DateTime.parse(json['transaction_date'].toString())
          : DateTime.now(),
      transactionType: DmInventoryTx.parseType(
        json['transaction_type'] as String?,
      ),
      gallons: (json['gallons'] as num).toDouble(),
      notes: json['notes'] as String?,
      deliveryId: json['delivery_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
    );
  }

  static InventoryTxType parseType(String? type) {
    switch (type) {
      case 'load':
        return InventoryTxType.load;
      case 'deduct':
        return InventoryTxType.deduct;
      default:
        return InventoryTxType.adjustment;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'transaction_date':
        '${transactionDate.year}-${transactionDate.month.toString().padLeft(2, '0')}-${transactionDate.day.toString().padLeft(2, '0')}',
    'transaction_type': transactionType.name,
    'gallons': gallons,
    'notes': notes,
    'delivery_id': deliveryId,
  };
}
