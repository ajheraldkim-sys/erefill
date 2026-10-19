class DmDelivery {
  final String id;
  final String ownerId;
  final String? riderId;
  final String? riderName; // denormalized for display
  final DateTime deliveryDate;
  final double gallons;
  final double pricePerGallon;
  final double expenses;
  final String? notes;
  final double emptyGallonsReturned;
  final double commission;
  final double creditAmount;
  final bool isSynced;
  final String? localId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DmDelivery({
    required this.id,
    required this.ownerId,
    this.riderId,
    this.riderName,
    required this.deliveryDate,
    required this.gallons,
    required this.pricePerGallon,
    this.expenses = 0,
    this.notes,
    this.emptyGallonsReturned = 0,
    required this.commission,
    this.creditAmount = 0,
    this.isSynced = false,
    this.localId,
    required this.createdAt,
    required this.updatedAt,
  });

  double get income => gallons * pricePerGallon;
  double get ownerProfit => income - expenses - commission;

  factory DmDelivery.fromJson(Map<String, dynamic> json) {
    return DmDelivery(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      riderId: json['rider_id'] as String?,
      riderName: json['rider_name'] as String?,
      deliveryDate: json['delivery_date'] != null
          ? DateTime.parse(json['delivery_date'].toString())
          : DateTime.now(),
      gallons: (json['gallons'] as num).toDouble(),
      pricePerGallon: (json['price_per_gallon'] as num).toDouble(),
      expenses: (json['expenses'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      emptyGallonsReturned:
          (json['empty_gallons_returned'] as num?)?.toDouble() ?? 0,
      commission: (json['commission'] as num?)?.toDouble() ?? 0,
      creditAmount: (json['credit_amount'] as num?)?.toDouble() ?? 0,
      isSynced: json['is_synced'] as bool? ?? false,
      localId: json['local_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'rider_id': riderId,
    'rider_name': riderName,
    'delivery_date':
        '${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}-${deliveryDate.day.toString().padLeft(2, '0')}',
    'gallons': gallons,
    'price_per_gallon': pricePerGallon,
    'expenses': expenses,
    'notes': notes,
    'empty_gallons_returned': emptyGallonsReturned,
    'commission': commission,
    'credit_amount': creditAmount,
    'is_synced': isSynced,
    'local_id': localId,
  };

  /// Serializes model for Supabase cloud upsert, removing local-only columns and handling nullable UUIDs
  Map<String, dynamic> toCloudJson() {
    final cleanRiderId =
        (riderId != null && riderId!.trim().isNotEmpty) ? riderId!.trim() : null;
    return {
      'id': id,
      'owner_id': ownerId,
      'rider_id': cleanRiderId,
      'delivery_date':
          '${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}-${deliveryDate.day.toString().padLeft(2, '0')}',
      'gallons': gallons,
      'price_per_gallon': pricePerGallon,
      'expenses': expenses,
      'notes': notes,
      'empty_gallons_returned': emptyGallonsReturned,
      'commission': commission,
      'credit_amount': creditAmount,
      'is_synced': true,
      'local_id': localId ?? id,
    };
  }

  DmDelivery copyWith({
    String? id,
    String? ownerId,
    String? riderId,
    String? riderName,
    DateTime? deliveryDate,
    double? gallons,
    double? pricePerGallon,
    double? expenses,
    String? notes,
    double? emptyGallonsReturned,
    double? commission,
    double? creditAmount,
    bool? isSynced,
    String? localId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DmDelivery(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      riderId: riderId ?? this.riderId,
      riderName: riderName ?? this.riderName,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      gallons: gallons ?? this.gallons,
      pricePerGallon: pricePerGallon ?? this.pricePerGallon,
      expenses: expenses ?? this.expenses,
      notes: notes ?? this.notes,
      emptyGallonsReturned: emptyGallonsReturned ?? this.emptyGallonsReturned,
      commission: commission ?? this.commission,
      creditAmount: creditAmount ?? this.creditAmount,
      isSynced: isSynced ?? this.isSynced,
      localId: localId ?? this.localId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
