import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../db_tables.dart';
import '../services/owner_inventory_service.dart';
import 'realtime_hub.dart';
import 'sync_store.dart';

/// Every offline-synchronized query in the app, by role.
///
/// Screens acquire these through `SyncedState.useSynced` instead of querying
/// Supabase themselves, so a query, its cache entry and its realtime channel
/// exist once no matter how many screens show the data.
abstract final class SyncResources {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Tag on every resource derived from `orders`; see
  /// [SyncStore.refreshTagged].
  static const ordersTag = 'orders';
  static const inventoryTag = 'inventory';
  static const ridersTag = 'riders';

  static const activeOwnerStatuses = [
    'pending',
    'accepted',
    'preparing',
    'ready_for_pickup',
    'assigned_to_rider',
    'out_for_delivery',
  ];

  static const activeRiderStatuses = [
    'assigned_to_rider',
    'out_for_delivery',
    'ready_for_pickup',
    'preparing',
    'accepted',
  ];

  // ─── Customer ─────────────────────────────────────────────────────────────

  /// The customer's orders (newest first) and the ratings they left.
  ///
  /// Server data only; orders still queued on the device are overlaid by the
  /// screen, because they must show even when this resource cannot refresh.
  static SyncSpec<CustomerOrdersData> customerOrders(String customerId) =>
      SyncSpec(
        key: 'customer_orders:$customerId',
        tags: const {ordersTag},
        watches: [
          TableWatch('orders', column: 'customer_id', value: customerId),
          TableWatch('reviews', column: 'customer_id', value: customerId),
        ],
        pollInterval: const Duration(seconds: 60),
        decode: CustomerOrdersData.fromJson,
        encode: (v) => v.toJson(),
        fetch: () async {
          final rows = await _db
              .from('orders')
              .select('*, profiles:owner_id(station_name), order_items(*)')
              .eq('customer_id', customerId)
              .order('created_at', ascending: false);
          final ratings = <String, int>{};
          try {
            final reviewRows = await _db
                .from('reviews')
                .select('order_id, rating')
                .eq('customer_id', customerId);
            for (final r in reviewRows) {
              final orderId = r['order_id'];
              if (orderId != null) {
                // 0 = reviewed without a star value; never assume 5 stars.
                ratings[orderId.toString()] =
                    (r['rating'] as num?)?.toInt() ?? 0;
              }
            }
          } catch (e) {
            debugPrint('Error loading customer reviews: $e');
          }
          return CustomerOrdersData(
            orders: List<Map<String, dynamic>>.from(rows),
            reviewRatings: ratings,
          );
        },
      );

  // ─── Owner ────────────────────────────────────────────────────────────────

  /// All of the station's orders (for dashboard stats and trends) plus the
  /// five newest with customer names.
  static SyncSpec<OwnerOverviewData> ownerOverview(String ownerId) => SyncSpec(
    key: 'owner_overview:$ownerId',
    tags: const {ordersTag},
    watches: [TableWatch('orders', column: 'owner_id', value: ownerId)],
    pollInterval: const Duration(seconds: 60),
    decode: OwnerOverviewData.fromJson,
    encode: (v) => v.toJson(),
    fetch: () async {
      final results = await Future.wait([
        _db.from('orders').select('*').eq('owner_id', ownerId),
        _ownerRecentOrders(ownerId),
      ]);
      return OwnerOverviewData(
        orders: List<Map<String, dynamic>>.from(results[0]),
        recent: List<Map<String, dynamic>>.from(results[1]),
      );
    },
  );

  static Future<List<Map<String, dynamic>>> _ownerRecentOrders(
    String ownerId,
  ) async {
    try {
      return List<Map<String, dynamic>>.from(
        await _db
            .from('orders')
            .select('*, profiles!orders_customer_id_fkey(full_name, avatar_url)')
            .eq('owner_id', ownerId)
            .order('created_at', ascending: false)
            .limit(5),
      );
    } catch (e) {
      debugPrint('Failed to fetch enriched recent orders, trying fallback: $e');
      return List<Map<String, dynamic>>.from(
        await _db
            .from('orders')
            .select('*')
            .eq('owner_id', ownerId)
            .order('created_at', ascending: false)
            .limit(5),
      );
    }
  }

