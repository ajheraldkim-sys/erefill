import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db_tables.dart';
import '../water_types.dart';

/// Every station sells exactly one product: the refill of its registered
/// water type. These helpers load and resolve that product.
abstract final class OrderProductHelpers {
  /// Columns guaranteed on all deployed `products` schemas.
  static const coreSelectFields =
      'id, name, price, category, is_available, description, container_size, stock_level';

  /// Owner view — adds the refill metadata columns.
  static const catalogSelectFields =
      'id, name, description, price, category, is_available, created_at, container_size, stock_level, preparation_minutes';

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static bool isValidProductId(dynamic id) {
    final value = id?.toString().trim() ?? '';
    return _uuidPattern.hasMatch(value);
  }

  static bool isDisplayOnly(Map<String, dynamic>? product) {
    return product?['_display_only'] == true;
  }

  static bool isRealProduct(Map<String, dynamic>? product) {
    if (product == null || isDisplayOnly(product)) return false;
    return isValidProductId(product['id']) && !isNonWaterProduct(product);
  }

  /// Categories of legacy containers/caps that are not the station's water.
  static const _nonWaterCategories = {'accessories', 'products', 'containers'};

  static bool isNonWaterProduct(Map<String, dynamic>? product) {
    final category = product?['category']?.toString().trim().toLowerCase();
    return category != null && _nonWaterCategories.contains(category);
  }

  /// The station's product from a loaded list (older data may still hold
  /// several rows, including containers; the first real water one wins).
  static Map<String, dynamic>? defaultFromList(List<dynamic> products) {
    Map<String, dynamic>? fallback;
    for (final row in products.whereType<Map>()) {
      final product = Map<String, dynamic>.from(row);
      if (isRealProduct(product)) return product;
      if (!isNonWaterProduct(product)) fallback ??= product;
    }
    return fallback;
  }

  /// Fills optional refill metadata when a query didn't select it. The values
  /// mirror the `products` column defaults (`'5 gallon'`, `15`), so the UI
  /// never shows anything the database wouldn't.
  static Map<String, dynamic> withDisplayDefaults(
    Map<String, dynamic> product,
  ) {
    return {
      ...product,
      'container_size': product['container_size']?.toString() ?? '5 gallon',
      'preparation_minutes':
          (product['preparation_minutes'] as num?)?.toInt() ?? 15,
    };
  }

  /// Loads the station's product, asking the server to create it from the
  /// station's water type when it doesn't exist yet.
  static Future<Map<String, dynamic>?> ensureStationProduct(
    SupabaseClient client,
    String ownerId,
  ) async {
    final existing = await fetchStationProduct(client, ownerId);
    if (existing != null) return existing;

    try {
      await client.rpc(
        'sync_owner_default_product',
        params: {'p_owner_id': ownerId},
      );
    } catch (e) {
      debugPrint('ensureStationProduct rpc error: $e');
    }
    return fetchStationProduct(client, ownerId);
  }

  /// Resolves the product row required to place an order.
  static Future<Map<String, dynamic>?> resolveOrderProduct(
    SupabaseClient client,
    String ownerId, {
    Map<String, dynamic>? selected,
    List<dynamic> products = const [],
  }) async {
    if (isRealProduct(selected)) return selected;
    final fromList = defaultFromList(products);
    if (isRealProduct(fromList)) return fromList;
    return ensureStationProduct(client, ownerId);
  }

  /// Loads the station's product from Supabase.
  static Future<Map<String, dynamic>?> fetchStationProduct(
    SupabaseClient client,
    String ownerId,
  ) async {
    try {
      final rows = await client
          .from(DbTables.waterOptions)
          .select(catalogSelectFields)
          .eq('owner_id', ownerId)
          .order('is_available', ascending: false)
          .order('created_at', ascending: true);
      final product = defaultFromList(rows);
      if (product != null) return withDisplayDefaults(product);
    } catch (e) {
      debugPrint('fetchStationProduct error: $e');
    }
    return null;
  }

  /// Placeholder shown while the station's product is loading or missing.
  /// It can't be ordered.
  static Map<String, dynamic> displayFallback({
    required String ownerId,
    required double price,
    String? waterType,
  }) {
    final type = WaterTypes.byName(waterType);
    return withDisplayDefaults({
      'name': type.name,
      'category': type.shortName,
      'description': type.description,
      'price': price,
      '_display_only': true,
      '_owner_id': ownerId,
    });
  }
}
