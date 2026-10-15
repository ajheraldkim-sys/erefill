import '../../../models/cart_model.dart';

class CheckoutPaymentOption {
  final String type;
  final String label;
  final bool available;
  final String? reason;

  const CheckoutPaymentOption({
    required this.type,
    required this.label,
    required this.available,
    this.reason,
  });

  factory CheckoutPaymentOption.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? json['method'] ?? 'cod')
        .toString()
        .toLowerCase();
    return CheckoutPaymentOption(
      type: type,
      label: json['label']?.toString() ?? CheckoutRules.paymentLabel(type),
      available: json['available'] == true,
      reason: json['reason']?.toString(),
    );
  }
}

class CheckoutPreflightResult {
  final bool canSubmit;
  final String? message;

  const CheckoutPreflightResult._(this.canSubmit, this.message);

  const CheckoutPreflightResult.ok() : this._(true, null);
  const CheckoutPreflightResult.blocked(String message)
    : this._(false, message);
}

class CheckoutRules {
  const CheckoutRules._();

  static const onlinePaymentMethods = {'gcash', 'maya', 'card'};

  static const cashPaymentOption = CheckoutPaymentOption(
    type: 'cod',
    label: 'Cash',
    available: true,
  );

  static const cashOnlyPaymentMethods = [cashPaymentOption];

  static const standardPaymentMethods = [
    CheckoutPaymentOption(
      type: 'cod',
      label: 'Cash on Delivery',
      available: true,
    ),
    CheckoutPaymentOption(
      type: 'gcash',
      label: 'GCash',
      available: true,
    ),
    CheckoutPaymentOption(
      type: 'maya',
      label: 'Maya',
      available: true,
    ),
    CheckoutPaymentOption(
      type: 'card',
      label: 'Credit/Debit Card',
      available: true,
    ),
  ];

  static bool isOnlinePayment(String? method) {
    return onlinePaymentMethods.contains((method ?? 'cod').toLowerCase());
  }

  /// Online orders are not actionable or trackable until the payment provider
  /// confirms them. Cash-on-delivery orders are trackable immediately.
  static bool canTrackOrder(Map<String, dynamic> order) {
    if (!isOnlinePayment(order['payment_method']?.toString())) return true;
    return const {'success', 'paid', 'succeeded', 'completed'}.contains(
      order['payment_status']?.toString().trim().toLowerCase(),
    );
  }

  static String paymentLabel(String? method) {
    switch ((method ?? 'cod').toLowerCase()) {
      case 'gcash':
        return 'GCash';
      case 'maya':
        return 'Maya';
      case 'card':
        return 'Credit/Debit Card';
      default:
        return 'Cash on Delivery';
    }
  }

  static bool isPaymentAvailable(
    String method,
    List<CheckoutPaymentOption> options,
  ) {
    return options.any(
      (option) => option.type == method.toLowerCase() && option.available,
    );
  }

  static List<CheckoutPaymentOption> normalizePaymentOptions(
    List<dynamic> rows,
  ) {
    final parsed = rows
        .whereType<Map>()
        .map(
          (row) =>
              CheckoutPaymentOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();

    if (parsed.isEmpty) return cashOnlyPaymentMethods;
    if (!parsed.any((option) => option.type == 'cod')) {
      return [cashPaymentOption, ...parsed];
    }
    return parsed;
  }

  static Map<String, dynamic> useSavedAddress(
    Map<String, dynamic> profile,
    Map<String, dynamic> address,
  ) {
    return {
      ...profile,
      'complete_address': address['complete_address'],
      'barangay': address['barangay'],
      'town': address['town'],
      'landmark': address['landmark'],
      'latitude': address['latitude'],
      'longitude': address['longitude'],
      'map_pin_town': address['map_pin_town'],
    };
  }

  static List<CheckoutPaymentOption> selectableMethods(
    List<CheckoutPaymentOption> methods,
  ) {
    if (methods.isEmpty) return cashOnlyPaymentMethods;
    if (!methods.any((option) => option.type == 'cod')) {
      return [cashPaymentOption, ...methods];
    }
    return methods;
  }

  static CheckoutPreflightResult validate({
    required CartProvider cart,
    required String? customerId,
    required bool isStationOpen,
    required Map<String, dynamic>? customerProfile,
  }) {
    if (cart.totalItems == 0) {
      return const CheckoutPreflightResult.blocked(
        'Your refill order is empty. Choose a water type first.',
      );
    }
    if (customerId == null) {
      return const CheckoutPreflightResult.blocked(
        'Please log in to place an order.',
      );
    }
    if (!isStationOpen) {
      return const CheckoutPreflightResult.blocked(
        'This station is currently closed.',
      );
    }

    final deliveryIssue = deliveryProfileIssue(customerProfile);
    if (deliveryIssue != null) {
      return CheckoutPreflightResult.blocked(deliveryIssue);
    }

    return const CheckoutPreflightResult.ok();
  }

  /// Returns a user-facing message when delivery details are incomplete.
  static String? deliveryProfileIssue(Map<String, dynamic>? customerProfile) {
    final completeAddress =
        customerProfile?['complete_address']?.toString().trim() ?? '';
    if (completeAddress.isEmpty) {
      return 'Add your delivery address below to continue.';
    }

    // A saved-address pin is verified when an explicit map_pin_town is provided.
    // Legacy profiles or addresses where map_pin_town is null remain supported as
    // long as they have usable delivery coordinates.
    final town = customerProfile?['town']?.toString();
    final pinTown = customerProfile?['map_pin_town']?.toString();
    if (pinTown != null &&
        pinTown.isNotEmpty &&
        town != null &&
        town.isNotEmpty &&
        pinTown != town) {
      return 'Confirm this address on the map before using it for delivery.';
    }

    if (!hasUsableDeliveryCoordinates(customerProfile)) {
      return 'Pin your map location on your delivery address to continue.';
    }

    return null;
  }

  static bool isDeliveryProfileReady(Map<String, dynamic>? customerProfile) {
    return deliveryProfileIssue(customerProfile) == null;
  }

  /// `0,0` is a fallback/sentinel, not a deliverable map location. The
  /// previous null-only check allowed it through and sent orders to a
  /// location inconsistent with the selected municipality.
  static bool hasUsableDeliveryCoordinates(
    Map<String, dynamic>? customerProfile,
  ) {
    final latitude = (customerProfile?['latitude'] as num?)?.toDouble();
    final longitude = (customerProfile?['longitude'] as num?)?.toDouble();
    return latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        (latitude != 0 || longitude != 0);
  }

  static String statusTitle(String status) {
    switch (status) {
      case 'pending':
        return 'Order Placed';
      case 'accepted':
        return 'Accepted';
      case 'preparing':
        return 'Preparing';
      case 'ready':
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'rider_assigned':
      case 'assigned_to_rider':
        return 'Assigned to Rider';
      case 'delivering':
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Order Status';
    }
  }
}