  /// The station's open orders with customer contact details, for the order
  /// queue and kanban board.
  static SyncSpec<List<Map<String, dynamic>>> ownerActiveOrders(
    String ownerId,
  ) => SyncSpec(
    key: 'owner_active_orders:$ownerId',
    tags: const {ordersTag},
    watches: [TableWatch('orders', column: 'owner_id', value: ownerId)],
    pollInterval: const Duration(seconds: 30),
    decode: _rowList,
    fetch: () => _fetchOwnerActiveOrders(ownerId),
  );

  static Future<List<Map<String, dynamic>>> _fetchOwnerActiveOrders(
    String ownerId,
  ) async {
    List<Map<String, dynamic>> withCustomer(List<Map<String, dynamic>> raw) {
      return raw.map((o) {
        final cust = o['customer'] as Map<String, dynamic>?;
        return {
          ...o,
          'customer_name':
              o['customer_name'] ?? cust?['full_name'] ?? 'Guest Customer',
          'customer_address':
              o['customer_address'] ??
              cust?['complete_address'] ??
              'Station Pickup',
          'customer_phone': o['customer_phone'] ?? cust?['phone'] ?? 'No phone',
          'customer_barangay':
              o['customer_barangay'] ?? cust?['barangay'] ?? '',
          'customer_landmark':
              o['customer_landmark'] ?? cust?['landmark'] ?? '',
        };
      }).toList();
    }

    // 1. Primary Attempt: Query with joined customer profiles
    try {
      final response = await _db
          .from('orders')
          .select('''
            *,
            customer:profiles!orders_customer_id_fkey(full_name, complete_address, phone, barangay, landmark)
          ''')
          .eq('owner_id', ownerId)
          .inFilter('status', activeOwnerStatuses)
          .order('created_at', ascending: false);
      return withCustomer(List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint(
        'Primary joined order fetch failed, attempting resilient fallbacks: $e',
      );
    }

    // 2. Fallback Attempt A: Simple direct select on orders without foreign key join
    try {
      final response = await _db
          .from('orders')
          .select('*')
          .eq('owner_id', ownerId)
          .inFilter('status', activeOwnerStatuses)
          .order('created_at', ascending: false);
      return withCustomer(List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint('Direct inFilter order fetch failed: $e');
    }

    // 3. Fallback Attempt B: In case inFilter enum fails (e.g. 22P02 or schema mismatch)
    final response = await _db
        .from('orders')
        .select('*')
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false)
        .limit(50);
    final active = List<Map<String, dynamic>>.from(response).where((o) {
      final s = (o['status'] ?? '').toString().toLowerCase();
      return s != 'delivered' && s != 'cancelled' && s != 'declined';
    }).toList();
    return withCustomer(active);
  }

  /// Riders linked to the station, most reliable first.
  static SyncSpec<List<Map<String, dynamic>>> ownerRiders(String ownerId) =>
      SyncSpec(
        key: 'owner_riders:$ownerId',
        tags: const {ridersTag},
        watches: [TableWatch('profiles', column: 'owner_id', value: ownerId)],
        decode: _rowList,
        fetch: () async => List<Map<String, dynamic>>.from(
          await _db
              .from('profiles')
              .select('id, full_name, username, reliability_score, flagged_count')
              .eq('owner_id', ownerId)
              .eq('role', 'rider')
              .order('reliability_score', ascending: false),
        ),
      );

  /// Filled and empty gallon stock with low-stock products.
  static SyncSpec<OwnerInventorySnapshot> ownerInventory(String ownerId) =>
      SyncSpec(
        key: 'owner_inventory:$ownerId',
        tags: const {inventoryTag},
        watches: [
          TableWatch(DbTables.waterOptions, column: 'owner_id', value: ownerId),
          TableWatch('owner_settings', column: 'owner_id', value: ownerId),
        ],
        pollInterval: const Duration(minutes: 2),
        decode: (json) => OwnerInventorySnapshot.fromJson(
          Map<String, dynamic>.from(json as Map),
        ),
        encode: (v) => v.toJson(),
        fetch: () => OwnerInventoryService().fetchSnapshot(ownerId),
      );

  // ─── Rider ────────────────────────────────────────────────────────────────

  /// The rider's profile, open deliveries and lifetime delivered stats.
  static SyncSpec<RiderDashboardData> riderDashboard(String riderId) =>
      SyncSpec(
        key: 'rider_dashboard:$riderId',
        tags: const {ordersTag},
        watches: [
          TableWatch('orders', column: 'assigned_rider_id', value: riderId),
          TableWatch('profiles', column: 'id', value: riderId),
        ],
        pollInterval: const Duration(seconds: 30),
        decode: RiderDashboardData.fromJson,
        encode: (v) => v.toJson(),
        fetch: () async {
          final results = await Future.wait([
            _db
                .from('profiles')
                .select(
                  'full_name, first_name, last_name, mi, suffix, username, phone, town, barangay, vehicle_type, license_number, avatar_url, created_at, is_online',
                )
                .eq('id', riderId)
                .maybeSingle(),
            _db
                .from('orders')
                .select('''
                  id, status, created_at, customer_id, total_amount, items, subtotal, delivery_fee, station_name, payment_method, payment_status,
                  customer:profiles!orders_customer_id_fkey(full_name, complete_address, phone, barangay, latitude, longitude)
                ''')
                .eq('assigned_rider_id', riderId)
                .inFilter('status', activeRiderStatuses)
                .order('created_at', ascending: false),
            _db
                .from('orders')
                .select('id, delivery_fee')
                .eq('assigned_rider_id', riderId)
                .eq('status', 'delivered'),
          ]);
          final delivered = results[2] as List? ?? const [];
          return RiderDashboardData(
            profile: results[0] == null
                ? null
                : Map<String, dynamic>.from(results[0] as Map),
            activeOrders: List<Map<String, dynamic>>.from(
              results[1] as List? ?? const [],
            ),
            completedDeliveries: delivered.length,
            totalEarnings: delivered.fold<double>(0, (sum, o) {
              final fee = o is Map ? o['delivery_fee'] : null;
              return sum +
                  (fee is num
                      ? fee.toDouble()
                      : double.tryParse(fee?.toString() ?? '') ?? 0);
            }),
          );
        },
      );

  static List<Map<String, dynamic>> _rowList(Object? json) => [
    for (final row in json as List) Map<String, dynamic>.from(row as Map),
  ];
}

class CustomerOrdersData {
  const CustomerOrdersData({required this.orders, required this.reviewRatings});

