import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import '../../../core/water_types.dart';
import '../../../features/account/saved_addresses_screen.dart';
import 'package:erefill/core/models/cart_model.dart';
import '../../../core/utils/order_product_helpers.dart';
import '../../../core/utils/station_query_helpers.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/brand/hero_header.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../../../core/widgets/experience_widgets.dart';
import '../../../core/widgets/refill_components.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/auth_dialogs.dart';
import '../../../core/widgets/notification_preview_sheet.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/services/station_data_cache.dart';
import '../../../core/services/local_data_cache.dart';
import '../../../core/utils/station_price_helpers.dart';
import '../../../core/widgets/app_cached_image.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/live_order_progress_tracker.dart';
import '../../../core/widgets/offline_sync_status_pill.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/money.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
class CustomerHomeTab extends StatefulWidget {
  final VoidCallback? onOpenStations;

  const CustomerHomeTab({super.key, this.onOpenStations});

  @override
  State<CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends State<CustomerHomeTab>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final supabase = Supabase.instance.client;
  final PageController _homeBannerController = PageController();

  String _userFirstName = 'there';
  String _userMunicipality = '';
  int _stationCount = 0;
  List<Map<String, dynamic>> _stations = [];
  List<Map<String, dynamic>> _favoriteStations = [];
  final Set<String> _favoriteChangesInProgress = {};
  Map<String, dynamic>? _activeOrder;
  Map<String, dynamic>? _quickOrderStation;
  Map<String, dynamic>? _lastCompletedOrder;
  bool _isProcessingQuickOrder = false;
  bool _quickStationIsLastOrder = false;
  bool _isLoading = true;
  int _homeBannerIndex = 0;
  int _homeCacheGeneration = 0;
  int _homeFetchGeneration = 0;
  Timer? _homeBannerTimer;
  Timer? _activeOrderPollTimer;
  String _selectedCategory = 'All';

  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _favoritesChannel;
  RealtimeChannel? _stationsChannel;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Instant synchronous 0ms memory hydration before first build frame
    final user = supabase.auth.currentUser;
    final cached = user != null
        ? LocalDataCache.instance.getMemory<Map<String, dynamic>>('customer_home_${user.id}')
        : null;
    // Older builds wrote a signed-in customer's full snapshot under this
    // shared key. Do not expose address- or order-derived state after logout.
    unawaited(LocalDataCache.instance.invalidate('customer_home_guest'));
    if (cached != null) {
      _userFirstName = cached['userFirstName']?.toString() ?? _userFirstName;
      _userMunicipality = cached['userMunicipality']?.toString() ?? _userMunicipality;
      _stations = List<Map<String, dynamic>>.from(cached['stations'] as List? ?? const []);
      _favoriteStations = List<Map<String, dynamic>>.from(cached['favoriteStations'] as List? ?? const []);
      _stationCount = _stations.length;
      _quickOrderStation = cached['quickOrderStation'] as Map<String, dynamic>?;
      _quickStationIsLastOrder = cached['quickStationIsLastOrder'] == true;
      _lastCompletedOrder = cached['lastCompletedOrder'] as Map<String, dynamic>?;
      _activeOrder = cached['activeOrder'] as Map<String, dynamic>?;
      if (_stations.isNotEmpty) {
        _isLoading = false; // Zero waiting time on customer home!
      }
    }

