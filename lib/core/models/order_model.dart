import 'dart:convert';

/// Order data model with proper null safety
class OrderModel {
  final String id;
  final String? customerId;
  final String? ownerId;
  final String? stationName;
  final List<OrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final String paymentMethod;
  final String? paymentProofUrl;
  final String status;
  final String? assignedRiderId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Related data
  final CustomerModel? customer;
  final RiderModel? rider;

  OrderModel({
    required this.id,
    this.customerId,
    this.ownerId,
    this.stationName,
    this.items = const [],
    this.subtotal = 0.0,
    this.deliveryFee = 0.0,
    this.totalAmount = 0.0,
    this.paymentMethod = 'cod',
    this.paymentProofUrl,
    this.status = 'pending',
    this.assignedRiderId,
    this.createdAt,
    this.updatedAt,
    this.customer,
    this.rider,
  });

  factory OrderModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return OrderModel(id: '');
    }

    // `items` is a jsonb array, but cached or legacy rows may hold it as a
    // JSON-encoded string; malformed data yields no items rather than a crash.
    Object? itemsData = json['items'];
    if (itemsData is String) {
      try {
        itemsData = jsonDecode(itemsData);
      } on FormatException {
        itemsData = null;
      }
    }
    final parsedItems = itemsData is List
        ? itemsData
              .whereType<Map>()
              .map(
                (item) => OrderItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <OrderItem>[];

    return OrderModel(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString(),
      ownerId: json['owner_id']?.toString(),
      stationName: json['station_name']?.toString(),
      items: parsedItems,
      subtotal: _parseDouble(json['subtotal']),
      deliveryFee: _parseDouble(json['delivery_fee']),
      totalAmount: _parseDouble(json['total_amount']),
      paymentMethod: json['payment_method']?.toString() ?? 'cod',
      paymentProofUrl: json['payment_proof_url']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      assignedRiderId: json['assigned_rider_id']?.toString(),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
      customer: json['customer'] != null
          ? CustomerModel.fromJson(
              json['customer'] is Map<String, dynamic>
                  ? json['customer']
                  : null,
            )
          : null,
      rider: json['rider'] != null
          ? RiderModel.fromJson(
              json['rider'] is Map<String, dynamic> ? json['rider'] : null,
            )
          : null,
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isPreparing => status == 'preparing';
  bool get isReadyForPickup => status == 'ready_for_pickup';
  bool get isAssignedToRider => status == 'assigned_to_rider';
  bool get isOutForDelivery => status == 'out_for_delivery';
  bool get isDelivered => status == 'delivered';
  bool get isCancelled => status == 'cancelled';

  bool get hasRiderAssigned =>
      assignedRiderId != null && assignedRiderId!.isNotEmpty;

  String get displayStatus {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'preparing':
        return 'Preparing';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'assigned_to_rider':
        return 'Assigned to Rider';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Processing';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'owner_id': ownerId,
      'station_name': stationName,
      'items': items.map((e) => e.toJson()).toList(),
      'subtotal': subtotal,
      'delivery_fee': deliveryFee,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'payment_proof_url': paymentProofUrl,
      'status': status,
      'assigned_rider_id': assignedRiderId,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class OrderItem {
  final String? productName;
  final int quantity;
  final double priceAtPurchase;
  final double subtotal;

  OrderItem({
    this.productName,
    this.quantity = 1,
    this.priceAtPurchase = 0.0,
    this.subtotal = 0.0,
  });

  factory OrderItem.fromJson(Map<String, dynamic>? json) {
    if (json == null) return OrderItem();

    return OrderItem(
      productName: json['product_name']?.toString() ?? json['name']?.toString(),
      quantity: _parseInt(json['quantity']),
      priceAtPurchase: OrderModel._parseDouble(
        json['price_at_purchase'] ?? json['price'],
      ),
      subtotal: OrderModel._parseDouble(json['subtotal']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 1;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 1;
    return 1;
  }

  Map<String, dynamic> toJson() {
    return {
      'product_name': productName,
      'quantity': quantity,
      'price_at_purchase': priceAtPurchase,
      'subtotal': subtotal,
    };
  }
}

class CustomerModel {
  final String? id;
  final String? fullName;
  final String? phone;
  final String? completeAddress;
  final String? barangay;
  final String? town;

  CustomerModel({
    this.id,
    this.fullName,
    this.phone,
    this.completeAddress,
    this.barangay,
    this.town,
  });

  factory CustomerModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CustomerModel();

    return CustomerModel(
      id: json['id']?.toString(),
      fullName: json['full_name']?.toString(),
      phone: json['phone']?.toString(),
      completeAddress:
          json['complete_address']?.toString() ?? json['address']?.toString(),
      barangay: json['barangay']?.toString(),
      town: json['town']?.toString(),
    );
  }

  String get displayName =>
      fullName?.isNotEmpty == true ? fullName! : 'Customer';
  String get displayAddress => completeAddress?.isNotEmpty == true
      ? completeAddress!
      : 'No address provided';
  String get displayPhone => phone?.isNotEmpty == true ? phone! : '';
}

class RiderModel {
  final String? id;
  final String? fullName;
  final String? phone;
  final String? username;

  RiderModel({this.id, this.fullName, this.phone, this.username});

  factory RiderModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) return RiderModel();

    return RiderModel(
      id: json['id']?.toString(),
      fullName: json['full_name']?.toString(),
      phone: json['phone']?.toString(),
      username: json['username']?.toString(),
    );
  }

  String get displayName => fullName?.isNotEmpty == true
      ? fullName!
      : (username?.isNotEmpty == true ? username! : 'Rider');
  String get initials {
    final name = displayName;
    if (name.isEmpty) return 'R';
    return name.split(' ').first[0].toUpperCase();
  }
}
