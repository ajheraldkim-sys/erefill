import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db_tables.dart';
import '../utils/supabase_helpers.dart';
import '../water_types.dart';

/// Resolves which station product to use when placing an order.
abstract final class OrderProductHelpers {
  /// Columns guaranteed on all deployed `products` schemas.
  static const coreSelectFields = 'id, name, price, category, is_available';

  /// Owner catalog list — avoids optional refill metadata columns.
  static const catalogSelectFields =
      'id, name, description, price, category, is_available, created_at';

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
    return isValidProductId(product['id']);
  }

  /// Picks the default product from a loaded list — prioritizing customer preferred water type when provided.
  static Map<String, dynamic>? defaultFromList(
    List<dynamic> products, {
    String? stationWaterType,
    String? preferredWaterType,
  }) {
    if (products.isEmpty) return null;

    final real = products
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .where((p) => isValidProductId(p['id']))
        .toList();
    final pool = real.isNotEmpty
        ? real
        : products
              .whereType<Map>()
              .map((p) => Map<String, dynamic>.from(p))
              .toList();
    if (pool.isEmpty) return null;

    // 1. If preferredWaterType is provided, prioritize matching customer's preference
    if (preferredWaterType != null && preferredWaterType.trim().isNotEmpty) {
      final customerPreferred = WaterTypes.byName(preferredWaterType);
      for (final product in pool) {
        final type = WaterTypes.byName(
          product['category']?.toString() ?? product['name']?.toString(),
        );
        if (type.shortName.toLowerCase() == customerPreferred.shortName.toLowerCase()) {
          return product;
        }
      }
    }

    // 2. Otherwise match the station's primary water type
    final preferred = WaterTypes.byName(stationWaterType);
    for (final product in pool) {
      final type = WaterTypes.byName(
        product['category']?.toString() ?? product['name']?.toString(),
      );
      if (type.shortName.toLowerCase() == preferred.shortName.toLowerCase()) {
        return product;
      }
    }

    pool.sort((a, b) {
      final aPrice = (a['price'] as num?)?.toDouble() ?? double.infinity;
      final bPrice = (b['price'] as num?)?.toDouble() ?? double.infinity;
      return aPrice.compareTo(bPrice);
    });
    return pool.first;
  }

  /// Applies UI defaults for optional refill metadata columns.
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

  /// Ensures a single orderable product exists for the owner using station pricing settings.
  static Future<Map<String, dynamic>?> ensureDefaultProductForOwner(
    SupabaseClient client,
    String ownerId, {
    required double pricePerGallon,
    String? waterType,
  }) async {
    if (pricePerGallon <= 0) return null;

    final existing = await fetchDefaultForStation(client, ownerId);
    if (existing != null && isRealProduct(existing)) {
      return existing;
    }

    try {
      final response = await client.rpc(
        'sync_owner_default_product',
        params: {'p_owner_id': ownerId},
      );
      if (response is Map) {
        final product = Map<String, dynamic>.from(response);
        if (isRealProduct(product)) {
          return withDisplayDefaults(product);
        }
      }
    } catch (e) {
      debugPrint('ensureDefaultProductForOwner rpc error: $e');
    }

    return fetchDefaultForStation(client, ownerId);
  }

  /// Resolves the product row required to place an order.
  static Future<Map<String, dynamic>?> resolveOrderProduct(
    SupabaseClient client,
    String ownerId, {
    Map<String, dynamic>? selected,
    List<dynamic> products = const [],
    String? waterType,
    String? preferredWaterType,
    double? settingsPrice,
  }) async {
    if (isRealProduct(selected)) {
      return selected;
    }

    final fromList = defaultFromList(
      products,
      stationWaterType: waterType,
      preferredWaterType: preferredWaterType,
    );
    if (isRealProduct(fromList)) {
      return fromList;
    }

    final price = settingsPrice ?? 0;
    if (price > 0) {
      return ensureDefaultProductForOwner(
        client,
        ownerId,
        pricePerGallon: price,
        waterType: waterType,
      );
    }

    return fetchDefaultForStation(client, ownerId);
  }

  /// Loads the first orderable product for a station from Supabase.
  static Future<Map<String, dynamic>?> fetchDefaultForStation(
    SupabaseClient client,
    String ownerId,
  ) async {
    try {
      final available = await client
          .from(DbTables.waterOptions)
          .select(coreSelectFields)
          .eq('owner_id', ownerId)
          .eq('is_available', true)
          .order('price', ascending: true)
          .limit(1);
      if (available.isNotEmpty) {
        return withDisplayDefaults(Map<String, dynamic>.from(available.first));
      }

      final any = await client
          .from(DbTables.waterOptions)
          .select(coreSelectFields)
          .eq('owner_id', ownerId)
          .order('price', ascending: true)
          .limit(1);
      if (any.isNotEmpty) {
        return withDisplayDefaults(Map<String, dynamic>.from(any.first));
      }
    } catch (e) {
      debugPrint('fetchDefaultForStation error: $e');
    }
    return null;
  }

  static Map<String, dynamic> displayFallback({
    required String ownerId,
    required double price,
    String? waterType,
  }) {
    final type = WaterTypes.byName(waterType);
    return withDisplayDefaults({
      'name': type.name,
      'category': type.shortName,
      'price': price,
      '_display_only': true,
      '_owner_id': ownerId,
    });
  }

  static const _optionalProductFields = [
    'container_size',
    'preparation_minutes',
  ];

  static bool _isCategoryCheckError(Object e) {
    final lower = e.toString().toLowerCase();
    return lower.contains('products_category_check') ||
        (lower.contains('check constraint') && lower.contains('category'));
  }

  /// Inserts a product row, omitting optional columns or falling back to legacy category constraints.
  static Future<void> insertProduct(
    SupabaseClient client,
    Map<String, dynamic> payload,
  ) async {
    var data = Map<String, dynamic>.from(payload);
    final categoryFallbacks = ['Refill', 'Products', null];
    var fallbackIndex = 0;

    while (true) {
      try {
        await client.from(DbTables.waterOptions).insert(data);
        return;
      } catch (e) {
        if (_isCategoryCheckError(e) &&
            fallbackIndex < categoryFallbacks.length) {
          final nextCategory = categoryFallbacks[fallbackIndex++];
          if (nextCategory != null) {
            data['category'] = nextCategory;
          } else {
            data.remove('category');
          }
          continue;
        }

        final missing = _optionalProductFields
            .where(
              (field) =>
                  data.containsKey(field) &&
                  SupabaseHelpers.isMissingColumnError(e, field),
            )
            .toList();
        if (missing.isEmpty) rethrow;
        for (final field in missing) {
          data.remove(field);
        }
      }
    }
  }

  /// Updates a product row, omitting optional columns or falling back to legacy category constraints.
  static Future<void> updateProduct(
    SupabaseClient client,
    String productId,
    Map<String, dynamic> payload,
  ) async {
    var data = Map<String, dynamic>.from(payload);
    final categoryFallbacks = ['Refill', 'Products', null];
    var fallbackIndex = 0;

    while (true) {
      try {
        await client
            .from(DbTables.waterOptions)
            .update(data)
            .eq('id', productId);
        return;
      } catch (e) {
        if (_isCategoryCheckError(e) &&
            fallbackIndex < categoryFallbacks.length) {
          final nextCategory = categoryFallbacks[fallbackIndex++];
          if (nextCategory != null) {
            data['category'] = nextCategory;
          } else {
            data.remove('category');
          }
          continue;
        }

        final missing = _optionalProductFields
            .where(
              (field) =>
                  data.containsKey(field) &&
                  SupabaseHelpers.isMissingColumnError(e, field),
            )
            .toList();
        if (missing.isEmpty) rethrow;
        for (final field in missing) {
          data.remove(field);
        }
      }
    }
  }
}