    _loadCachedHome();
    _startHomeBannerTimer();
    _startActiveOrderPollTimer();
    _fetchData();
    _subscribeToOrders();
    _subscribeToFavorites();
    _subscribeToStations();
  }

  String? _lastObservedTown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<UserProvider>().user;
    final currentTown = _municipalityName(user?.town);
    if (_lastObservedTown == null) {
      _lastObservedTown = currentTown;
    } else if (currentTown != null &&
        currentTown.isNotEmpty &&
        currentTown.toLowerCase() != _lastObservedTown?.toLowerCase()) {
      _lastObservedTown = currentTown;
      _userMunicipality = currentTown;
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        _homeCacheGeneration++;
        unawaited(LocalDataCache.instance.invalidatePattern('customer_home_'));
      }
      setState(() {
        _stations = [];
        _favoriteStations = [];
        _stationCount = 0;
        _quickOrderStation = null;
        _quickStationIsLastOrder = false;
        _isLoading = true;
      });
      _fetchData();
    }
  }

  void _startActiveOrderPollTimer() {
    _activeOrderPollTimer?.cancel();
    _activeOrderPollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && _activeOrder != null) {
        _fetchData();
      }
    });
  }

  Future<void> _loadCachedHome() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final cacheGeneration = _homeCacheGeneration;
    final cached = await LocalDataCache.instance.get<Map<String, dynamic>>('customer_home_${user.id}');
    if (cached != null &&
        mounted &&
        cacheGeneration == _homeCacheGeneration &&
        supabase.auth.currentUser?.id == user.id) {
      setState(() {
        _userFirstName = cached['userFirstName']?.toString() ?? _userFirstName;
        _userMunicipality = cached['userMunicipality']?.toString() ?? _userMunicipality;
        _stations = List<Map<String, dynamic>>.from(cached['stations'] as List? ?? const []);
        _favoriteStations = List<Map<String, dynamic>>.from(cached['favoriteStations'] as List? ?? const []);
        _stationCount = _stations.length;
        _quickOrderStation = cached['quickOrderStation'] as Map<String, dynamic>?;
        _quickStationIsLastOrder = cached['quickStationIsLastOrder'] == true;
        _lastCompletedOrder = cached['lastCompletedOrder'] as Map<String, dynamic>?;
        _activeOrder = cached['activeOrder'] as Map<String, dynamic>?;
        _isLoading = false; // Instantly hide skeleton loaders!
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHomeBannerTimer();
      _startActiveOrderPollTimer();
      _fetchData();
    } else {
      _homeBannerTimer?.cancel();
      _homeBannerTimer = null;
      _activeOrderPollTimer?.cancel();
      _activeOrderPollTimer = null;
    }
  }

  void _startHomeBannerTimer() {
    _homeBannerTimer?.cancel();
    // 6 s gives time to read; no auto-rotation when the OS asks for reduced
    // motion (WCAG 2.2.2). Swipe and the page dots still work.
    _homeBannerTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_homeBannerController.hasClients || !mounted) return;
      if (AppUi.reduceMotion(context)) return;
      _homeBannerController.animateToPage(
        (_homeBannerIndex + 1) % 3,
        duration: AppUi.motionSlow,
        curve: AppUi.motionCurve,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homeBannerTimer?.cancel();
    _activeOrderPollTimer?.cancel();
    _homeBannerController.dispose();
    if (_ordersChannel != null) supabase.removeChannel(_ordersChannel!);
    if (_favoritesChannel != null) supabase.removeChannel(_favoritesChannel!);
    if (_stationsChannel != null) supabase.removeChannel(_stationsChannel!);
    super.dispose();
  }

  /// Older records may contain the previous service-area label. It is not a
  /// municipality and must never override the town selected at registration.
  String? _municipalityName(dynamic value) {
    final town = value?.toString().trim();
    if (town == null ||
        town.isEmpty ||
        town.toLowerCase() == 'cantilan & madrid') {
      return null;
    }
    return town;
  }

  Future<dynamic> _safeHomeQuery(Future<dynamic> request, String label) async {
    try {
      return await request;
    } catch (error) {
      // A nonessential home query (for example, prices or favorites) should
      // not hide nearby stations that are otherwise available to the customer.
      debugPrint('Home $label query failed: $error');
      return label == 'profile' ? null : const <dynamic>[];
    }
  }

  Future<void> _fetchData() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final userId = user.id;
    final requestId = ++_homeFetchGeneration;

    try {
      final initialUser = mounted ? context.read<UserProvider>().user : null;
      final cachedFirstName =
          initialUser?.firstName ?? initialUser?.fullName?.split(' ').first;
      final cachedTown = _municipalityName(initialUser?.town);

      // Parallelize primary queries
      final batchResults = await Future.wait<dynamic>([
        _safeHomeQuery(
          supabase
              .from('profiles')
              .select('full_name, first_name, town, barangay')
              .eq('id', user.id)
              .maybeSingle(),
          'profile',
        ),
        _safeHomeQuery(
          supabase.from('owner_settings').select('owner_id, price_per_gallon'),
          'station pricing',
        ),
        _safeHomeQuery(
          supabase
              .from('profiles')
              .select(StationQueryHelpers.ownerStationFields)
              .eq('role', 'owner'),
          'stations',
        ),
        _safeHomeQuery(
          supabase
              .from('orders')
              .select('*, profiles:owner_id(station_name)')
              .eq('customer_id', user.id)
              .not('status', 'in', '(delivered,cancelled)')
              .order('created_at', ascending: false)
              .limit(1),
          'active orders',
        ),
        _safeHomeQuery(
          supabase
              .from('favorites')
              .select('station_id')
              .eq('user_id', user.id),
          'favorites',
        ),
        // 5: last completed order for Quick Reorder
        _safeHomeQuery(
          supabase
              .from('orders')
              .select(
                'id, owner_id, station_name, total_amount, order_items(*), created_at, status',
              )
              .eq('customer_id', user.id)
              .eq('status', 'delivered')
              .order('created_at', ascending: false)
              .limit(1),
          'completed orders',
        ),
        // 6: active station products to resolve offered water types (Purified, Alkaline, Mineral)
        _safeHomeQuery(
          supabase
              .from('products')
              .select('owner_id, name, category, is_available')
              .eq('is_available', true),
          'station products',
        ),
      ]);

      final profile = batchResults[0] as Map<String, dynamic>?;
      final firstNameRaw = profile?['first_name']?.toString().trim();
      final firstName = (firstNameRaw != null && firstNameRaw.isNotEmpty)
          ? firstNameRaw
          : (profile?['full_name']?.toString().split(' ').first ??
                cachedFirstName ??
                'there');
      final town = _municipalityName(profile?['town']) ?? cachedTown;

      final ownerPrices = StationPriceHelpers.mapFromSettingsRows(
        batchResults[1] as List? ?? const [],
      );

      final ownerRows = batchResults[2] as List? ?? const [];
      final productRows = batchResults[6] as List? ?? const [];
      final Map<String, Set<String>> stationWaterTypes = {};
      for (final p in productRows) {
        if (p is Map) {
          final ownerId = p['owner_id']?.toString();
          if (ownerId != null && ownerId.isNotEmpty) {
            final types = stationWaterTypes.putIfAbsent(ownerId, () => <String>{});
            final cat = p['category']?.toString().trim();
            final name = p['name']?.toString().trim();
            if (cat != null && cat.isNotEmpty) {
              types.add(cat);
              final lowerCat = cat.toLowerCase();
              if (lowerCat.contains('container') ||
                  lowerCat.contains('accessor') ||
                  lowerCat == 'products') {
                types.add('Accessories');
              }
            }
            if (name != null) {
              final lower = name.toLowerCase();
              if (lower.contains('purified')) types.add('Purified');
              if (lower.contains('alkaline')) types.add('Alkaline');
              if (lower.contains('mineral')) types.add('Mineral');
              if (lower.contains('container') ||
                  lower.contains('bottle') ||
                  lower.contains('pump') ||
                  lower.contains('cap')) {
                types.add('Accessories');
              }
            }
          }
        }
      }

      Map<String, dynamic> enrichStation(Map<String, dynamic> raw) {
        final s = StationPriceHelpers.withResolvedPrice(
          Map<String, dynamic>.from(raw),
          ownerPrices: ownerPrices,
        );
        final sId = s['id']?.toString();
        final types = Set<String>.from(stationWaterTypes[sId] ?? const <String>{});

        // Also check cached station bundle in StationDataCache
        final cached = StationDataCache.instance.get(sId);
        if (cached != null) {
          if (cached.waterType != null && cached.waterType!.isNotEmpty) {
            types.add(cached.waterType!);
          }
          for (final prod in cached.products) {
            if (prod is Map) {
              final c = prod['category']?.toString();
              final n = prod['name']?.toString();
              if (c != null && c.isNotEmpty) {
                types.add(c);
                final lowerCat = c.toLowerCase();
                if (lowerCat.contains('container') ||
                    lowerCat.contains('accessor') ||
                    lowerCat == 'products') {
                  types.add('Accessories');
                }
              }
              if (n != null) {
                final lower = n.toLowerCase();
                if (lower.contains('purified')) types.add('Purified');
                if (lower.contains('alkaline')) types.add('Alkaline');
                if (lower.contains('mineral')) types.add('Mineral');
                if (lower.contains('container') ||
                    lower.contains('bottle') ||
                    lower.contains('pump') ||
                    lower.contains('cap')) {
                  types.add('Accessories');
                }
              }
            }
          }
        }

        // Profile primary_water_type
        final primary = s['primary_water_type']?.toString().trim();
        if (primary != null && primary.isNotEmpty) {
          types.add(primary);
          final lower = primary.toLowerCase();
          if (lower.contains('purified')) types.add('Purified');
          if (lower.contains('alkaline')) types.add('Alkaline');
          if (lower.contains('mineral')) types.add('Mineral');
        }

        // Station name keywords (e.g. "Water Kaw Alkaline Station")
        final sName = (s['station_name'] ?? s['full_name'] ?? '').toString().toLowerCase();
        if (sName.contains('purified')) types.add('Purified');
        if (sName.contains('alkaline')) types.add('Alkaline');
        if (sName.contains('mineral')) types.add('Mineral');

        // Refill stations by default provide Purified if not specified
        if (types.isEmpty) {
          types.add('Purified');
        }

        // Home snapshots are persisted with jsonEncode. Keep the collection
        // JSON-safe while retaining the Set's de-duplication and insertion
        // order for category filtering and display after a cache reload.
        s['available_water_types'] = types.toList(growable: false);
        return s;
      }

      List<Map<String, dynamic>> stations = [];
      if (town != null && town.trim().isNotEmpty) {
        final townKey = town.trim().toLowerCase();
        final inTown = List<Map<String, dynamic>>.from(ownerRows)
            .where(
              (s) =>
                  (s['town'] ?? s['municipality'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase() ==
                  townKey,
            )
            .toList();

        if (inTown.isNotEmpty) {
          stations = StationQueryHelpers.withAvailabilityAll(inTown)
              .map(enrichStation)
              .take(6)
              .toList();
        }
      }

      // If no station matched the exact municipality string, show active stations serving the area so home is never empty
      if (stations.isEmpty && ownerRows.isNotEmpty) {
        stations =
            StationQueryHelpers.withAvailabilityAll(
                  List<Map<String, dynamic>>.from(ownerRows),
                )
                .map(enrichStation)
                .take(6)
                .toList();
      }

      // Map favorites from batch
      final favRows = batchResults[4] as List? ?? const [];
      final favIds = favRows
          .map((f) => f['station_id']?.toString())
          .whereType<String>()
          .toSet();
      final favorites =
          StationQueryHelpers.withAvailabilityAll(
                List<Map<String, dynamic>>.from(
                  ownerRows,
                ).where((s) => favIds.contains(s['id']?.toString())),
              )
              .map(enrichStation)
              .toList();

      final prefetchIds = {
        ...stations.map((s) => s['id']?.toString()),
        ...favorites.map((s) => s['id']?.toString()),
      }.whereType<String>().toList();
      StationDataCache.instance.prefetch(prefetchIds);

      final orders = batchResults[3] as List? ?? const [];
      final lastCompletedOrders = batchResults[5] as List? ?? const [];

      // Resolve quick order station: prefer last completed order's station
      Map<String, dynamic>? quickStation;
      bool quickIsLastOrder = false;
      Map<String, dynamic>? lastCompleted;

      if (lastCompletedOrders.isNotEmpty) {
        final candidateOrder = Map<String, dynamic>.from(lastCompletedOrders.first);
        final lastOwnerId = candidateOrder['owner_id']?.toString();
        if (lastOwnerId != null) {
          // Find station profile for the last order's owner
          final matchingStation = List<Map<String, dynamic>>.from(ownerRows)
              .where((s) => s['id']?.toString() == lastOwnerId)
              .map(
                (s) => StationPriceHelpers.withResolvedPrice(
                  StationQueryHelpers.withAvailability(
                    Map<String, dynamic>.from(s),
                  ),
                  ownerPrices: ownerPrices,
                ),
              )
              .firstOrNull;
          if (matchingStation != null) {
            final stationTown = (matchingStation['town'] ?? matchingStation['municipality'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final currentTownKey = town?.trim().toLowerCase() ?? '';
            // Only use as quick reorder station if it is located in the customer's current municipality
            if (currentTownKey.isEmpty || stationTown == currentTownKey) {
              quickStation = matchingStation;
              quickIsLastOrder = true;
              lastCompleted = candidateOrder;
            }
          }
        }
      }

      quickStation ??= favorites
              .where((f) {
                if (town == null || town.trim().isEmpty) return true;
                final fTown = (f['town'] ?? f['municipality'] ?? '').toString().trim().toLowerCase();
                return fTown == town.trim().toLowerCase();
              })
              .firstOrNull ??
          (stations.isNotEmpty ? stations.first : null);

      if (!mounted ||
          requestId != _homeFetchGeneration ||
          supabase.auth.currentUser?.id != userId) {
        return;
      }
      setState(() {
        _userFirstName = firstName;
        _userMunicipality = town ?? '';
        _stations = stations;
        _favoriteStations = favorites;
        _stationCount = stations.length;
        _quickOrderStation = quickStation;
        _quickStationIsLastOrder = quickIsLastOrder;
        _lastCompletedOrder = lastCompleted;
        _activeOrder = orders.isNotEmpty
            ? Map<String, dynamic>.from(orders.first)
            : null;
        _isLoading = false;
      });

      // Background cache snapshot for instant rendering on next open/revisit
      final homeSnapshot = {
        'userFirstName': firstName,
        'userMunicipality': town ?? '',
        'stations': stations,
        'favoriteStations': favorites,
        'quickOrderStation': quickStation,
        'quickStationIsLastOrder': quickIsLastOrder,
        'lastCompletedOrder': lastCompleted,
        'activeOrder': _activeOrder,
      };
      LocalDataCache.instance.set('customer_home_$userId', homeSnapshot);
    } catch (e) {
      debugPrint('Home fetch error: $e');
      if (mounted && requestId == _homeFetchGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeToOrders() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (_ordersChannel != null) {
      supabase.removeChannel(_ordersChannel!);
      _ordersChannel = null;
    }

    _ordersChannel = supabase
        .channel('home:updates:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: userId,
          ),
          callback: (_) => _fetchData(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (_) => _handleCustomerProfileChange(userId),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'owner_settings',
          callback: (_) => _fetchData(),
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) _subscribeToOrders();
            });
          }
        });
  }

  Future<void> _handleCustomerProfileChange(String userId) async {
    _homeCacheGeneration++;
    await LocalDataCache.instance.invalidate('customer_home_$userId');
    if (mounted && supabase.auth.currentUser?.id == userId) {
      await _fetchData();
    }
  }

  Future<List<Map<String, dynamic>>> _loadFavoriteStations(
    String userId, {
    required Map<String, double> ownerPrices,
  }) async {
    final favoriteRows = await supabase
        .from('favorites')
        .select('station_id')
        .eq('user_id', userId);
    final stationIds = (favoriteRows as List)
        .map((favorite) => favorite['station_id']?.toString())
        .whereType<String>()
        .toSet();

    if (stationIds.isEmpty) return [];

    final ownerRows = await supabase
        .from('profiles')
        .select(StationQueryHelpers.ownerStationFields)
        .eq('role', 'owner')
        .inFilter('id', stationIds.toList());

    return StationQueryHelpers.withAvailabilityAll(
      List<Map<String, dynamic>>.from(ownerRows),
    ).map((station) {
      return StationPriceHelpers.withResolvedPrice(
        Map<String, dynamic>.from(station),
        ownerPrices: ownerPrices,
      );
    }).toList();
  }

  void _subscribeToFavorites() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _favoritesChannel = supabase
        .channel('home:favorites:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'favorites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _refreshFavoriteStations(userId),
        )
        .subscribe();
  }

  void _subscribeToStations() {
    _stationsChannel = supabase
        .channel('home:station-updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            final record = payload.newRecord;
            if (record['role']?.toString() == 'owner') _fetchData();
          },
        )
        .subscribe();
  }

  Future<void> _refreshFavoriteStations(String userId) async {
    try {
      final ownerPrices = StationPriceHelpers.mapFromSettingsRows(
        await supabase
            .from('owner_settings')
            .select('owner_id, price_per_gallon'),
      );
      final favorites = await _loadFavoriteStations(
        userId,
        ownerPrices: ownerPrices,
      );

      if (!mounted || supabase.auth.currentUser?.id != userId) return;
      setState(() {
        _favoriteStations = favorites;
        if (!_quickStationIsLastOrder) {
          _quickOrderStation = favorites.isNotEmpty
              ? favorites.first
              : _stations.isNotEmpty
              ? _stations.first
              : null;
        }
      });
    } catch (e) {
      debugPrint('Error refreshing favorite stations: $e');
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _quickOrderStationName {
    final s = _quickOrderStation;
    if (s == null) return 'Browse stations';
    return s['station_name']?.toString().trim().isNotEmpty == true
        ? s['station_name'].toString()
        : s['full_name']?.toString() ?? 'Water station';
  }

  Widget _buildHomeBanner(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _homeBannerController,
            itemCount: 3,
            onPageChanged: (index) {
              setState(() => _homeBannerIndex = index);
              _startHomeBannerTimer();
            },
            itemBuilder: (context, index) =>
                _buildHomeBannerPage(context, index),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (index) => Semantics(
              button: true,
              label: 'Show banner ${index + 1} of 3',
              child: GestureDetector(
                onTap: () {
                  _homeBannerController.animateToPage(
                    index,
                    duration: AppUi.motion(context, AppUi.motionSlow),
                    curve: AppUi.motionCurve,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: _homeBannerIndex == index ? 20 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _homeBannerIndex == index
                        ? AppUi.bluePrimary
                        : AppUi.borderOf(context),
                    border: Border.all(
                      color: _homeBannerIndex == index
                          ? AppUi.bluePrimary
                          : AppUi.textMutedOf(context).withValues(alpha: 0.25),
                    ),
                    borderRadius: BorderRadius.circular(AppUi.radiusFull),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeBannerPage(BuildContext context, int index) {
    late final String title;
    late final String subtitle;
    late final String action;
    late final String eyebrow;
    late final IconData icon;
    late final ExperienceScene scene;
    late final List<Color> colors;
    late final VoidCallback onTap;

    switch (index) {
      case 0:
        eyebrow = 'WATER, CLOSER TO HOME';
        title = 'Your next refill is nearby';
        subtitle = 'Discover stations serving $_userMunicipality.';
        action = 'Explore stations';
        icon = Icons.explore_rounded;
        scene = ExperienceScene.discover;
        colors = const [AppUi.bluePrimary, AppUi.bluePrimaryDark];
        onTap = () => _openStations(context);
        break;
      case 1:
        eyebrow = _quickStationIsLastOrder ? 'EASY REORDER' : 'QUICK START';
        title = _quickOrderStation == null
            ? 'A better way to refill'
            : 'Your usual water, a few taps away';
        subtitle = _quickOrderStation == null
            ? 'Choose a station and place your first order with ease.'
            : _quickStationIsLastOrder
            ? 'Order again from your favorite recent station.'
            : 'Start an order from $_quickOrderStationName.';
        action = _quickOrderStation == null ? 'Find a station' : 'Order again';
        icon = Icons.water_drop_rounded;
        scene = ExperienceScene.delivery;
        colors = const [AppUi.bluePrimary, AppUi.bluePrimaryDark];
        onTap = _quickOrderStation == null
            ? () => _openStations(context)
            : () => _handleQuickOrder(
                _quickOrderStation!,
                order: _lastCompletedOrder,
              );
        break;
      case 2:
        final count = _favoriteStations.length;
        eyebrow = 'MADE FOR YOUR NEXT ORDER';
        title = 'Keep your go-to stations close';
        subtitle = count == 0
            ? 'Save stations you love and find them here next time.'
            : 'Your $count saved station${count == 1 ? '' : 's'} are one tap away.';
        action = 'View favorites';
        icon = Icons.favorite_rounded;
        scene = ExperienceScene.station;
        colors = const [AppUi.bluePrimary, AppUi.bluePrimaryDark];
        onTap = () => _showFavorites(context);
        break;
      default:
        throw RangeError.index(index, 3);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppUi.radiusSheet),
          child: Ink(
            decoration: BoxDecoration(
              color: colors.first,
              borderRadius: BorderRadius.circular(AppUi.radiusSheet),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(17, 13, 13, 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(AppUi.radiusFull),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                eyebrow,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.25,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 12,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(AppUi.radiusFull),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      action,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.last,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: colors.last,
                                    size: 13,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                      SizedBox(
                        width: 104,
                        height: 132,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ExperienceIllustration(
                              scene: scene,
                              role: ExperienceRole.customer,
                              height: 126,
                              animate: false,
                            ),
                            Positioned(
                              top: 3,
                              right: 2,
                              child: Container(
                                width: 31,
                                height: 31,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(icon, color: colors.last, size: 17),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleQuickOrder(
    Map<String, dynamic> station, {
    Map<String, dynamic>? order,
  }) async {
    if (_isProcessingQuickOrder) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthDialogs.showSignInRequired(context);
      return;
    }

    final availability = station['station_availability']?.toString() ??
        ((station['is_open'] as bool? ?? true) ? 'open' : 'closed');
    if (availability != 'open') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            availability == 'busy'
                ? 'Station is busy and not accepting new orders.'
                : availability == 'maintenance'
                    ? 'Station is under maintenance right now.'
                    : 'Station is currently closed.',
          ),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isProcessingQuickOrder = true);

    try {
      final cart = Provider.of<CartProvider>(context, listen: false);
      final stationId = station['id']?.toString() ??
          station['owner_id']?.toString() ??
          '';
      final stationName = station['station_name']?.toString() ??
          station['full_name']?.toString() ??
          'Water Station';

      cart.clearCart();
      cart.setStation(stationId, stationName);

      bool itemsPopulated = false;

      // 1. Populate from previous order items if available
      List<dynamic> items = (order?['order_items'] as List?) ?? const [];
      if (items.isEmpty && order?['id'] != null) {
        try {
          final fetched = await supabase
              .from('order_items')
              .select('*')
              .eq('order_id', order!['id']);
          items = fetched as List<dynamic>;
        } catch (_) {}
      }

      // Only reuse items whose product and price are known. The server prices
      // orders from product_id, so an invented price would only mislead.
      final validItems = items
          .whereType<Map<String, dynamic>>()
          .where((raw) => OrderProductHelpers.isValidProductId(raw['product_id']))
          .where((raw) => raw['price_at_purchase'] is num)
          .toList();

      if (validItems.isNotEmpty) {
        for (final raw in validItems) {
          final productId = raw['product_id'].toString();
          final productName =
              (raw['product_name'] ?? 'Purified Water Refill').toString();
          final price = (raw['price_at_purchase'] as num).toDouble();
          final qty = ((raw['quantity'] as num?) ?? 1).toInt();

          cart.addItem(productId, productName, price);
          if (qty > 1) {
            cart.updateQuantity(productId, qty);
          }
        }
        itemsPopulated = true;
      }

      // 2. Fallback: the station's cheapest available product, if it has a price.
      if (!itemsPopulated) {
        Map<String, dynamic>? defaultProduct;
        try {
          final prods = await supabase
              .from('products')
              .select('*')
              .eq('owner_id', stationId)
              .eq('is_available', true)
              .order('price', ascending: true)
              .limit(1);
          if (prods.isNotEmpty) {
            defaultProduct = prods.first;
          }
        } catch (_) {}

        final prodId = defaultProduct?['id']?.toString();
        final price = (defaultProduct?['price'] as num?)?.toDouble();
        if (prodId == null || price == null) {
          // No priced product to prefill: let the customer choose on the
          // station page instead of guessing.
          cart.clearCart();
          if (!mounted) return;
          context.openStationDetails(station);
          return;
        }
        cart.addItem(
          prodId,
          defaultProduct?['name']?.toString() ?? 'Water refill',
          price,
        );
        cart.updateQuantity(prodId, 1);
      }

      if (!mounted) return;
      context.openCheckout({
        'id': stationId,
        'station_name': stationName,
        'is_open': true,
      });
    } catch (e) {
      debugPrint('Quick order error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start quick order: ${FriendlyErrors.message(e)}'),
            backgroundColor: AppColors.uiError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingQuickOrder = false);
    }
  }

  void _openLocationPicker(BuildContext context) async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.user;
    await context.openSavedAddresses(
      SavedAddressLaunchContext(
        address: user?.completeAddress ?? '',
        landmark: user?.landmark ?? '',
        town: _userMunicipality.isNotEmpty ? _userMunicipality : user?.town,
        barangay: user?.barangay,
        latitude: user?.latitude ?? 0.0,
        longitude: user?.longitude ?? 0.0,
      ),
    );
    if (!mounted) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      _homeCacheGeneration++;
      await LocalDataCache.instance.invalidatePattern('customer_home_');
      await LocalDataCache.instance.invalidate('cached_owner_stations');
    }
    await userProvider.refreshProfile();
    if (!mounted) return;
    // Never briefly advertise stations from the old municipality while the
    // authoritative profile query for the newly selected address is pending.
    setState(() {
      _stations = [];
      _favoriteStations = [];
      _stationCount = 0;
      _quickOrderStation = null;
      _quickStationIsLastOrder = false;
      _isLoading = true;
    });
    await _fetchData();
  }

  List<Map<String, dynamic>> get _filteredStations {
    List<Map<String, dynamic>> base;
    if (_selectedCategory == 'All') {
      base = List<Map<String, dynamic>>.from(_stations);
    } else {
      final cat = _selectedCategory.toLowerCase();
      base = _stations.where((s) {
        final types = s['available_water_types'];
        if (types is Set<String>) {
          if (types.any((t) => t.toLowerCase() == cat || t.toLowerCase().contains(cat))) {
            return true;
          }
        } else if (types is Iterable) {
          if (types.any((t) => t.toString().toLowerCase() == cat || t.toString().toLowerCase().contains(cat))) {
            return true;
          }
        }

        final primaryType = (s['primary_water_type'] ?? '').toString().toLowerCase();
        if (primaryType.contains(cat)) return true;

        final name = (s['station_name'] ?? s['full_name'] ?? '').toString().toLowerCase();
        if (name.contains(cat)) return true;

        return false;
      }).toList();
    }

    // Sort: open stations first, closed stations moved to the bottom
    base.sort((a, b) {
      final aAvail = (a['station_availability'] ?? (a['is_open'] == false ? 'closed' : 'open')).toString().toLowerCase();
      final bAvail = (b['station_availability'] ?? (b['is_open'] == false ? 'closed' : 'open')).toString().toLowerCase();
      final aClosed = aAvail == 'closed';
      final bClosed = bAvail == 'closed';
      if (aClosed && !bClosed) return 1;
      if (!aClosed && bClosed) return -1;
      return 0;
    });

    return base;
  }

  Widget _buildQuickOrderButton(BuildContext context) {
    final targetStation = _quickOrderStation ??
        (_stations.isNotEmpty ? _stations.first : null);
    final order = _lastCompletedOrder;
    final isReorder = _quickOrderStation != null && order != null;
    final stationName = targetStation != null
        ? ((targetStation['station_name']?.toString().trim().isNotEmpty == true)
            ? targetStation['station_name'].toString()
            : (targetStation['full_name']?.toString() ?? 'Nearby Station'))
        : null;

    final totalAmount = (order?['total_amount'] as num?)?.toDouble();
    final itemsList = order?['order_items'] as List? ?? const [];
    final itemCount = itemsList.length;
    final itemSummary = itemCount > 0
        ? '$itemCount item${itemCount == 1 ? '' : 's'}'
        : null;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppUi.radiusSheet),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        onTap: _isProcessingQuickOrder
            ? null
            : () {
                if (targetStation != null) {
                  _handleQuickOrder(targetStation, order: order);
                } else {
                  _openStations(context);
                }
              },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppUi.radiusSheet),
            border: Border.all(color: AppUi.borderOf(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppUi.brandSoftOf(context),
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                ),
                child: _isProcessingQuickOrder
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppUi.bluePrimary,
                          ),
                        ),
                      )
                    : Icon(
                        isReorder ? Icons.replay_rounded : Icons.bolt_rounded,
                        color: AppUi.brandOf(context),
                        size: 24,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isReorder ? 'REPEAT LAST ORDER' : 'QUICK REFILL',
                          style: TextStyle(
                            color: AppUi.brandOf(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        if (isReorder && totalAmount != null) ...[
                          Text(
                            ' · ${formatPeso(totalAmount, whole: true)}',
                            style: TextStyle(
                              color: AppUi.textSecondaryOf(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stationName != null
                          ? (isReorder
                              ? 'Reorder from $stationName'
                              : 'Refill from $stationName')
                          : 'Quick order water in 1 tap',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isReorder && itemSummary != null
                          ? '$itemSummary · Instant checkout'
                          : 'Pre-filled cart · Tap to place order',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppUi.captionText.copyWith(
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppUi.bluePrimary,
                  borderRadius: BorderRadius.circular(AppUi.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isReorder ? 'Reorder' : 'Order',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaterCategoryRow(BuildContext context) {
    final prefType = context.watch<UserProvider>().user?.preferredWaterType;
    final prefShortName = prefType != null && prefType.trim().isNotEmpty
        ? WaterTypes.byName(prefType).shortName
        : null;

    const categories = [
      {'label': 'All Refills', 'icon': Icons.grid_view_rounded, 'filter': 'All'},
      {'label': 'Purified', 'icon': Icons.water_drop_rounded, 'filter': 'Purified'},
      {'label': 'Alkaline', 'icon': Icons.science_rounded, 'filter': 'Alkaline'},
      {'label': 'Mineral', 'icon': Icons.spa_rounded, 'filter': 'Mineral'},
      {'label': 'Accessories', 'icon': Icons.inventory_2_outlined, 'filter': 'Accessories'},
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = categories[i];
          final filterKey = cat['filter'] as String;
          final isSelected = _selectedCategory == filterKey;
          final isPreferred = prefShortName != null &&
              filterKey.toLowerCase() == prefShortName.toLowerCase();

          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppUi.radiusFull),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppUi.radiusFull),
              onTap: () {
                AppHaptics.selection();
                setState(() => _selectedCategory = filterKey);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppUi.bluePrimary
                      : (isPreferred
                          ? AppUi.bluePrimary.withValues(alpha: 0.08)
                          : AppUi.surfaceOf(context)),
                  borderRadius: BorderRadius.circular(AppUi.radiusFull),
                  border: Border.all(
                    color: isSelected
                        ? AppUi.bluePrimary
                        : (isPreferred
                            ? AppUi.bluePrimary.withValues(alpha: 0.35)
                            : AppUi.borderOf(context)),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cat['icon'] as IconData,
                      size: 15,
                      color: isSelected
                          ? Colors.white
                          : (isPreferred
                              ? AppUi.bluePrimary
                              : AppUi.textSecondaryOf(context)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat['label'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected || isPreferred ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : (isPreferred
                                ? AppUi.bluePrimary
                                : AppUi.textPrimaryOf(context)),
                      ),
                    ),
                    if (isPreferred) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: isSelected ? Colors.white : AppUi.brandOf(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return _buildSkeleton();

    final displayedStations = _filteredStations;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          Selector<NotificationProvider, int>(
            selector: (_, p) => p.unreadCount,
            builder: (context, notifCount, _) {
              return CustomerHeroHeader(
                greeting: '$_greeting, $_userFirstName',
                location: _municipalityName(
                      context.watch<UserProvider>().user?.town,
                    ) ??
                    (_userMunicipality.isNotEmpty
                        ? _userMunicipality
                        : 'Set your municipality'),
                notificationCount: notifCount,
                onNotificationTap: () => _showNotifications(context),
                onFavoritesTap: () => _showFavorites(context),
                onLocationTap: () => _openLocationPicker(context),
                favoritesCount: _favoriteStations.length,
              );
            },
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppUi.bluePrimary,
              onRefresh: _fetchData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppUi.screenPadding,
                      AppUi.spacingMd,
                      AppUi.screenPadding,
                      0,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const OfflineSyncStatusPill(),
                        if (_activeOrder != null) ...[
                          LiveOrderProgressTracker(
                            status: _activeOrder!['status']?.toString() ?? 'pending',
                            stationName: (_activeOrder!['profiles'] as Map<String, dynamic>?)?['station_name'] ??
                                _activeOrder!['station_name']?.toString() ??
                                'Water Station',
                            riderName: (_activeOrder!['rider'] as Map<String, dynamic>?)?['full_name']?.toString(),
                            onTrackMap: () =>
                                context.openOrderTracker(_activeOrder!),
                            onChat: () => context.openInbox(),
                          ),
                          AppUi.vGapMd,
                        ],
                        _buildHomeBanner(context),
                        AppUi.vGapMd,
                        _buildQuickOrderButton(context),
                        AppUi.vGapMd,
                        _buildWaterCategoryRow(context),
                        AppUi.vGapMd,
                        Row(
                          children: [
                            Text(
                              _selectedCategory == 'All'
                                  ? 'Nearby stations'
                                  : 'Nearby $_selectedCategory stations',
                              style: AppUi.sectionTitle,
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => _openStations(context),
                              child: Text(
                                _selectedCategory == 'All'
                                    ? 'See all ($_stationCount)'
                                    : 'See all (${displayedStations.length})',
                              ),
                            ),
                          ],
                        ),
                        AppUi.vGapSm,
                      ]),
                    ),
                  ),
                  if (displayedStations.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppUi.screenPadding,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: AxoEmptyState(
                          pose: AxoPose.empty,
                          title: _selectedCategory == 'All'
                              ? 'No stations nearby yet'
                              : 'No $_selectedCategory stations found',
                          message: _selectedCategory == 'All'
                              ? 'We could not find refill stations in your municipality. Browse all stations or update your profile town.'
                              : 'No stations in your area currently offer $_selectedCategory refills. Tap below to view all stations.',
                          actionLabel: _selectedCategory == 'All'
                              ? 'Browse stations'
                              : 'View all refills',
                          onAction: () {
                            if (_selectedCategory != 'All') {
                              setState(() => _selectedCategory = 'All');
                            } else {
                              _openStations(context);
                            }
                          },
                          compact: true,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppUi.screenPadding,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: AppUi.spacingSm,
                              mainAxisSpacing: AppUi.spacingSm,
                              childAspectRatio: 0.74,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => StationCard(
                            station: displayedStations[index],
                            compact: true,
                            onTap: () => context.openStationDetails(
                              displayedStations[index],
                            ),
                          ),
                          childCount: displayedStations.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    showNotificationPreviewSheet(
      context,
      onViewAll: () => context.openNotifications(),
    );
  }

  void _showFavorites(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.42,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppUi.radiusPill)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const _SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Favorite stations',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StatefulBuilder(
                    builder: (context, setSheetState) {
                      if (_favoriteStations.isEmpty) {
                        return const _SheetEmptyState(
                          icon: Icons.favorite_border_rounded,
                          message:
                              'Save stations with the heart button to find them here.',
                        );
                      }
                      return ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: _favoriteStations.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final station = _favoriteStations[index];
                          final stationId = station['id']?.toString();
                          final isUpdating =
                              stationId != null &&
                              _favoriteChangesInProgress.contains(stationId);
                          final name = station['station_name']
                              ?.toString()
                              .trim();
                          final title = name != null && name.isNotEmpty
                              ? name
                              : station['full_name']?.toString() ??
                                    'Water station';
                          final location =
                              [
                                    station['barangay']?.toString(),
                                    station['town']?.toString(),
                                  ]
                                  .where(
                                    (part) => part != null && part.isNotEmpty,
                                  )
                                  .join(', ');
                          final photo = station['station_photo_url']
                              ?.toString();
                          final price = station['price_per_gallon'];
                          return Material(
                            color: AppUi.pageBgOf(context),
                            borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                context.openStationDetails(station);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                                      child: SizedBox(
                                        width: 54,
                                        height: 54,
                                        child: AppCachedImage(
                                          imageUrl: photo,
                                          width: 54,
                                          height: 54,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 150,
                                          memCacheHeight: 150,
                                          errorWidget: const _StationThumb(),
                                          placeholder: const _StationThumb(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            location.isEmpty
                                                ? 'Nearby station'
                                                : location,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppUi.captionText,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (price is num) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '${formatPeso(price, whole: true)}/gal',
                                        style: TextStyle(
                                          color: AppUi.brandOf(context),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    IconButton(
                                      tooltip: 'Remove from favorites',
                                      onPressed: stationId == null || isUpdating
                                          ? null
                                          : () => _removeFavorite(
                                              stationId,
                                              context,
                                              setSheetState,
                                            ),
                                      icon: isUpdating
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.favorite_rounded,
                                              color: AppUi.error,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _openStations(context);
                      },
                      child: const Text('Browse stations'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeFavorite(
    String stationId,
    BuildContext sheetContext,
    StateSetter setSheetState,
  ) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) AuthDialogs.showSignInRequired(context);
      return;
    }

    if (sheetContext.mounted) {
      setSheetState(() => _favoriteChangesInProgress.add(stationId));
    }
    try {
      await supabase
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('station_id', stationId);

      if (!mounted) return;
      setState(() {
        _favoriteStations.removeWhere(
          (station) => station['id']?.toString() == stationId,
        );
      });
      if (sheetContext.mounted) setSheetState(() {});
    } catch (e) {
      debugPrint('Error removing favorite station: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove favorite station.')),
        );
      }
    } finally {
      _favoriteChangesInProgress.remove(stationId);
      if (sheetContext.mounted) setSheetState(() {});
    }
  }

  void _openStations(BuildContext context) {
    HapticFeedback.lightImpact();
    if (widget.onOpenStations != null) {
      widget.onOpenStations!();
      return;
    }
    context.openStationList();
  }

  Widget _buildSkeleton() {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(height: 24),
            Skeleton(height: 140, borderRadius: 24),
            SizedBox(height: 16),
            Skeleton(height: 120, borderRadius: 16),
            SizedBox(height: 18),
            Expanded(child: Skeleton(height: 190, borderRadius: 16)),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      decoration: BoxDecoration(
        color: AppUi.textMutedOf(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppUi.radiusFull),
      ),
    );
  }
}

class _SheetEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _SheetEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppUi.textMutedOf(context)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppUi.textSecondaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationThumb extends StatelessWidget {
  const _StationThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppUi.brandSoftOf(context),
      child: Icon(Icons.water_drop_rounded, color: AppUi.brandOf(context)),
    );
  }
}
