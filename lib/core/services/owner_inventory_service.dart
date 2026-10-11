import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/db_tables.dart';
import 'package:erefill/core/utils/supabase_helpers.dart';

class OwnerInventorySnapshot {
  const OwnerInventorySnapshot({
    required this.filledGallons,
    required this.emptyGallons,
    required this.products,
    required this.lowStockProducts,
  });

  final int filledGallons;
  final int emptyGallons;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> lowStockProducts;

  bool get hasLowFilledStock => lowStockProducts.isNotEmpty;
}

class OwnerInventoryService {
  OwnerInventoryService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<OwnerInventorySnapshot> fetchSnapshot(String ownerId) async {
    final products = List<Map<String, dynamic>>.from(
      await _client
          .from(DbTables.waterOptions)
          .select('id, name, category, stock_level, low_stock_threshold, is_available')
          .eq('owner_id', ownerId)
          .eq('is_available', true)
          .order('category'),
    );

    final settings = await _client
        .from('owner_settings')
        .select('empty_gallons_stock')
        .eq('owner_id', ownerId)
        .maybeSingle()
        .catchError((e) {
          if (SupabaseHelpers.isMissingColumnError(e, 'empty_gallons_stock')) {
            return null;
          }
          throw e;
        });

    var emptyGallons = 0;
    try {
      emptyGallons = (settings?['empty_gallons_stock'] as num?)?.toInt() ?? 0;
    } catch (_) {
      emptyGallons = 0;
    }

    var filled = 0;
    final lowStock = <Map<String, dynamic>>[];
    for (final product in products) {
      final stock = (product['stock_level'] as num?)?.toInt() ?? 0;
      final threshold = (product['low_stock_threshold'] as num?)?.toInt() ?? 10;
      filled += stock;
      if (stock <= threshold) {
        lowStock.add(product);
      }
    }

    return OwnerInventorySnapshot(
      filledGallons: filled,
      emptyGallons: emptyGallons,
      products: products,
      lowStockProducts: lowStock,
    );
  }

  Stream<List<Map<String, dynamic>>> ledgerStream(String ownerId) {
    return _client
        .from('owner_inventory_ledger')
        .stream(primaryKey: ['id'])
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false)
        .handleError((error, stackTrace) {
          debugPrint('Owner inventory stream error: $error');
          debugPrint('Owner inventory stream stack: $stackTrace');
          return <Map<String, dynamic>>[];
        })
        .map((rows) => rows.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<String?> logTransaction({
    required String txType,
    required int gallons,
    String? notes,
    String? productId,
  }) async {
    try {
      final response = await _client.rpc(
        'log_owner_inventory_tx',
        params: {
          'p_tx_type': txType,
          'p_gallons': gallons,
          'p_notes': notes,
          'p_product_id': productId,
        },
      );
      final result = Map<String, dynamic>.from(response as Map);
      if (result['success'] != true) {
        return result['message']?.toString() ?? 'Inventory update failed.';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static String labelForTxType(String? type) {
    switch (type) {
      case 'load_filled':
        return 'Filled load';
      case 'adjust_filled':
        return 'Filled adjustment';
      case 'load_empty':
        return 'Empty load';
      case 'adjust_empty':
        return 'Empty adjustment';
      case 'empty_return':
        return 'Empty return';
      default:
        return type ?? 'Update';
    }
  }
}
