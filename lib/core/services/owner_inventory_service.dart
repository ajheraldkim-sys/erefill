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

  Future<void> recordDeliveryCompletion({
    required String ownerId,
    required String orderId,
    required int gallons,
    String? waterType,
    String? productId,
    int emptyGallonsReturned = 0,
  }) async {
    if (gallons <= 0 && emptyGallonsReturned <= 0) return;

    try {
      // 1. If product ID is provided or can be found by waterType, deduct stock level
      String? resolvedProductId = productId;
      if (resolvedProductId == null && waterType != null && waterType.isNotEmpty) {
        final res = await _client
            .from(DbTables.waterOptions)
            .select('id, stock_level')
            .eq('owner_id', ownerId)
            .ilike('name', '%$waterType%')
            .limit(1)
            .maybeSingle();
        if (res != null) {
          resolvedProductId = res['id']?.toString();
          final currentStock = (res['stock_level'] as num?)?.toInt() ?? 0;
          final newStock = (currentStock - gallons).clamp(0, 999999);
          await _client
              .from(DbTables.waterOptions)
              .update({'stock_level': newStock})
              .eq('id', resolvedProductId!);
        }
      } else if (resolvedProductId != null) {
        final res = await _client
            .from(DbTables.waterOptions)
            .select('stock_level')
            .eq('id', resolvedProductId)
            .maybeSingle();
        if (res != null) {
          final currentStock = (res['stock_level'] as num?)?.toInt() ?? 0;
          final newStock = (currentStock - gallons).clamp(0, 999999);
          await _client
              .from(DbTables.waterOptions)
              .update({'stock_level': newStock})
              .eq('id', resolvedProductId);
        }
      }

      // 2. If empty gallons were returned, increment empty_gallons_stock
      if (emptyGallonsReturned > 0) {
        final sett = await _client
            .from('owner_settings')
            .select('empty_gallons_stock')
            .eq('owner_id', ownerId)
            .maybeSingle();
        final currentEmpty = (sett?['empty_gallons_stock'] as num?)?.toInt() ?? 0;
        await _client
            .from('owner_settings')
            .upsert({
              'owner_id': ownerId,
              'empty_gallons_stock': currentEmpty + emptyGallonsReturned,
              'updated_at': DateTime.now().toIso8601String(),
            }, onConflict: 'owner_id');
      }

      // 3. Log into owner_inventory_ledger
      final shortId = orderId.length >= 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
      await _client.from('owner_inventory_ledger').insert({
        'owner_id': ownerId,
        'tx_type': 'order_delivery',
        'gallons': gallons,
        'product_id': resolvedProductId,
        'notes': 'Online Order #$shortId fulfilled ($gallons gal delivered${emptyGallonsReturned > 0 ? ', $emptyGallonsReturned empty returned' : ''})',
      });
    } catch (e) {
      debugPrint('[OwnerInventoryService] Auto-deduction fallback notice: $e');
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
      case 'order_delivery':
        return 'Order delivery';
      default:
        return type ?? 'Update';
    }
  }
}
