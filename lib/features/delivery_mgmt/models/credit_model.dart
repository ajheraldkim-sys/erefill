enum CreditType { customer, rider }

class DmCredit {
  final String id;
  final String ownerId;
  final String? riderId;
  final String? riderName;
  final String? deliveryId;
  final CreditType creditType;
  final String debtorName;
  final double amount;
  final double paidAmount;
  final bool isPaid;
  final DateTime? paymentDate;
  final String? notes;
  final bool isSynced;
  final String? localId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DmCredit({
    required this.id,
    required this.ownerId,
    this.riderId,
    this.riderName,
    this.deliveryId,
    required this.creditType,
    required this.debtorName,
    required this.amount,
    this.paidAmount = 0,
    this.isPaid = false,
    this.paymentDate,
    this.notes,
    this.isSynced = false,
    this.localId,
    required this.createdAt,
    required this.updatedAt,
  });

  double get remaining => amount - paidAmount;

  factory DmCredit.fromJson(Map<String, dynamic> json) {
    return DmCredit(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      riderId: json['rider_id'] as String?,
      riderName: json['rider_name'] as String?,
      deliveryId: json['delivery_id'] as String?,
      creditType: (json['credit_type'] as String?) == 'rider'
          ? CreditType.rider
          : CreditType.customer,
      debtorName: json['debtor_name'] as String,
      amount: (json['amount'] as num).toDouble(),
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      isPaid: json['is_paid'] as bool? ?? false,
      paymentDate: json['payment_date'] != null
          ? DateTime.parse(json['payment_date'].toString())
          : null,
      notes: json['notes'] as String?,
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
    'delivery_id': deliveryId,
    'credit_type': creditType == CreditType.rider ? 'rider' : 'customer',
    'debtor_name': debtorName,
    'amount': amount,
    'paid_amount': paidAmount,
    'is_paid': isPaid,
    'payment_date': paymentDate?.toIso8601String().split('T').first,
    'notes': notes,
    'is_synced': isSynced,
    'local_id': localId,
  };

  DmCredit copyWith({
    String? id,
    String? ownerId,
    String? riderId,
    String? riderName,
    String? deliveryId,
    CreditType? creditType,
    String? debtorName,
    double? amount,
    double? paidAmount,
    bool? isPaid,
    DateTime? paymentDate,
    String? notes,
    bool? isSynced,
    String? localId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DmCredit(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      riderId: riderId ?? this.riderId,
      riderName: riderName ?? this.riderName,
      deliveryId: deliveryId ?? this.deliveryId,
      creditType: creditType ?? this.creditType,
      debtorName: debtorName ?? this.debtorName,
      amount: amount ?? this.amount,
      paidAmount: paidAmount ?? this.paidAmount,
      isPaid: isPaid ?? this.isPaid,
      paymentDate: paymentDate ?? this.paymentDate,
      notes: notes ?? this.notes,
      isSynced: isSynced ?? this.isSynced,
      localId: localId ?? this.localId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
