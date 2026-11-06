import 'dart:typed_data';

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
    this.imageUrl,
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

  /// Public URL in the product_images bucket, if the owner added a photo.
  final String? imageUrl;

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
    String? imageUrl,
  }) => Accessory(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    price: price ?? this.price,
    stock: stock ?? this.stock,
    isAvailable: isAvailable ?? this.isAvailable,
    description: description,
    imageUrl: imageUrl ?? this.imageUrl,
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
    imageUrl: (r['image_url']?.toString().trim().isEmpty ?? true)
        ? null
        : r['image_url'].toString(),
  );
}

abstract interface class AccessoryRepository {
  Future<List<Accessory>> list(String ownerId);
  Future<void> save(String ownerId, Accessory accessory);
  Future<void> delete(String id);

  /// Uploads a photo and returns its public URL.
  Future<String> uploadPhoto(String ownerId, List<int> bytes, String ext);
}

class SupabaseAccessoryRepository implements AccessoryRepository {
  SupabaseAccessoryRepository([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  static const _fields =
      'id, name, category, price, stock_level, is_available, description, image_url';

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
      'image_url': a.imageUrl,
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

  @override
  Future<String> uploadPhoto(
    String ownerId,
    List<int> bytes,
    String ext,
  ) async {
    final path =
        'accessories/$ownerId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bucket = _client.storage.from('product_images');
    await bucket.uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: FileOptions(contentType: 'image/$ext'),
    );
    return bucket.getPublicUrl(path);
  }
}

/// Small square photo of an accessory, or its category icon.
class AccessoryThumb extends StatelessWidget {
  const AccessoryThumb({super.key, required this.accessory, this.size = 40});
  final Accessory accessory;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox.square(
      dimension: size,
      child: Icon(
        Accessory.iconFor(accessory.category),
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    final url = accessory.imageUrl;
    if (url == null) return icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: accessory.name,
        errorBuilder: (context, error, stack) => icon,
      ),
    );
  }
}
