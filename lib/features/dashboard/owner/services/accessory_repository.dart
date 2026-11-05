import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/db_tables.dart';

/// A water-refilling accessory a station sells next to its water.
class Accessory {
  const Accessory({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    required this.isAvailable,
    this.description,
  });

  /// Empty for an accessory that has not been saved yet.
  final String id;
  final String name;

  /// One of [categories].
  final String category;
  final double price;
  final int stock;
  final bool isAvailable;
  final String? description;

  static const categories = <String, String>{
    'gallon': 'Empty gallon',
    'cap': 'Cap',
    'seal': 'Seal',
    'dispenser': 'Dispenser',
    'other': 'Other',
  };

  static IconData iconFor(String category) => switch (category) {
        'gallon' => Icons.water_drop_outlined,
        'cap' => Icons.radio_button_checked_rounded,
        'seal' => Icons.verified_outlined,
        'dispenser' => Icons.kitchen_outlined,
        _ => Icons.inventory_2_outlined,
      };

  bool get inStock => stock > 0;

  Accessory copyWith({
    String? id,
    String? name,
    String? category,
    double? price,
    int? stock,
    bool? isAvailable,
  }) =>
      Accessory(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        price: price ?? this.price,
        stock: stock ?? this.stock,
        isAvailable: isAvailable ?? this.isAvailable,
        description: description,
      );

  factory Accessory.fromRow(Map<String, dynamic> r) => Accessory(
        id: r['id'].toString(),
        name: (r['name'] ?? '').toString(),
        category: categories.containsKey(r['category'])
            ? r['category'].toString()
            : 'other',
        price: (r['price'] as num?)?.toDouble() ?? 0,
        stock: (r['stock_level'] as num?)?.toInt() ?? 0,
        isAvailable: r['is_available'] != false,
        description: r['description']?.toString(),
      );
}

abstract interface class AccessoryRepository {
  Future<List<Accessory>> list(String ownerId);
  Future<void> save(String ownerId, Accessory accessory);
  Future<void> delete(String id);
}

class SupabaseAccessoryRepository implements AccessoryRepository {
  SupabaseAccessoryRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  static const _fields =
      'id, name, category, price, stock_level, is_available, description';

  @override
  Future<List<Accessory>> list(String ownerId) async {
    final rows = await _client
        .from(DbTables.waterOptions)
        .select(_fields)
        .eq('owner_id', ownerId)
        .eq('kind', 'accessory')
        .order('name');
    return [for (final r in rows) Accessory.fromRow(r)];
  }

  @override
  Future<void> save(String ownerId, Accessory a) async {
    final data = {
      'owner_id': ownerId,
      'kind': 'accessory',
      'name': a.name,
      'category': a.category,
      'price': a.price,
      'stock_level': a.stock,
      'is_available': a.isAvailable,
      'description': a.description,
    };
    if (a.id.isEmpty) {
      await _client.from(DbTables.waterOptions).insert(data);
    } else {
      await _client.from(DbTables.waterOptions).update(data).eq('id', a.id);
    }
  }

  @override
  Future<void> delete(String id) =>
      _client.from(DbTables.waterOptions).delete().eq('id', id);
}
