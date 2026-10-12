import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../db_tables.dart';
import '../utils/order_product_helpers.dart';

/// Bundle containing all station details needed for instant UI rendering.
class CachedStationBundle {
  final String ownerId;
  final List<dynamic> products;
  final Map<String, dynamic>? settingsData;
  final Map<String, dynamic>? profileData;
  final List<int> ratingCounts;
  final double? pricePerGallon;
  final double baseDeliveryFee;
  final String? waterType;
  final DateTime cachedAt;

  CachedStationBundle({
    required this.ownerId,
    required this.products,
    this.settingsData,
    this.profileData,
    required this.ratingCounts,
    this.pricePerGallon,
    required this.baseDeliveryFee,
    this.waterType,
    required this.cachedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > const Duration(minutes: 5);

  CachedStationBundle copyWith({
    List<dynamic>? products,
    Map<String, dynamic>? settingsData,
    Map<String, dynamic>? profileData,
    List<int>? ratingCounts,
    double? pricePerGallon,
    double? baseDeliveryFee,
    String? waterType,
  }) {
    return CachedStationBundle(
      ownerId: ownerId,
      products: products ?? this.products,
      settingsData: settingsData ?? this.settingsData,
      profileData: profileData ?? this.profileData,
      ratingCounts: ratingCounts ?? this.ratingCounts,
      pricePerGallon: pricePerGallon ?? this.pricePerGallon,
      baseDeliveryFee: baseDeliveryFee ?? this.baseDeliveryFee,
      waterType: waterType ?? this.waterType,
      cachedAt: DateTime.now(),
    );
  }
}

/// High-performance in-memory cache and real-time synchronizer for water refill
/// stations and their available products.
class StationDataCache {
  StationDataCache._internal();
  static final StationDataCache instance = StationDataCache._internal();

  final Map<String, CachedStationBundle> _cache = {};
  final Map<String, Future<CachedStationBundle>> _inFlight = {};
  final StreamController<String> _stationUpdatesController =
      StreamController<String>.broadcast();

  /// Stream of ownerIds that have been updated in real-time.
  Stream<String> get onStationUpdated => _stationUpdatesController.stream;

  /// Returns cached bundle synchronously if available.
  CachedStationBundle? get(String? ownerId) {
    if (ownerId == null || ownerId.isEmpty) return null;
    return _cache[ownerId];
  }

  /// Store or update cached bundle manually.
  void set(String ownerId, CachedStationBundle bundle) {
    _cache[ownerId] = bundle;
    _stationUpdatesController.add(ownerId);
  }

  /// Invalidate cache for a specific station.
  void invalidate(String ownerId) {
    _cache.remove(ownerId);
  }

  /// Clear entire cache.
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  /// Fetch or retrieve station bundle with deduplicated concurrent requests
  /// and parallelized queries.
  Future<CachedStationBundle> getOrFetch(
    String ownerId, {
    bool forceRefresh = false,
  }) async {
    final existing = _cache[ownerId];
    if (!forceRefresh && existing != null && !existing.isExpired) {
      return existing;
    }

    // Reuse in-flight request if one is currently pending
    final pending = _inFlight[ownerId];
    if (pending != null && !forceRefresh) {
      return pending;
    }

    final future = _fetchFromNetwork(ownerId);
    _inFlight[ownerId] = future;

    try {
      final bundle = await future;
      _cache[ownerId] = bundle;
      _stationUpdatesController.add(ownerId);
      return bundle;
    } finally {
      _inFlight.remove(ownerId);
    }
  }

  /// Runs all 4 station queries concurrently via Future.wait for maximum speed.
  Future<CachedStationBundle> _fetchFromNetwork(String ownerId) async {
    final supabase = Supabase.instance.client;

    final results = await Future.wait<dynamic>([
      // 0: Water products (refill options)
      supabase
          .from(DbTables.waterOptions)
          .select(OrderProductHelpers.coreSelectFields)
          .eq('owner_id', ownerId)
          .eq('is_available', true)
          .order('price', ascending: true),

      // 1: Owner settings (pricing & delivery)
      supabase
          .from('owner_settings')
          .select('base_delivery_fee, price_per_gallon')
          .eq('owner_id', ownerId)
          .maybeSingle(),

      // 2: Profile details
      supabase
          .from('profiles')
          .select(
            'primary_water_type, average_rating, review_count, station_name, '
            'complete_address, barangay, town, latitude, longitude, '
            'station_photo_url, is_open, station_availability, phone',
          )
          .eq('id', ownerId)
          .maybeSingle(),

      // 3: Rating breakdown
      supabase
          .from('reviews')
          .select('rating')
          .eq('station_id', ownerId),
    ]);

    final productData = (results[0] as List? ?? const []).cast<dynamic>();
    final settingsData = results[1] as Map<String, dynamic>?;
    final profileData = results[2] as Map<String, dynamic>?;
    final reviewRows = results[3] as List? ?? const [];

    final ratingCounts = List<int>.filled(5, 0);
    for (final review in reviewRows) {
      final rating = (review['rating'] as num?)?.toInt();
      if (rating != null && rating >= 1 && rating <= 5) {
        ratingCounts[rating - 1]++;
      }
    }

    final pricePerGallon =
        (settingsData?['price_per_gallon'] as num?)?.toDouble();
    final baseDeliveryFee =
        (settingsData?['base_delivery_fee'] as num?)?.toDouble() ?? 25.0;
    final waterType = profileData?['primary_water_type']?.toString();

    return CachedStationBundle(
      ownerId: ownerId,
      products: productData,
      settingsData: settingsData,
      profileData: profileData,
      ratingCounts: ratingCounts,
      pricePerGallon: pricePerGallon,
      baseDeliveryFee: baseDeliveryFee,
      waterType: waterType,
      cachedAt: DateTime.now(),
    );
  }

  /// Asynchronously prefetch water options for a list of stations.
  /// Runs in background without blocking UI so when a user navigates to any
  /// station screen, the available water refills appear instantaneously.
  void prefetch(List<String> ownerIds) {
    for (final id in ownerIds) {
      if (id.isEmpty) continue;
      final cached = _cache[id];
      if (cached == null || cached.isExpired) {
        getOrFetch(id).catchError((e) {
          debugPrint('Prefetch failed for $id: $e');
          return CachedStationBundle(
            ownerId: id,
            products: const [],
            ratingCounts: List.filled(5, 0),
            baseDeliveryFee: 25.0,
            cachedAt: DateTime.now(),
          );
        });
      }
    }
  }

  /// Apply real-time updates directly to cache when PostgresChanges events occur.
  void applyRealtimeEvent({
    required String table,
    required String ownerId,
    required Map<String, dynamic> record,
    required String eventType, // 'INSERT', 'UPDATE', 'DELETE'
  }) {
    final existing = _cache[ownerId];
    if (existing == null) {
      // Invalidate so next read re-fetches
      invalidate(ownerId);
      return;
    }

    if (table == DbTables.waterOptions) {
      final products = List<dynamic>.from(existing.products);
      final recordId = record['id']?.toString();

      if (eventType == 'DELETE') {
        products.removeWhere((p) => p['id']?.toString() == recordId);
      } else if (eventType == 'INSERT') {
        if (record['is_available'] == true) {
          products.removeWhere((p) => p['id']?.toString() == recordId);
          products.add(record);
          products.sort((a, b) => ((a['price'] as num?) ?? 0).compareTo((b['price'] as num?) ?? 0));
        }
      } else if (eventType == 'UPDATE') {
        products.removeWhere((p) => p['id']?.toString() == recordId);
        if (record['is_available'] == true) {
          products.add(record);
          products.sort((a, b) => ((a['price'] as num?) ?? 0).compareTo((b['price'] as num?) ?? 0));
        }
      }

      set(ownerId, existing.copyWith(products: products));
    } else if (table == 'owner_settings') {
      final ppg = (record['price_per_gallon'] as num?)?.toDouble() ?? existing.pricePerGallon;
      final fee = (record['base_delivery_fee'] as num?)?.toDouble() ?? existing.baseDeliveryFee;
      set(ownerId, existing.copyWith(pricePerGallon: ppg, baseDeliveryFee: fee, settingsData: record));
    } else if (table == 'profiles') {
      final mergedProfile = {...?existing.profileData, ...record};
      final wt = record['primary_water_type']?.toString() ?? existing.waterType;
      set(ownerId, existing.copyWith(profileData: mergedProfile, waterType: wt));
    } else {
      // For reviews or other tables, trigger background refresh
      getOrFetch(ownerId, forceRefresh: true).catchError((_) => existing);
    }
  }
}
