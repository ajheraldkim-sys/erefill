import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/providers/notification_provider.dart';
import 'package:erefill/core/providers/user_provider.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:erefill/core/widgets/app_ui_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/widgets/experience_widgets.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/widgets/notification_preview_sheet.dart';
import 'package:erefill/core/widgets/role_bottom_nav_bar.dart';
import 'package:erefill/core/widgets/lazy_indexed_stack.dart';
import 'order_management_screen.dart';
import 'riders_screen.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/models/system_notification.dart';
import 'owner_menu_screen.dart';
import 'stock_credits_hub_screen.dart';
import 'services/station_setup_service.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/services/owner_inventory_service.dart';
import 'package:erefill/core/services/local_data_cache.dart';
import 'package:erefill/core/services/observability_service.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import '../../subscriptions/services/subscription_service.dart';
import '../../payouts/widgets/owner_wallet_sheet.dart';
import 'widgets/new_order_alert_sheet.dart';
import 'package:erefill/core/widgets/offline_sync_status_pill.dart';
import '../../delivery_mgmt/providers/credit_provider.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final supabase = Supabase.instance.client;
  final _setupService = StationSetupService();
  StationSetupStatus _setupStatus = StationSetupStatus.empty();
  Map<String, dynamic>? ownerProfile;
  bool _isLoading = true;
  int _selectedIndex = 0;
  bool _isOpen = true;
  String _availability = 'open';
  int _totalRiders = 0;
  double _baseDeliveryFee = 0;
  double _pricePerGallon = 0;
  bool _hasOrderableProduct = false;
  String? _ownerId;
  StreamSubscription? _profileSub;
  StreamSubscription? _settingsSub;
  bool _setupStatusLoadInProgress = false;
  bool _setupStatusNeedsRefresh = false;
  int _stockCreditsTab = 0;

  @override
  void initState() {
    super.initState();
    final user = context.read<UserProvider>().user;
    if (user != null) {
      ownerProfile = {
        'id': user.id,
        'station_name': user.stationName,
        'full_name': user.fullName,
        'phone': user.phone,
        'town': user.town,
        'barangay': user.barangay,
        'latitude': user.latitude,
        'longitude': user.longitude,
        'station_photo_url': user.stationPhotoUrl,
        'average_rating': user.averageRating,
      };
      _isLoading = false;
    }
    _setupProfileListener();
  }

  void _setupProfileListener() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    _ownerId = user.id;

    // Auto-process due recurring subscriptions for this station in background
    unawaited(
      SubscriptionService()
          .processDueSubscriptions(stationId: user.id)
          .then<void>((_) {})
          .catchError((Object e) => ObservabilityService()
              .logFailure('generate_due_subscription_orders', e)),
    );
    if (mounted) {
      context.read<CreditProvider>().initialize(user.id);
    }

    _profileSub = SafeSupabase.listen(
      supabase.from('profiles').stream(primaryKey: ['id']).eq('id', user.id),
      (data) {
        if (data.isNotEmpty && mounted) {
          setState(() {
            ownerProfile = data.first;
            _isOpen = ownerProfile?['is_open'] ?? true;
            _availability =
                ownerProfile?['station_availability']?.toString() ??
                (_isOpen ? 'open' : 'closed');
            _isLoading = false;
          });
          _loadOwnerSetupStatus();
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Owner profile stream error: $error');
        debugPrint('Owner profile stream stack: $stackTrace');
      },
    );

    _settingsSub = SafeSupabase.listen(
      supabase
          .from('owner_settings')
          .stream(primaryKey: ['id'])
          .eq('owner_id', user.id),
      (data) {
        if (data.isNotEmpty && mounted) {
          final settings = data.first;
          setState(() {
            _baseDeliveryFee =
                (settings['base_delivery_fee'] as num?)?.toDouble() ??
                _baseDeliveryFee;
            _pricePerGallon =
                (settings['price_per_gallon'] as num?)?.toDouble() ??
                _pricePerGallon;
          });
          _loadOwnerSetupStatus();
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Owner settings stream error: $error');
      },
    );
  }

  void _changeTab(int index) {
    final wasDifferent = _selectedIndex != index;
    setState(() {
      _selectedIndex = index;
      if (index == 2 || index == 4) {
        _setupStatusNeedsRefresh = true;
      }
    });
    if (index == 0 && (wasDifferent || _setupStatusNeedsRefresh)) {
      _setupStatusNeedsRefresh = false;
      _loadOwnerSetupStatus();
    }
  }

  Future<void> _loadOwnerSetupStatus() async {
    if (_setupStatusLoadInProgress) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _setupStatusLoadInProgress = true;
    try {
      final statusFuture = _setupService.getSetupStatus(user.id);
      final ridersResponseFuture = supabase
          .from('profiles')
          .select('id')
          .eq('role', 'rider')
          .eq('owner_id', user.id);

      final settingsResponseFuture = supabase
          .from('owner_settings')
          .select('base_delivery_fee, price_per_gallon')
          .eq('owner_id', user.id)
          .maybeSingle();

      final productResponseFuture = supabase
          .from('products')
          .select('id')
          .eq('owner_id', user.id)
          .eq('is_available', true)
          .gt('price', 0)
          .limit(1);

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        statusFuture,
        ridersResponseFuture,
        settingsResponseFuture,
        productResponseFuture,
      ]);

      if (!mounted) return;
      final status = results[0] as StationSetupStatus;
      final riders = results[1] as List;
      final settings = results[2] as Map<String, dynamic>?;
      final products = results[3] as List;

      setState(() {
        _setupStatus = status;
        _totalRiders = riders.length;
        _baseDeliveryFee =
            (settings?['base_delivery_fee'] as num?)?.toDouble() ?? 0;
        _pricePerGallon =
            (settings?['price_per_gallon'] as num?)?.toDouble() ?? 0;
        _hasOrderableProduct = products.isNotEmpty || status.isProductsComplete;
      });

      if (_pricePerGallon > 0 && !_hasOrderableProduct) {
        try {
          final syncedProduct = await supabase.rpc(
            'sync_owner_default_product',
            params: {'p_owner_id': user.id},
          );
          if (mounted && syncedProduct != null) {
            setState(() => _hasOrderableProduct = true);
          }
        } catch (e) {
          debugPrint('Owner product sync on load failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading setup status: $e');
    } finally {
      _setupStatusLoadInProgress = false;
    }
  }

  Future<void> _setStationAvailability(String availability) async {
    if (_ownerId == null) return;
    if (availability == 'open' && !_setupStatus.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot open station: ${_setupStatus.completedCount} of 5 required setup sections completed. Missing: ${_setupStatus.missingFields.join(", ")}',
          ),
          backgroundColor: AppColors.uiError,
        ),
      );
      return;
    }

    try {
      await supabase
          .from('profiles')
          .update({
            'station_availability': availability,
            'is_open': availability == 'open',
          })
          .eq('id', _ownerId!);
      setState(() {
        _availability = availability;
        _isOpen = availability == 'open';
      });
    } catch (e) {
      debugPrint('Error toggling status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FriendlyErrors.message(e)),
            backgroundColor: AppColors.uiError,
          ),
        );
      }
    }
  }

  bool get _stationHasLocation =>
      (ownerProfile?['latitude'] as num?) != null &&
      (ownerProfile?['longitude'] as num?) != null;

  bool get _stationSetupReady => _setupStatus.isComplete;

  @override
  void dispose() {
    _profileSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildDashboardSkeleton();

    final List<Widget> screens = [
      _OwnerHomeOverview(
        fullName: ownerProfile?['full_name'],
        town: ownerProfile?['town'],
        barangay: ownerProfile?['barangay'],
        stationName: ownerProfile?['station_name'],
        availability: _availability,
        totalRiders: _totalRiders,
        hasOrderableProduct: _hasOrderableProduct,
        baseDeliveryFee: _baseDeliveryFee,
        pricePerGallon: _pricePerGallon,
        setupReady: _stationSetupReady,
        setupStatus: _setupStatus,
        hasLocationPin: _stationHasLocation,
        onAvailabilityChanged: _setStationAvailability,
        onViewOrders: () => _changeTab(1),
        onOpenInventory: () {
          setState(() => _stockCreditsTab = 0);
          _changeTab(2);
        },
        onOpenCredits: () {
          setState(() => _stockCreditsTab = 1);
          _changeTab(2);
        },
        onOpenAccount: () => _changeTab(4),
        onOpenRiders: () => _changeTab(3),
      ),
      const OrderManagementScreen(),
      StockCreditsHubScreen(
        key: ValueKey('stock_credits_$_stockCreditsTab'),
        initialTab: _stockCreditsTab,
      ),
      RidersScreen(ownerId: _ownerId ?? ''),
      const OwnerMenuScreen(),
    ];

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          _changeTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: SafeArea(
          bottom: false,
          child: LazyIndexedStack(index: _selectedIndex, children: screens),
        ),
        bottomNavigationBar: Consumer<NotificationProvider>(
          builder: (context, notif, _) {
            return RoleBottomNavBar(
              currentIndex: _selectedIndex,
              onTap: (index) => _changeTab(index),
              items: [
                const RoleBottomNavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Overview',
                ),
                RoleBottomNavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: 'Orders',
                  badgeCount: notif.newOrdersCount,
                ),
                const RoleBottomNavItem(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2_rounded,
                  label: 'Stock & Credits',
                ),
                const RoleBottomNavItem(
                  icon: Icons.delivery_dining_outlined,
                  activeIcon: Icons.delivery_dining_rounded,
                  label: 'Riders',
                ),
                const RoleBottomNavItem(
                  icon: Icons.storefront_outlined,
                  activeIcon: Icons.storefront_rounded,
                  label: 'Station',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDashboardSkeleton() {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Skeleton(
              height: 220,
              width: double.infinity,
              borderRadius: 0,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: const Skeleton(height: 120, borderRadius: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: const Skeleton(height: 120, borderRadius: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Skeleton(
                      height: 200,
                      width: double.infinity,
                      borderRadius: 24,
                    ),
                    const SizedBox(height: 24),
                    const Skeleton(
                      height: 300,
                      width: double.infinity,
                      borderRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerHomeOverview extends StatefulWidget {
  final String? fullName;
  final String? town;
  final String? barangay;
  final String? stationName;
  final String availability;
  final int totalRiders;
  final bool hasOrderableProduct;
  final double baseDeliveryFee;
  final double pricePerGallon;
  final bool setupReady;
  final StationSetupStatus setupStatus;
  final bool hasLocationPin;
  final ValueChanged<String> onAvailabilityChanged;
  final VoidCallback onViewOrders;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenCredits;
  final VoidCallback onOpenAccount;
  final VoidCallback? onOpenRiders;

  const _OwnerHomeOverview({
    this.fullName,
    this.town,
    this.barangay,
    this.stationName,
    required this.availability,
    required this.totalRiders,
    required this.hasOrderableProduct,
    required this.baseDeliveryFee,
    required this.pricePerGallon,
    required this.setupReady,
    required this.setupStatus,
    required this.hasLocationPin,
    required this.onAvailabilityChanged,
    required this.onViewOrders,
    required this.onOpenInventory,
    required this.onOpenCredits,
    required this.onOpenAccount,
    this.onOpenRiders,
  });

  @override
  State<_OwnerHomeOverview> createState() => _OwnerHomeOverviewState();
}

class _OwnerHomeOverviewState extends State<_OwnerHomeOverview>
    with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  Map<String, dynamic> _stats = {};
  List<dynamic> _recentOrders = [];
  OwnerInventorySnapshot? _inventory;
  StreamSubscription? _ordersSub;
  RealtimeChannel? _ordersChannel;
  final _inventoryService = OwnerInventoryService();
  int _previousPendingCount = 0;
  bool _isFirstOrdersLoad = true;

  Timer? _periodicRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final user = supabase.auth.currentUser;
    if (user != null) {
      final mem = LocalDataCache.instance.getMemory<Map<String, dynamic>>(
        'owner_overview_${user.id}',
      );
      if (mem != null) {
        _stats = Map<String, dynamic>.from(mem['stats'] as Map? ?? {});
        _recentOrders = List<dynamic>.from(mem['recentOrders'] as List? ?? []);
      }
    }
    _loadCachedOverview();
    _setupOrdersListener();
    _loadInventorySnapshot();
    _refreshOrdersSnapshot();
    _periodicRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadInventorySnapshot();
        _refreshOrdersSnapshot();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadInventorySnapshot();
      _refreshOrdersSnapshot();
    }
  }

  Future<void> _loadCachedOverview() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final cached = await LocalDataCache.instance.get<Map<String, dynamic>>(
        'owner_overview_${user.id}',
      );
      if (cached != null && mounted) {
        setState(() {
          _stats = Map<String, dynamic>.from(cached['stats'] as Map? ?? {});
          _recentOrders = List<dynamic>.from(
            cached['recentOrders'] as List? ?? [],
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading cached owner overview: $e');
    }
  }

  Future<void> _loadInventorySnapshot() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _inventoryService.fetchSnapshot(user.id);
      if (mounted) setState(() => _inventory = snapshot);
    } catch (e) {
      debugPrint('Inventory snapshot error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicRefreshTimer?.cancel();
    _ordersSub?.cancel();
    if (_ordersChannel != null) {
      supabase.removeChannel(_ordersChannel!);
    }
    super.dispose();
  }

  Future<void> _processOrders(List<dynamic> data) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final now = DateTime.now();

    double todayRevenue = 0;
    int todayOrdersCount = 0;
    int pendingCount = 0;
    int acceptedCount = 0;
    int preparingCount = 0;
    int readyCount = 0;
    int deliveringCount = 0;
    int deliveredTodayCount = 0;

    for (var o in data) {
      final rawCreated = o['created_at']?.toString();
      final dt = rawCreated != null
          ? DateTime.tryParse(rawCreated)?.toLocal()
          : null;
      final isToday =
          dt != null &&
          dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day;

      // Canonical status so aliases (confirmed, completed, ready_for_delivery,
      // assigned_to_rider, canceled) land in the same bucket as everywhere else.
      final status = OrderStatusColors.normalize(o['status']?.toString());
      final isVoid = status == 'cancelled' || status == 'rejected';

      if (isToday) {
        todayOrdersCount++;
        if (!isVoid) {
          todayRevenue += (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        }
      }

      if (status == 'pending') pendingCount++;
      if (status == 'accepted') acceptedCount++;
      if (status == 'preparing') preparingCount++;
      if (status == 'ready_for_pickup') readyCount++;
      if (status == 'out_for_delivery') deliveringCount++;
      if (status == 'delivered' && isToday) deliveredTodayCount++;
    }

    if (!_isFirstOrdersLoad && pendingCount > _previousPendingCount) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        final newestPending = data.firstWhere(
          (o) => (o['status'] ?? '') == 'pending',
          orElse: () => null,
        );
        if (newestPending is Map<String, dynamic>) {
          NewOrderAlertSheet.show(
            context,
            order: newestPending,
            onAccept: (orderId) async {
              await SafeSupabase.transitionOrderStatus(
                orderId: orderId,
                newStatus: 'accepted',
              );
              _refreshOrdersSnapshot();
            },
            onDecline: (orderId) async {
              await SafeSupabase.transitionOrderStatus(
                orderId: orderId,
                newStatus: 'cancelled',
              );
              _refreshOrdersSnapshot();
            },
          );
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.bolt, color: AppColors.uiWarning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pendingCount - _previousPendingCount == 1
                          ? 'New refill order received!'
                          : '${pendingCount - _previousPendingCount} new refill orders received!',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'View',
                onPressed: widget.onViewOrders,
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
    _isFirstOrdersLoad = false;
    _previousPendingCount = pendingCount;

    List<Map<String, dynamic>> enrichedRecent = [];
    try {
      final res = await supabase
          .from('orders')
          .select('*, profiles!orders_customer_id_fkey(full_name, avatar_url)')
          .eq('owner_id', user.id)
          .order('created_at', ascending: false)
          .limit(5);
      enrichedRecent = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Failed to fetch enriched recent orders, trying fallback: $e');
      try {
        final simple = await supabase
            .from('orders')
            .select('*')
            .eq('owner_id', user.id)
            .order('created_at', ascending: false)
            .limit(5);
        enrichedRecent = List<Map<String, dynamic>>.from(simple);
      } catch (err2) {
        debugPrint('Failed fallback recent orders: $err2');
      }
    }

    // Compute real 7-day daily trends from database orders
    final List<double> revenueTrend7Days = List.filled(7, 0.0);
    final List<double> ordersTrend7Days = List.filled(7, 0.0);
    final List<double> deliveredTrend7Days = List.filled(7, 0.0);
    final List<double> pendingTrend7Days = List.filled(7, 0.0);

    // Calculate start of each of the last 7 calendar days (0 = 6 days ago, 6 = today)
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = todayMidnight.subtract(const Duration(days: 6));

    for (var o in data) {
      final rawCreated = o['created_at']?.toString();
      final dt = rawCreated != null
          ? DateTime.tryParse(rawCreated)?.toLocal()
          : null;
      if (dt == null) continue;

      final orderDayMidnight = DateTime(dt.year, dt.month, dt.day);
      final dayOffset = orderDayMidnight.difference(sevenDaysAgo).inDays;

      if (dayOffset >= 0 && dayOffset < 7) {
        final amount = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        final status = OrderStatusColors.normalize(o['status']?.toString());

        ordersTrend7Days[dayOffset] += 1;
        if (status != 'cancelled' && status != 'rejected') {
          revenueTrend7Days[dayOffset] += amount;
        }
        if (status == 'delivered') {
          deliveredTrend7Days[dayOffset] += 1;
        }
        if (status == 'pending') {
          pendingTrend7Days[dayOffset] += 1;
        }
      }
    }

    final double calculatedWeeklyRevenue = revenueTrend7Days.fold<double>(
      0.0,
      (sum, val) => sum + val,
    );
    final int calculatedWeeklyOrders = ordersTrend7Days.fold<int>(
      0,
      (sum, val) => sum + val.toInt(),
    );

    if (mounted) {
      setState(() {
        _stats = {
          'ordersToday': todayOrdersCount,
          'revenueToday': todayRevenue,
          'pending': pendingCount,
          'accepted': acceptedCount,
          'preparing': preparingCount,
          'ready': readyCount,
          'delivering': deliveringCount,
          'delivered': deliveredTodayCount,
          'weeklyRevenue': calculatedWeeklyRevenue,
          'weeklyOrders': calculatedWeeklyOrders,
          'revenueTrend': revenueTrend7Days,
          'ordersTrend': ordersTrend7Days,
          'pendingTrend': pendingTrend7Days,
          'deliveredTrend': deliveredTrend7Days,
        };
        _recentOrders = enrichedRecent;
      });
      unawaited(
        LocalDataCache.instance.set('owner_overview_${user.id}', {
          'stats': _stats,
          'recentOrders': enrichedRecent,
        }),
      );
    }
  }

  Future<void> _refreshOrdersSnapshot() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await supabase
          .from('orders')
          .select('*')
          .eq('owner_id', user.id);
      await _processOrders(data);
    } catch (e) {
      debugPrint('Failed to refresh owner orders snapshot: $e');
    }
  }

  void _setupOrdersListener() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _ordersSub = SafeSupabase.listen(
      supabase
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('owner_id', user.id),
      (data) => _processOrders(data),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Orders stream error: $error');
        debugPrint('Orders stream stack: $stackTrace');
      },
    );

    if (_ordersChannel != null) {
      supabase.removeChannel(_ordersChannel!);
      _ordersChannel = null;
    }

    _ordersChannel = supabase
        .channel('public:orders:owner_overview:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: user.id,
          ),
          callback: (_) => _refreshOrdersSnapshot(),
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) _setupOrdersListener();
            });
          }
        });
  }

  int _stat(String key) => (_stats[key] as num?)?.toInt() ?? 0;
  double _amount(String key) => (_stats[key] as num?)?.toDouble() ?? 0.0;

  /// Today vs. yesterday from the real 7-day trend (last = today). Null when
  /// there is no basis for a comparison, so no percentage is invented.
  int? _dayOverDayPct(List<double> trend) {
    if (trend.length < 2) return null;
    final yesterday = trend[trend.length - 2];
    if (yesterday <= 0) return null;
    return ((trend.last - yesterday) / yesterday * 100).round();
  }

  List<double> _parseTrend(dynamic rawTrend) {
    if (rawTrend is! List) {
      return const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    }
    try {
      final list = rawTrend
          .map((e) => (e as num?)?.toDouble() ?? 0.0)
          .toList(growable: false);
      return list.length >= 2
          ? list
          : const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    } catch (_) {
      return const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    }
  }

  Widget _buildInventoryCard() {
    final inventory = _inventory;
    final theme = Theme.of(context);
    final warn = StatusToneStyle.of(
      StatusTone.warning,
      isDark: AppUi.isDark(context),
    );
    return AppCard(
      onTap: widget.onOpenInventory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Inventory',
            action: Icon(
              Icons.chevron_right_rounded,
              color: AppUi.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: AppUi.spacingMd),
          if (inventory == null)
            Text('Loading stock levels…', style: theme.textTheme.bodyMedium)
          else ...[
            Row(
              children: [
                Expanded(
                  child: _InventoryStat(
                    label: 'Filled',
                    value: '${inventory.filledGallons} gal',
                    warning: inventory.hasLowFilledStock,
                  ),
                ),
                const SizedBox(width: AppUi.spacingMd),
                Expanded(
                  child: _InventoryStat(
                    label: 'Empty',
                    value: '${inventory.emptyGallons} gal',
                  ),
                ),
              ],
            ),
            if (inventory.hasLowFilledStock) ...[
              const SizedBox(height: AppUi.spacingMd),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: AppUi.iconSm,
                    color: warn.foreground,
                  ),
                  const SizedBox(width: AppUi.spacingSm),
                  Expanded(
                    child: Text(
                      'Low filled stock — restock before peak hours.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: warn.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildGuidedSetupCard() {
    // Only shown until setup is complete; the station card covers the rest.
    final status = widget.setupStatus;

    return GuidedSetupCard(
      role: ExperienceRole.owner,
      title: 'Finish station setup · ${status.percentage}%',
      message:
          '${status.completedCount} of 5 sections done. Customers can order once everything is complete.',
      actionLabel: 'Continue setup',
      onAction: widget.onOpenAccount,
      steps: [
        ExperienceStep(
          label: 'Station profile',
          helper: 'Station name, phone number, municipality, and map pin.',
          isComplete: status.isProfileComplete,
          onTap: widget.onOpenAccount,
        ),
        ExperienceStep(
          label: 'Operating schedule',
          helper: 'Opening/closing hours and active operating days.',
          isComplete: status.isScheduleComplete,
          onTap: widget.onOpenAccount,
        ),
        ExperienceStep(
          label: 'Pricing & delivery rules',
          helper: 'Base refill price and centralized delivery policy.',
          isComplete: status.isDeliveryComplete,
          onTap: widget.onOpenAccount,
        ),
        ExperienceStep(
          label: 'Products & catalog',
          helper:
              'At least 1 active orderable refill, container, or accessory.',
          isComplete: status.isProductsComplete,
          onTap: () => context.openOwnerServiceCatalog(),
        ),
        ExperienceStep(
          label: 'Accepted payment methods',
          helper: 'Cash on delivery, GCash, Maya, or card channels.',
          isComplete: status.isPaymentsComplete,
          onTap: widget.onOpenAccount,
        ),
      ],
    );
  }

  void _showBroadcastBottomSheet(BuildContext context) {
    final titleController = TextEditingController(text: 'Station Alert');
    final messageController = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: AppUi.radiusSheetTop,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.campaign_rounded,
                          color: AppUi.brandOf(context),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Alert riders',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This will send a priority alert to ALL of your active riders instantly.',
                      style: TextStyle(
                        color: AppUi.textSecondaryOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: titleController,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                      decoration: AppUi.fieldDecorationOf(
                        context,
                        'Alert Title',
                        prefixIcon: const Icon(Icons.label_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: messageController,
                      onChanged: (_) => setState(() {}),
                      maxLines: 4,
                      maxLength: 160,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppUi.textPrimaryOf(context),
                      ),
                      decoration:
                          AppUi.fieldDecorationOf(
                            context,
                            'Type your message...',
                            prefixIcon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                            ),
                          ).copyWith(
                            alignLabelWithHint: true,
                            counterStyle: TextStyle(
                              color: AppUi.textSecondaryOf(context),
                              fontSize: 12,
                            ),
                          ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: AppUi.buttonHeight,
                      child: FilledButton(
                        onPressed:
                            isSending || messageController.text.trim().isEmpty
                            ? null
                            : () async {
                                setState(() => isSending = true);
                                try {
                                  final service = ChatService();
                                  await service.broadcastToRiders(
                                    title: titleController.text,
                                    content: messageController.text,
                                    type: NotificationType.stationBroadcast,
                                  );
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Broadcast sent successfully!',
                                      ),
                                      backgroundColor: AppColors.uiSuccess,
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  setState(() => isSending = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed: ${FriendlyErrors.message(e)}',
                                      ),
                                      backgroundColor: AppColors.uiError,
                                    ),
                                  );
                                }
                              },
                        child: isSending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text('Send to all riders'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = [
      if (widget.barangay != null) widget.barangay,
      if (widget.town != null) widget.town,
    ].join(', ');
    final pending = _stat('pending');

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          Consumer<NotificationProvider>(
            builder: (context, notif, _) {
              return OwnerHeroHeader(
                stationName: widget.stationName ?? 'Water Station',
                location: location.isEmpty ? 'Set your location' : location,
                availability: widget.availability,
                onNotificationTap: () => showNotificationPreviewSheet(
                  context,
                  onViewAll: () => context.openNotifications(),
                ),
                onChatTap: () => context.openInbox(),
                unreadChatCount: notif.unreadChatCount,
              );
            },
          ),
          const OfflineSyncStatusPill(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _ordersSub?.cancel();
                _setupOrdersListener();
                await Future.wait([
                  _loadInventorySnapshot(),
                  _refreshOrdersSnapshot(),
                ]);
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= AppBreakpoints.expanded;

                  final callout = pending > 0
                      ? _PendingOrdersCallout(
                          count: pending,
                          onReview: widget.onViewOrders,
                        )
                      : null;
                  final station = _StationStatusCard(
                    availability: widget.availability,
                    totalRiders: widget.totalRiders,
                    pricingSet:
                        widget.baseDeliveryFee > 0 &&
                        widget.pricePerGallon > 0 &&
                        widget.hasOrderableProduct,
                    onChanged: widget.onAvailabilityChanged,
                  );
                  final setup = widget.setupReady
                      ? null
                      : _buildGuidedSetupCard();

                  final main = <Widget>[
                    ?callout,
                    _buildTodaySection(),
                    _buildPipelineCard(),
                    _buildRecentOrders(),
                  ];
                  final side = <Widget>[
                    station,
                    ?setup,
                    _buildInventoryCard(),
                    _buildQuickActions(),
                  ];
                  final phone = <Widget>[
                    ?callout,
                    station,
                    ?setup,
                    _buildTodaySection(),
                    _buildPipelineCard(),
                    _buildInventoryCard(),
                    _buildQuickActions(),
                    _buildRecentOrders(),
                  ];

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    padding: AppUi.pagePaddingLoose.copyWith(
                      top: AppUi.spacingLg,
                    ),
                    children: [
                      ResponsiveCenter(
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: _stack(main)),
                                  const SizedBox(width: AppUi.spacingXl),
                                  Expanded(flex: 2, child: _stack(side)),
                                ],
                              )
                            : _stack(phone),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stack(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppUi.spacingXl),
          children[i],
        ],
      ],
    );
  }

  Widget _buildTodaySection() {
    final revenueTrend = _parseTrend(_stats['revenueTrend']);
    final ordersTrend = _parseTrend(_stats['ordersTrend']);
    final deliveredTrend = _parseTrend(_stats['deliveredTrend']);
    final weeklyOrders = _stat('weeklyOrders');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Today',
          subtitle:
              'Last 7 days: ${formatPeso(_amount('weeklyRevenue'), whole: true)}'
              ' · $weeklyOrders order${weeklyOrders == 1 ? '' : 's'}',
        ),
        const SizedBox(height: AppUi.spacingMd),
        Consumer<CreditProvider>(
          builder: (context, creditProv, _) {
            final unpaid = creditProv.credits.where((c) => !c.isPaid);
            final utang = unpaid.fold<double>(0, (sum, c) => sum + c.remaining);
            final unpaidCount = unpaid.length;
            return _ResponsiveGrid(
              minTileWidth: 150,
              maxColumns: 4,
              children: [
                _KpiTile(
                  label: 'Revenue',
                  value: formatPeso(_amount('revenueToday'), whole: true),
                  icon: Icons.payments_outlined,
                  deltaPct: _dayOverDayPct(revenueTrend),
                ),
                _KpiTile(
                  label: 'Orders',
                  value: '${_stat('ordersToday')}',
                  icon: Icons.receipt_long_outlined,
                  deltaPct: _dayOverDayPct(ordersTrend),
                ),
                _KpiTile(
                  label: 'Delivered',
                  value: '${_stat('delivered')}',
                  icon: Icons.check_circle_outline_rounded,
                  deltaPct: _dayOverDayPct(deliveredTrend),
                ),
                _KpiTile(
                  label: 'Unpaid utang',
                  value: formatPeso(utang, whole: true),
                  icon: Icons.account_balance_wallet_outlined,
                  footnote: unpaidCount > 0
                      ? '$unpaidCount customer${unpaidCount == 1 ? '' : 's'}'
                      : 'All settled',
                  footnoteTone: unpaidCount > 0 ? StatusTone.warning : null,
                  onTap: widget.onOpenCredits,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPipelineCard() {
    const stages = [
      ('pending', 'Pending'),
      ('accepted', 'Accepted'),
      ('preparing', 'Preparing'),
      ('ready_for_pickup', 'Ready'),
      ('out_for_delivery', 'On the way'),
    ];
    final counts = {
      'pending': _stat('pending'),
      'accepted': _stat('accepted'),
      'preparing': _stat('preparing'),
      'ready_for_pickup': _stat('ready'),
      'out_for_delivery': _stat('delivering'),
    };
    final active = counts.values.fold<int>(0, (a, b) => a + b);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: 'Order pipeline',
            subtitle: active == 0
                ? 'No active orders'
                : '$active active order${active == 1 ? '' : 's'}',
            action: TextButton(
              onPressed: widget.onViewOrders,
              child: const Text('Manage'),
            ),
          ),
          const SizedBox(height: AppUi.spacingMd),
          _ResponsiveGrid(
            minTileWidth: 96,
            maxColumns: 5,
            spacing: AppUi.spacingSm,
            children: [
              for (final (status, label) in stages)
                _PipelineStage(
                  label: label,
                  count: counts[status] ?? 0,
                  color: OrderStatusColors.getColor(status),
                  onTap: widget.onViewOrders,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: 'Quick actions'),
        const SizedBox(height: AppUi.spacingMd),
        _QuickActionList(
          children: [
            _QuickAction(
              icon: Icons.water_drop_outlined,
              label: 'Water catalog',
              onTap: () => context.openOwnerServiceCatalog(),
            ),
            _QuickAction(
              icon: Icons.receipt_long_outlined,
              label: 'Credits & utang',
              onTap: widget.onOpenCredits,
            ),
            _QuickAction(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Digital wallet',
              onTap: () {
                final uid = supabase.auth.currentUser?.id;
                if (uid != null) {
                  OwnerWalletSheet.show(
                    context,
                    ownerId: uid,
                    onManageRiderPayouts: widget.onOpenRiders,
                  );
                }
              },
            ),
            _QuickAction(
              icon: Icons.campaign_outlined,
              label: 'Alert riders',
              onTap: () => _showBroadcastBottomSheet(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentOrders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Recent orders',
          action: TextButton(
            onPressed: widget.onViewOrders,
            child: const Text('View all'),
          ),
        ),
        const SizedBox(height: AppUi.spacingSm),
        if (_recentOrders.isEmpty)
          AxoEmptyState(
            pose: AxoPose.empty,
            title: 'No orders yet',
            message:
                'When customers place refill orders, they will appear here instantly.',
            compact: true,
          )
        else
          ..._recentOrders.map(
            (o) => _OrderListItem(order: o, onTap: widget.onViewOrders),
          ),
      ],
    );
  }
}

/// Title row used by every overview section: title, optional one-line
/// context and an optional trailing action.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const _SectionHeader({required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

/// Lays children out in equal-width columns: as many as fit at
/// [minTileWidth], capped at [maxColumns].
class _ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;

  const _ResponsiveGrid({
    required this.children,
    required this.minTileWidth,
    required this.maxColumns,
    this.spacing = AppUi.spacingMd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit =
            ((constraints.maxWidth + spacing) / (minTileWidth + spacing))
                .floor();
        final columns = fit.clamp(1, maxColumns);
        double widthFor(int perRow) =>
            (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        // A short last row stretches to the full width instead of leaving a
        // hole (e.g. 5 pipeline stages on a phone become 3 + 2).
        final lastRowStart = children.length - children.length % columns;
        final lastRowCount = children.length % columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < children.length; i++)
              SizedBox(
                width: lastRowCount > 0 && i >= lastRowStart
                    ? widthFor(lastRowCount)
                    : widthFor(columns),
                child: children[i],
              ),
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  /// Real day-over-day change; null when yesterday had no data.
  final int? deltaPct;
  final String? footnote;
  final StatusTone? footnoteTone;
  final VoidCallback? onTap;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    this.deltaPct,
    this.footnote,
    this.footnoteTone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = AppUi.isDark(context);
    final secondary = AppUi.textSecondaryOf(context);

    Widget foot;
    if (deltaPct != null) {
      final up = deltaPct! >= 0;
      final tone = StatusToneStyle.of(
        up ? StatusTone.success : StatusTone.danger,
        isDark: isDark,
      );
      foot = Row(
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: AppUi.iconSm,
            color: tone.foreground,
          ),
          const SizedBox(width: AppUi.spacingXs),
          Flexible(
            child: Text(
              '${up ? '+' : ''}$deltaPct% vs yesterday',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    } else {
      final color = footnoteTone == null
          ? secondary
          : StatusToneStyle.of(footnoteTone!, isDark: isDark).foreground;
      foot = Text(
        footnote ?? 'No data yesterday',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      );
    }

    return Semantics(
      container: true,
      button: onTap != null,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppUi.iconSm, color: secondary),
                const SizedBox(width: AppUi.spacingSm - 2),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppUi.spacingSm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
            ),
            const SizedBox(height: AppUi.spacingXs),
            foot,
          ],
        ),
      ),
    );
  }
}

class _PipelineStage extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  const _PipelineStage({
    required this.label,
    required this.count,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idle = count == 0;
    return Semantics(
      button: onTap != null,
      label: '$count $label',
      excludeSemantics: true,
      child: Material(
        color: AppUi.surfaceRaisedOf(context),
        borderRadius: AppUi.controlRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppUi.controlRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(AppUi.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: idle
                          ? AppUi.textSecondaryOf(context)
                          : AppUi.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: idle ? AppUi.borderOf(context) : color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryStat extends StatelessWidget {
  final String label;
  final String value;
  final bool warning;

  const _InventoryStat({
    required this.label,
    required this.value,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppUi.spacingMd),
      decoration: BoxDecoration(
        color: AppUi.surfaceRaisedOf(context),
        borderRadius: AppUi.controlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppUi.spacingXs),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: warning
                  ? StatusToneStyle.of(
                      StatusTone.warning,
                      isDark: AppUi.isDark(context),
                    ).foreground
                  : AppUi.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppUi.buttonHeightLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppUi.spacingLg),
          child: Row(
            children: [
              Icon(icon, size: AppUi.iconMd, color: AppUi.brandOf(context)),
              const SizedBox(width: AppUi.spacingMd),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppUi.textSecondaryOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One bordered card holding the quick actions as full-width rows, so labels
/// never wrap into uneven tiles.
class _QuickActionList extends StatelessWidget {
  final List<_QuickAction> children;

  const _QuickActionList({required this.children});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: AppUi.spacingLg + AppUi.iconMd + AppUi.spacingMd,
                color: AppUi.dividerOf(context),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Station availability: the status the customers see, the open/closed
/// switch, and the less common states (busy, maintenance) in a menu.
class _StationStatusCard extends StatelessWidget {
  final String availability;
  final int totalRiders;
  final bool pricingSet;
  final ValueChanged<String> onChanged;

  const _StationStatusCard({
    required this.availability,
    required this.totalRiders,
    required this.pricingSet,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = AppUi.isDark(context);
    final isOpen = availability == 'open';
    final (tone, icon, title, subtitle) = switch (availability) {
      'open' => (
        StatusTone.success,
        Icons.storefront_rounded,
        'Open for orders',
        'Customers can place refill orders',
      ),
      'busy' => (
        StatusTone.warning,
        Icons.hourglass_top_rounded,
        'Busy',
        'Refill queue is full',
      ),
      'maintenance' => (
        StatusTone.danger,
        Icons.build_rounded,
        'Under maintenance',
        'Equipment servicing',
      ),
      _ => (
        StatusTone.neutral,
        Icons.storefront_outlined,
        'Closed',
        'Not accepting orders',
      ),
    };
    final style = StatusToneStyle.of(tone, isDark: isDark);
    final warn = StatusToneStyle.of(StatusTone.warning, isDark: isDark);
    final secondary = AppUi.textSecondaryOf(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: AppUi.controlRadius,
                  border: Border.all(color: style.border),
                ),
                child: Icon(icon, color: style.foreground, size: AppUi.iconLg),
              ),
              const SizedBox(width: AppUi.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Semantics(
                label: 'Accept orders',
                child: Switch.adaptive(
                  value: isOpen,
                  onChanged: (val) {
                    HapticFeedback.mediumImpact();
                    onChanged(val ? 'open' : 'closed');
                  },
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More status options',
                initialValue: availability,
                onSelected: onChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(value: 'busy', child: Text('Busy')),
                  PopupMenuItem(
                    value: 'maintenance',
                    child: Text('Maintenance'),
                  ),
                  PopupMenuItem(value: 'closed', child: Text('Closed')),
                ],
                icon: Icon(Icons.more_vert_rounded, color: secondary),
              ),
            ],
          ),
          const SizedBox(height: AppUi.spacingMd),
          Divider(height: 1, color: AppUi.dividerOf(context)),
          const SizedBox(height: AppUi.spacingMd),
          Wrap(
            spacing: AppUi.spacingLg,
            runSpacing: AppUi.spacingSm,
            children: [
              _MetaItem(
                icon: Icons.delivery_dining_outlined,
                label: '$totalRiders rider${totalRiders == 1 ? '' : 's'}',
                color: secondary,
              ),
              _MetaItem(
                icon: pricingSet
                    ? Icons.sell_outlined
                    : Icons.error_outline_rounded,
                label: pricingSet ? 'Pricing set' : 'Pricing missing',
                color: pricingSet ? secondary : warn.foreground,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppUi.iconSm, color: color),
        const SizedBox(width: AppUi.spacingXs + 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _OrderListItem extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback? onTap;

  const _OrderListItem({required this.order, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OrderCard(
        order: order,
        role: OrderCardRole.owner,
        isFullColor: true,
        onTap: onTap,
      ),
    );
  }
}

/// Top-of-dashboard call to action whenever orders are waiting for the
/// station to accept or decline — the owner's most time-sensitive job.
class _PendingOrdersCallout extends StatelessWidget {
  final int count;
  final VoidCallback? onReview;

  const _PendingOrdersCallout({required this.count, this.onReview});

  @override
  Widget build(BuildContext context) {
    final tone = StatusToneStyle.of(
      StatusTone.warning,
      isDark: AppUi.isDark(context),
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: AppUi.cardRadius,
          border: Border.all(color: tone.border),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_active_rounded, color: tone.foreground),
            const SizedBox(width: AppUi.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1
                        ? '1 order is waiting'
                        : '$count orders are waiting',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tone.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Accept or decline so customers know what to expect.',
                    style: TextStyle(fontSize: 13, color: tone.foreground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppUi.spacingSm),
            FilledButton(
              onPressed: onReview,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
  }
}