  final List<Map<String, dynamic>> orders;

  /// Order id → star rating the customer left (0 = reviewed without stars).
  final Map<String, int> reviewRatings;

  factory CustomerOrdersData.fromJson(Object? json) {
    final map = Map<String, dynamic>.from(json as Map);
    return CustomerOrdersData(
      orders: SyncResources._rowList(map['orders'] ?? const []),
      reviewRatings: {
        for (final e in Map<String, dynamic>.from(
          map['review_ratings'] as Map? ?? const {},
        ).entries)
          e.key: (e.value as num?)?.toInt() ?? 0,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'orders': orders,
    'review_ratings': reviewRatings,
  };
}

class OwnerOverviewData {
  const OwnerOverviewData({required this.orders, required this.recent});

  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> recent;

  factory OwnerOverviewData.fromJson(Object? json) {
    final map = Map<String, dynamic>.from(json as Map);
    return OwnerOverviewData(
      orders: SyncResources._rowList(map['orders'] ?? const []),
      recent: SyncResources._rowList(map['recent'] ?? const []),
    );
  }

  Map<String, dynamic> toJson() => {'orders': orders, 'recent': recent};
}

class RiderDashboardData {
  const RiderDashboardData({
    required this.profile,
    required this.activeOrders,
    required this.completedDeliveries,
    required this.totalEarnings,
  });

  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> activeOrders;
  final int completedDeliveries;
  final double totalEarnings;

  factory RiderDashboardData.fromJson(Object? json) {
    final map = Map<String, dynamic>.from(json as Map);
    final profile = map['profile'];
    return RiderDashboardData(
      profile: profile == null ? null : Map<String, dynamic>.from(profile as Map),
      activeOrders: SyncResources._rowList(map['active_orders'] ?? const []),
      completedDeliveries: (map['completed'] as num?)?.toInt() ?? 0,
      totalEarnings: (map['earnings'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'profile': profile,
    'active_orders': activeOrders,
    'completed': completedDeliveries,
    'earnings': totalEarnings,
  };
}
