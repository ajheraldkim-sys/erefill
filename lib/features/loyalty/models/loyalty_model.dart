class LoyaltyProfile {
  final String userId;
  final String referralCode;
  final int pointsBalance;
  final int totalEarned;
  final int totalRedeemed;
  final String? referredBy;
  final DateTime updatedAt;

  LoyaltyProfile({
    required this.userId,
    required this.referralCode,
    this.pointsBalance = 0,
    this.totalEarned = 0,
    this.totalRedeemed = 0,
    this.referredBy,
    required this.updatedAt,
  });

  factory LoyaltyProfile.fromJson(Map<String, dynamic> json) {
    return LoyaltyProfile(
      userId: json['user_id']?.toString() ?? '',
      referralCode: json['referral_code']?.toString() ?? '',
      pointsBalance: (json['points_balance'] as num?)?.toInt() ?? 0,
      totalEarned: (json['total_earned'] as num?)?.toInt() ?? 0,
      totalRedeemed: (json['total_redeemed'] as num?)?.toInt() ?? 0,
      referredBy: json['referred_by']?.toString(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'referral_code': referralCode,
      'points_balance': pointsBalance,
      'total_earned': totalEarned,
      'total_redeemed': totalRedeemed,
      'referred_by': referredBy,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  LoyaltyProfile copyWith({
    int? pointsBalance,
    int? totalEarned,
    int? totalRedeemed,
    String? referredBy,
  }) {
    return LoyaltyProfile(
      userId: userId,
      referralCode: referralCode,
      pointsBalance: pointsBalance ?? this.pointsBalance,
      totalEarned: totalEarned ?? this.totalEarned,
      totalRedeemed: totalRedeemed ?? this.totalRedeemed,
      referredBy: referredBy ?? this.referredBy,
      updatedAt: DateTime.now(),
    );
  }
}

class LoyaltyRewardVoucher {
  final String id;
  final String userId;
  final String code;
  final String title;
  final String description;
  final double discountAmount;
  final int pointsCost;
  final bool isDeliveryDiscount;
  final bool isUsed;
  final DateTime createdAt;
  final DateTime expiresAt;

  LoyaltyRewardVoucher({
    required this.id,
    required this.userId,
    required this.code,
    required this.title,
    required this.description,
    required this.discountAmount,
    required this.pointsCost,
    this.isDeliveryDiscount = false,
    this.isUsed = false,
    required this.createdAt,
    required this.expiresAt,
  });

  factory LoyaltyRewardVoucher.fromJson(Map<String, dynamic> json) {
    return LoyaltyRewardVoucher(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Reward Voucher',
      description: json['description']?.toString() ?? '',
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      pointsCost: (json['points_cost'] as num?)?.toInt() ?? 0,
      isDeliveryDiscount: json['is_delivery_discount'] == true,
      isUsed: json['is_used'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString()) ??
              DateTime.now().add(const Duration(days: 30))
          : DateTime.now().add(const Duration(days: 30)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'code': code,
      'title': title,
      'description': description,
      'discount_amount': discountAmount,
      'points_cost': pointsCost,
      'is_delivery_discount': isDeliveryDiscount,
      'is_used': isUsed,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }
}

class LoyaltyTransaction {
  final String id;
  final String userId;
  final int points;
  final String description;
  final DateTime createdAt;

  LoyaltyTransaction({
    required this.id,
    required this.userId,
    required this.points,
    required this.description,
    required this.createdAt,
  });

  factory LoyaltyTransaction.fromJson(Map<String, dynamic> json) {
    return LoyaltyTransaction(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      points: (json['points'] as num?)?.toInt() ?? 0,
      description: json['description']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'points': points,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

