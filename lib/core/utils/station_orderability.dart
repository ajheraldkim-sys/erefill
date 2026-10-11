/// Shared rules for whether a station can accept customer orders.
abstract final class StationOrderability {
  static bool hasLocation(Map<String, dynamic> station) {
    final lat = (station['latitude'] as num?)?.toDouble() ??
        (station['lat'] as num?)?.toDouble();
    final lng = (station['longitude'] as num?)?.toDouble() ??
        (station['lng'] as num?)?.toDouble();
    return lat != null && lng != null && lat != 0 && lng != 0;
  }

  static bool hasPricing(
    Map<String, dynamic> station, {
    Map<String, double>? ownerSettingsPrices,
    Map<String, double>? productPrices,
  }) {
    final ownerId = station['id']?.toString();
    if (ownerId == null) return false;

    final productPrice = productPrices?[ownerId];
    if (productPrice != null && productPrice > 0) return true;

    final settingsPrice = ownerSettingsPrices?[ownerId];
    if (settingsPrice != null && settingsPrice > 0) return true;

    final profilePrice = (station['price_per_gallon'] as num?)?.toDouble();
    return profilePrice != null && profilePrice > 0;
  }

  static bool isOpenForOrders(Map<String, dynamic> station) {
    final availability = station['station_availability']?.toString();
    if (availability == 'closed' ||
        availability == 'maintenance' ||
        availability == 'busy') {
      return false;
    }
    return (station['is_open'] as bool?) ?? true;
  }

  static bool isOrderable(
    Map<String, dynamic> station, {
    Map<String, double>? ownerSettingsPrices,
    Map<String, double>? productPrices,
    bool requireProduct = false,
  }) {
    if (!hasLocation(station)) return false;
    if (!isOpenForOrders(station)) return false;

    final ownerId = station['id']?.toString();
    if (ownerId == null) return false;

    if (requireProduct) {
      final productPrice = productPrices?[ownerId];
      return productPrice != null && productPrice > 0;
    }

    return hasPricing(
      station,
      ownerSettingsPrices: ownerSettingsPrices,
      productPrices: productPrices,
    );
  }
}
