/// Resolves display price for a station row using products, then owner_settings.
class StationPriceHelpers {
  StationPriceHelpers._();

  static Map<String, double> mapFromSettingsRows(List<dynamic> rows) {    final prices = <String, double>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final ownerId = row['owner_id']?.toString();
      if (ownerId == null) continue;
      final price = (row['price_per_gallon'] as num?)?.toDouble();
      if (price != null && price > 0) {
        prices[ownerId] = price;
      }
    }
    return prices;
  }

  static Map<String, double> mapFromProductRows(List<dynamic> rows) {
    final prices = <String, double>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final ownerId = row['owner_id']?.toString();
      if (ownerId == null) continue;
      final available = row['is_available'];
      if (available == false) continue;
      final price = (row['price'] as num?)?.toDouble();
      if (price == null || price <= 0) continue;
      final existing = prices[ownerId];
      if (existing == null || price < existing) {
        prices[ownerId] = price;
      }
    }
    return prices;
  }

  static double priceForStation(
    Map<String, dynamic> station, {
    Map<String, double>? ownerPrices,
    Map<String, double>? productPrices,
  }) {
    final ownerId = station['id']?.toString();
    if (productPrices != null && ownerId != null) {
      final fromProduct = productPrices[ownerId];
      if (fromProduct != null && fromProduct > 0) return fromProduct;
    }
    if (ownerPrices != null && ownerId != null) {
      final fromSettings = ownerPrices[ownerId];
      if (fromSettings != null && fromSettings > 0) return fromSettings;
    }

    final raw = station['price_per_gallon'];
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw') ?? 0;
  }

  static Map<String, dynamic> withResolvedPrice(
    Map<String, dynamic> station, {
    Map<String, double>? ownerPrices,
    Map<String, double>? productPrices,
  }) {
    final copy = Map<String, dynamic>.from(station);
    copy['price_per_gallon'] = priceForStation(
      station,
      ownerPrices: ownerPrices,
      productPrices: productPrices,
    );
    return copy;
  }
}
