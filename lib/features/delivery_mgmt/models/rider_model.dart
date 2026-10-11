class DmRider {
  final String id;
  final String ownerId;
  final String? linkedUserId;
  final String fullName;
  final String? phone;
  final String? email;
  final double commissionPerGallon;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Computed / joined fields
  final int deliveryCount;
  final double totalGallons;

  const DmRider({
    required this.id,
    required this.ownerId,
    this.linkedUserId,
    required this.fullName,
    this.phone,
    this.email,
    required this.commissionPerGallon,
    required this.createdAt,
    required this.updatedAt,
    this.deliveryCount = 0,
    this.totalGallons = 0,
  });

  factory DmRider.fromJson(Map<String, dynamic> json) {
    return DmRider(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      linkedUserId: json['linked_user_id'] as String?,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      commissionPerGallon:
          (json['commission_per_gallon'] as num?)?.toDouble() ?? 0,
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
    'linked_user_id': linkedUserId,
    'full_name': fullName,
    'phone': phone,
    'email': email,
    'commission_per_gallon': commissionPerGallon,
  };

  DmRider copyWith({
    String? id,
    String? ownerId,
    String? linkedUserId,
    String? fullName,
    String? phone,
    String? email,
    double? commissionPerGallon,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? deliveryCount,
    double? totalGallons,
  }) {
    return DmRider(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      linkedUserId: linkedUserId ?? this.linkedUserId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      commissionPerGallon: commissionPerGallon ?? this.commissionPerGallon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveryCount: deliveryCount ?? this.deliveryCount,
      totalGallons: totalGallons ?? this.totalGallons,
    );
  }
}
