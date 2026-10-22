import 'package:erefill/core/sync/realtime_hub.dart';
import 'package:erefill/core/sync/sync_store.dart';
import 'package:erefill/core/water_types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_api_service.dart';

typedef AdminPage = AdminPagedResult<Map<String, dynamic>>;

/// Every query the admin console keeps synchronized offline, defined once.
///
/// Built on the shared sync layer in `package:erefill/core/sync`: each spec is
/// cache-first (saved data shows on the first frame, even after a restart),
/// refreshes in the background, refetches on realtime changes to the tables
/// it [SyncSpec.watches], and resyncs on resume and reconnect. Tables that are
/// not in the `supabase_realtime` publication (water_refill_stations,
/// system_config, audit_logs, fee wallets) fall back to [SyncSpec.pollInterval].
///
/// Screens share a resource whenever their keys match, so the dashboard and
/// the orders page never fetch the same page twice.
abstract final class AdminSync {
  static const _orders = TableWatch('orders');
  static const _profiles = TableWatch('profiles');
  static const _disputes = TableWatch('disputes');
  static const _reviews = TableWatch('reviews');
  static const _payments = TableWatch('payment_webhook_events');
  static const _releases = TableWatch('app_releases');

  /// For data realtime cannot see (unpublished tables, RPC aggregates).
  static const _poll = Duration(minutes: 2);

  /// Rider positions change constantly; refetch on a timer, not per ping.
  static const _ridersPoll = Duration(seconds: 15);

  /// Admin views watch whole tables, so coalesce bursts more than per-user
  /// screens do.
  static const _debounce = Duration(milliseconds: 800);

  // Tags for SyncStore.refreshTagged after a write.
  static const tagOrders = 'admin.orders';
  static const tagStations = 'admin.stations';
  static const tagUsers = 'admin.users';
  static const tagFees = 'admin.fees';
  static const tagConfig = 'admin.config';
  static const tagModeration = 'admin.moderation';
  static const tagPayments = 'admin.payments';
  static const tagReleases = 'admin.releases';
  static const tagCatalog = 'admin.catalog';

