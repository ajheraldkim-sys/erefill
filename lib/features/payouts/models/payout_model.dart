class RiderPayoutRequest {
  final String id;
  final String riderId;
  final String riderName;
  final String ownerId;
  final String? stationName;
  final double amount;
  final String payoutMethod; // 'gcash', 'maya', 'cash', 'bank'
  final String accountNumber;
  final String accountName;
  final String status; // 'pending', 'approved', 'disbursed', 'rejected'
  final String? referenceNumber;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? disbursedAt;

  RiderPayoutRequest({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.ownerId,
    this.stationName,
    required this.amount,
    required this.payoutMethod,
    required this.accountNumber,
    required this.accountName,
    this.status = 'pending',
    this.referenceNumber,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    this.disbursedAt,
  });

  factory RiderPayoutRequest.fromJson(Map<String, dynamic> json) {
    return RiderPayoutRequest(
      id: json['id']?.toString() ?? '',
      riderId: json['rider_id']?.toString() ?? '',
      riderName: json['rider_name']?.toString() ?? 'Rider',
      ownerId: json['owner_id']?.toString() ?? '',
      stationName: json['station_name']?.toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      payoutMethod: json['payout_method']?.toString() ?? 'gcash',
      accountNumber: json['account_number']?.toString() ?? '',
      accountName: json['account_name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      referenceNumber: json['reference_number']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      disbursedAt: json['disbursed_at'] != null
          ? DateTime.tryParse(json['disbursed_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rider_id': riderId,
      'rider_name': riderName,
      'owner_id': ownerId,
      'station_name': stationName,
      'amount': amount,
      'payout_method': payoutMethod,
      'account_number': accountNumber,
      'account_name': accountName,
      'status': status,
      'reference_number': referenceNumber,
      'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'disbursed_at': disbursedAt?.toIso8601String(),
    };
  }

  RiderPayoutRequest copyWith({
    String? status,
    String? referenceNumber,
    String? rejectionReason,
    DateTime? disbursedAt,
  }) {
    return RiderPayoutRequest(
      id: id,
      riderId: riderId,
      riderName: riderName,
      ownerId: ownerId,
      stationName: stationName,
      amount: amount,
      payoutMethod: payoutMethod,
      accountNumber: accountNumber,
      accountName: accountName,
      status: status ?? this.status,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      disbursedAt: disbursedAt ?? this.disbursedAt,
    );
  }
}

