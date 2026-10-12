class CustomerSubscription {
  final String id;
  final String customerId;
  final String stationId;
  final String stationName;
  final String? stationPhotoUrl;
  final int quantity;
  final String waterType;
  final double estimatedPrice;
  final String frequency; // 'every_3_days', 'twice_weekly', 'weekly', 'bi_weekly', 'monthly'
  final String preferredTimeSlot; // 'morning', 'afternoon', 'evening'
  final String deliveryAddress;
  final String paymentMethod;
  final bool isActive;
  final DateTime nextDeliveryDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomerSubscription({
    required this.id,
    required this.customerId,
    required this.stationId,
    required this.stationName,
    this.stationPhotoUrl,
    required this.quantity,
    required this.waterType,
    required this.estimatedPrice,
    required this.frequency,
    required this.preferredTimeSlot,
    required this.deliveryAddress,
    this.paymentMethod = 'cod',
    this.isActive = true,
    required this.nextDeliveryDate,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime computeNextDeliveryDate(DateTime from, String frequency) {
    switch (frequency) {
      case 'every_3_days':
        return from.add(const Duration(days: 3));
      case 'twice_weekly':
        return from.add(const Duration(days: 4));
      case 'weekly':
        return from.add(const Duration(days: 7));
      case 'bi_weekly':
        return from.add(const Duration(days: 14));
      case 'monthly':
        return DateTime(from.year, from.month + 1, from.day);
      default:
        return from.add(const Duration(days: 7));
    }
  }

  static String formatFrequencyLabel(String freq) {
    switch (freq) {
      case 'every_3_days':
        return 'Every 3 Days';
      case 'twice_weekly':
        return 'Twice a Week (Every 4 Days)';
      case 'weekly':
        return 'Weekly Refill';
      case 'bi_weekly':
        return 'Every 2 Weeks';
      case 'monthly':
        return 'Monthly Refill';
      default:
        return 'Regular Refill';
    }
  }

  static String formatTimeSlotLabel(String slot) {
    switch (slot) {
      case 'morning':
        return 'Morning (8:00 AM - 11:30 AM)';
      case 'afternoon':
        return 'Afternoon (1:00 PM - 4:30 PM)';
      case 'evening':
        return 'Evening (5:00 PM - 7:30 PM)';
      default:
        return 'Anytime during station hours';
    }
  }

  factory CustomerSubscription.fromJson(Map<String, dynamic> json) {
    return CustomerSubscription(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      stationId: json['station_id']?.toString() ?? '',
      stationName: json['station_name']?.toString() ?? 'Water Station',
      stationPhotoUrl: json['station_photo_url']?.toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      waterType: json['water_type']?.toString() ?? 'Purified',
      estimatedPrice: (json['estimated_price'] as num?)?.toDouble() ?? 30.0,
      frequency: json['frequency']?.toString() ?? 'weekly',
      preferredTimeSlot: json['preferred_time_slot']?.toString() ?? 'morning',
      deliveryAddress: json['delivery_address']?.toString() ?? '',
      paymentMethod: json['payment_method']?.toString() ?? 'cod',
      isActive: json['is_active'] == true || json['is_active'] == 1,
      nextDeliveryDate: json['next_delivery_date'] != null
          ? DateTime.tryParse(json['next_delivery_date'].toString()) ??
              DateTime.now().add(const Duration(days: 7))
          : DateTime.now().add(const Duration(days: 7)),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'station_id': stationId,
      'station_name': stationName,
      'station_photo_url': stationPhotoUrl,
      'quantity': quantity,
      'water_type': waterType,
      'estimated_price': estimatedPrice,
      'frequency': frequency,
      'preferred_time_slot': preferredTimeSlot,
      'delivery_address': deliveryAddress,
      'payment_method': paymentMethod,
      'is_active': isActive,
      'next_delivery_date': nextDeliveryDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  CustomerSubscription copyWith({
    bool? isActive,
    int? quantity,
    String? frequency,
    String? preferredTimeSlot,
    String? deliveryAddress,
    DateTime? nextDeliveryDate,
  }) {
    return CustomerSubscription(
      id: id,
      customerId: customerId,
      stationId: stationId,
      stationName: stationName,
      stationPhotoUrl: stationPhotoUrl,
      quantity: quantity ?? this.quantity,
      waterType: waterType,
      estimatedPrice: estimatedPrice,
      frequency: frequency ?? this.frequency,
      preferredTimeSlot: preferredTimeSlot ?? this.preferredTimeSlot,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      paymentMethod: paymentMethod,
      isActive: isActive ?? this.isActive,
      nextDeliveryDate: nextDeliveryDate ?? this.nextDeliveryDate,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