  /// Cache keys are scoped to the signed-in admin; sign-out wipes them all.
  static String _key(String name, [Map<String, Object?> params = const {}]) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'signed-out';
    final query = [
      for (final e in params.entries)
        if (e.value != null && e.value != '') '${e.key}=${e.value}',
    ].join('&');
    return 'admin:$uid:$name${query.isEmpty ? '' : '?$query'}';
  }

  // ─── Codecs ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> _map(Object? json) =>
      Map<String, dynamic>.from(json as Map);

  static List<Map<String, dynamic>> _rows(Object? json) => [
    for (final row in json as List) Map<String, dynamic>.from(row as Map),
  ];

  static Object? _encodePage(AdminPage page) => {
    'total': page.total,
    'rows': page.rows,
  };

  static AdminPage _page(Object? json) {
    final map = json as Map;
    return AdminPagedResult(
      total: (map['total'] as num?)?.toInt() ?? 0,
      rows: _rows(map['rows'] ?? const []),
    );
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  // ─── Dashboard & fees ─────────────────────────────────────────────────────

  /// Dashboard snapshot: platform stats plus the side panels. The stats call
  /// must succeed (so an outage keeps the saved snapshot); side panels degrade
  /// to empty, as they did before.
  static SyncSpec<Map<String, dynamic>> dashboard(AdminApiService api) =>
      SyncSpec(
        key: _key('dashboard'),
        fetch: () async {
          final stats = await api.dashboardStats();
          final side = await Future.wait<Object?>([
            api.listLiveRiders().catchError((_) => <Map<String, dynamic>>[]),
            api
                .listDisputes(status: 'open', limit: 1)
                .then<Object?>((p) => p.total)
                .catchError((_) => 0),
            api.listStations(limit: 20).catchError(
              (_) => const AdminPage(total: 0, rows: []),
            ),
            api.listOrders(limit: 6).catchError(
              (_) => const AdminPage(total: 0, rows: []),
            ),
          ]);
          final riders = side[0] as List<Map<String, dynamic>>;
          final stations = side[2] as AdminPage;
          return {
            'stats': stats,
            'online_riders': riders.where((r) => r['is_online'] == true).length,
            'open_disputes': side[1],
            'pending_stations': stations.rows.where((s) {
              final st = s['status']?.toString().toLowerCase();
              return st == 'pending' || st == 'pending_verification';
            }).toList(),
            'recent_orders': (side[3] as AdminPage).rows,
          };
        },
        decode: _map,
        watches: const [_orders, _profiles, _disputes],
        pollInterval: _poll,
        debounce: _debounce,
        tags: const {tagOrders, tagStations, tagUsers, tagConfig},
      );

  /// Service-fee analytics and the fee configuration forms.
  static SyncSpec<Map<String, dynamic>> platformFees(AdminApiService api) =>
      SyncSpec(
        key: _key('platform_fees'),
        fetch: () async {
          final results = await Future.wait<Object?>([
            api.revenueAnalytics(),
            api.dashboardStats(),
            api.getDeliveryFeeConfig(),
            api.getDeliveryFeeHistory(limit: 10),
          ]);
          return {
            'analytics': results[0],
            'stats': results[1],
            'delivery_config': results[2],
            'delivery_history': results[3],
          };
        },
        decode: _map,
        watches: const [_orders],
        pollInterval: _poll,
        debounce: _debounce,
        tags: const {tagFees, tagConfig},
      );

  static SyncSpec<List<FeeWalletRow>> feeWallets(
    Future<List<FeeWalletRow>> Function() fetch,
  ) => SyncSpec(
    key: _key('fee_wallets'),
    fetch: fetch,
    decode: (json) => [
      for (final row in json as List)
        FeeWalletRow.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    encode: (rows) => [for (final row in rows) row.toJson()],
    watches: const [_orders],
    pollInterval: _poll,
    debounce: _debounce,
    tags: const {tagFees},
  );

  static SyncSpec<List<Map<String, dynamic>>> systemConfig(
    AdminApiService api,
  ) => SyncSpec(
    key: _key('system_config'),
    fetch: api.listSystemConfig,
    decode: _rows,
    pollInterval: _poll,
    tags: const {tagConfig},
  );

  // ─── Stations ─────────────────────────────────────────────────────────────

  static SyncSpec<List<Map<String, dynamic>>> regions(AdminApiService api) =>
      SyncSpec(
        key: _key('regions'),
        fetch: api.listRegions,
        decode: _rows,
        tags: const {tagStations},
      );

  static SyncSpec<AdminPage> stations(
    AdminApiService api, {
    String? search,
    String? regionId,
  }) {
    final q = _blankToNull(search);
    return SyncSpec(
      key: _key('stations', {'region': regionId, 'q': q}),
      fetch: () => api.listStations(search: q, limit: 200, regionId: regionId),
      decode: _page,
      encode: _encodePage,
      watches: const [_profiles],
      pollInterval: _poll,
      debounce: _debounce,
      tags: const {tagStations},
      persist: q == null,
    );
  }

  /// Everything on a station's detail page. The detail call must succeed;
  /// the tabs degrade to empty, as they did before.
  static SyncSpec<Map<String, dynamic>> stationDetail(
    AdminApiService api,
    String ownerId,
  ) => SyncSpec(
    key: _key('station', {'id': ownerId}),
    fetch: () async {
      const emptyPage = AdminPage(total: 0, rows: []);
      final detail = await api.getStationDetail(ownerId);
      final results = await Future.wait<Object?>([
        api.listStationRiders(ownerId).catchError((_) => emptyPage),
        api.listStationCustomers(ownerId).catchError((_) => emptyPage),
        api
            .listStationProducts(ownerId)
            .catchError((_) => <Map<String, dynamic>>[]),
        api.listInventoryLedger(ownerId).catchError((_) => emptyPage),
        api
            .getActivityTimeline('station', ownerId)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      return {
        'detail': detail,
        'riders': _encodePage(results[0] as AdminPage),
        'customers': _encodePage(results[1] as AdminPage),
        'products': results[2],
        'ledger': _encodePage(results[3] as AdminPage),
        'timeline': results[4],
      };
    },
    decode: _map,
    watches: [
      TableWatch('profiles', column: 'id', value: ownerId),
      TableWatch('profiles', column: 'owner_id', value: ownerId),
      TableWatch('products', column: 'owner_id', value: ownerId),
      TableWatch('owner_inventory_ledger', column: 'owner_id', value: ownerId),
    ],
    pollInterval: _poll,
    tags: const {tagStations},
  );

  /// Decodes a page stored inside a composite snapshot.
  static AdminPage pageOf(Object? json) =>
      json == null ? const AdminPage(total: 0, rows: []) : _page(json);

  /// Decodes a row list stored inside a composite snapshot.
  static List<Map<String, dynamic>> rowsOf(Object? json) =>
      json == null ? const [] : _rows(json);

  // ─── Orders ───────────────────────────────────────────────────────────────

  static SyncSpec<AdminPage> orders(
    AdminApiService api, {
    required String status,
    String? search,
    int offset = 0,
    int limit = 50,
  }) {
    final q = _blankToNull(search);
    return SyncSpec(
      key: _key('orders', {
        'status': status,
        'q': q,
        'offset': offset,
        'limit': limit,
      }),
      fetch: () => api.listOrders(
        limit: limit,
        offset: offset,
        status: status,
        search: q,
      ),
      decode: _page,
      encode: _encodePage,
      watches: const [_orders],
      debounce: _debounce,
      tags: const {tagOrders},
      persist: q == null && offset == 0,
    );
  }

  static SyncSpec<Map<String, dynamic>> orderDetail(
    AdminApiService api,
    String orderId,
  ) => SyncSpec(
    key: _key('order', {'id': orderId}),
    fetch: () => api.getOrderDetail(orderId),
    decode: _map,
    watches: [
      TableWatch('orders', column: 'id', value: orderId),
      TableWatch('order_items', column: 'order_id', value: orderId),
    ],
    tags: const {tagOrders},
  );

  // ─── Users ────────────────────────────────────────────────────────────────

  static SyncSpec<AdminPage> users(
    AdminApiService api, {
    String? role,
    String? search,
    int offset = 0,
    int limit = 60,
  }) {
    final q = _blankToNull(search);
    return SyncSpec(
      key: _key('users', {
        'role': role,
        'q': q,
        'offset': offset,
        'limit': limit,
      }),
      fetch: () =>
          api.listUsers(role: role, search: q, limit: limit, offset: offset),
      decode: _page,
      encode: _encodePage,
      watches: const [_profiles],
      debounce: _debounce,
      tags: const {tagUsers},
      persist: q == null && offset == 0,
    );
  }

  static SyncSpec<List<Map<String, dynamic>>> admins(AdminApiService api) =>
      SyncSpec(
        key: _key('admins'),
        fetch: api.listAdmins,
        decode: _rows,
        watches: const [_profiles],
        debounce: _debounce,
        tags: const {tagUsers},
      );

  static SyncSpec<List<Map<String, dynamic>>> liveRiders(
    AdminApiService api, {
    String? regionId,
  }) => SyncSpec(
    key: _key('live_riders', {'region': regionId}),
    fetch: () => api.listLiveRiders(regionId: regionId),
    decode: _rows,
    pollInterval: _ridersPoll,
    tags: const {tagUsers},
  );

  // ─── Moderation, payments, audit ──────────────────────────────────────────

  static SyncSpec<Map<String, dynamic>> moderation(
    AdminApiService api, {
    String? disputeStatus,
  }) => SyncSpec(
    key: _key('moderation', {'status': disputeStatus}),
    fetch: () async {
      final results = await Future.wait([
        api.listDisputes(status: disputeStatus, limit: 100),
        api.listReviews(limit: 100, maxRating: 2),
      ]);
      return {
        'disputes': _encodePage(results[0]),
        'reviews': _encodePage(results[1]),
      };
    },
    decode: _map,
    watches: const [_disputes, _reviews],
    debounce: _debounce,
    tags: const {tagModeration},
  );

  static SyncSpec<AdminPage> paymentFailures(AdminApiService api) => SyncSpec(
    key: _key('payment_failures'),
    fetch: () => api.listPaymentFailures(limit: 100),
    decode: _page,
    encode: _encodePage,
    watches: const [_payments],
    debounce: _debounce,
    tags: const {tagPayments},
  );

  static SyncSpec<AdminPage> auditLogs(AdminApiService api) => SyncSpec(
    key: _key('audit_logs'),
    fetch: api.listAuditLogs,
    decode: _page,
    encode: _encodePage,
    pollInterval: const Duration(minutes: 1),
  );

  // ─── Catalog & releases ───────────────────────────────────────────────────

  /// Water types live in the shared [WaterTypes] registry (which caches
  /// itself); this resource refreshes it and carries per-type station counts.
  static SyncSpec<Map<String, int>> waterTypeStationCounts() => SyncSpec(
    key: _key('water_type_counts'),
    fetch: () async {
      final client = Supabase.instance.client;
      await WaterTypes.load(client: client, force: true);
      final rows = await client
          .from('profiles')
          .select('primary_water_type')
          .eq('role', 'owner');
      final counts = <String, int>{};
      for (final row in rows) {
        final name = row['primary_water_type']?.toString();
        if (name != null) counts[name] = (counts[name] ?? 0) + 1;
      }
      return counts;
    },
    decode: (json) => {
      for (final e in (json as Map).entries)
        e.key.toString(): (e.value as num).toInt(),
    },
    watches: const [_profiles],
    debounce: _debounce,
    tags: const {tagCatalog},
  );

  static SyncSpec<List<Map<String, dynamic>>> appReleases(
    AdminApiService api,
  ) => SyncSpec(
    key: _key('app_releases'),
    fetch: api.listAppReleases,
    decode: _rows,
    watches: const [_releases],
    tags: const {tagReleases},
  );
}
