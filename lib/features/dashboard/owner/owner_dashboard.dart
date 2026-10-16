import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/providers/notification_provider.dart';
import 'package:erefill/core/providers/user_provider.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/widgets/experience_widgets.dart';
import 'package:erefill/core/widgets/refill_components.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/widgets/notification_preview_sheet.dart';
import 'package:erefill/core/widgets/role_bottom_nav_bar.dart';
import 'package:erefill/core/widgets/lazy_indexed_stack.dart';
import 'order_management_screen.dart';
import 'riders_screen.dart';
import '../../chat/inbox_screen.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/models/system_notification.dart';
import 'owner_menu_screen.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/services/owner_inventory_service.dart';
import 'package:erefill/core/services/local_data_cache.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final supabase = Supabase.instance.client;
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

    _profileSub = SafeSupabase.listen(
      supabase
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', user.id),
      (data) {
        if (data.isNotEmpty && mounted) {
          setState(() {
            ownerProfile = data.first;
            _isOpen = ownerProfile?['is_open'] ?? true;
            _availability = ownerProfile?['station_availability']?.toString() ??
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
                (settings['base_delivery_fee'] as num?)?.toDouble() ?? _baseDeliveryFee;
            _pricePerGallon =
                (settings['price_per_gallon'] as num?)?.toDouble() ?? _pricePerGallon;
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
      final ridersResponse = await supabase
          .from('profiles')
          .select('id')
          .eq('role', 'rider')
          .eq('owner_id', user.id);

      final settingsResponse = await supabase
          .from('owner_settings')
          .select('base_delivery_fee, price_per_gallon')
          .eq('owner_id', user.id)
          .maybeSingle();

      final productResponse = await supabase
          .from('products')
          .select('id')
          .eq('owner_id', user.id)
          .eq('is_available', true)
          .gt('price', 0)
          .limit(1);

      if (!mounted) return;
      setState(() {
        _totalRiders = (ridersResponse as List).length;
        _baseDeliveryFee =
            (settingsResponse?['base_delivery_fee'] as num?)?.toDouble() ?? 0;
        _pricePerGallon =
            (settingsResponse?['price_per_gallon'] as num?)?.toDouble() ?? 0;
        _hasOrderableProduct = (productResponse as List).isNotEmpty;
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
    if (availability == 'open' && !_stationSetupReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete setup before opening the station.'),
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
    }
  }

  bool get _stationHasName =>
      ownerProfile?['station_name']?.toString().trim().isNotEmpty ?? false;

  bool get _stationHasLocation =>
      (ownerProfile?['latitude'] as num?) != null &&
      (ownerProfile?['longitude'] as num?) != null;

  bool get _stationHasTownBarangay =>
      (ownerProfile?['town']?.toString().trim().isNotEmpty ?? false) &&
      (ownerProfile?['barangay']?.toString().trim().isNotEmpty ?? false);

  bool get _stationHasPricing =>
      _pricePerGallon > 0 && _hasOrderableProduct;

  bool get _stationSetupReady =>
      _stationHasName &&
      _stationHasLocation &&
      _stationHasTownBarangay &&
      _stationHasPricing;

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
        hasLocationPin: _stationHasLocation,
        onAvailabilityChanged: _setStationAvailability,
        onViewOrders: () => _changeTab(1),
        onOpenInventory: () => context.openOwnerInventory(),
        onOpenAccount: () => _changeTab(4),
      ),
      const OrderManagementScreen(),
      RidersScreen(ownerId: _ownerId ?? ''),
      const InboxScreen(), // Use unified inbox
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
                  icon: Icons.delivery_dining_outlined,
                  activeIcon: Icons.delivery_dining_rounded,
                  label: 'Riders',
                ),
                RoleBottomNavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_rounded,
                  label: 'Messages',
                  badgeCount: notif.unreadChatCount,
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
  final bool hasLocationPin;
  final ValueChanged<String> onAvailabilityChanged;
  final VoidCallback onViewOrders;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenAccount;

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
    required this.hasLocationPin,
    required this.onAvailabilityChanged,
    required this.onViewOrders,
    required this.onOpenInventory,
    required this.onOpenAccount,
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
      final mem = LocalDataCache.instance.getMemory<Map<String, dynamic>>('owner_overview_${user.id}');
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
    int assignedCount = 0;
    int deliveringCount = 0;
    int deliveredTodayCount = 0;

    for (var o in data) {
      final rawCreated = o['created_at']?.toString();
      final dt = rawCreated != null
          ? DateTime.tryParse(rawCreated)?.toLocal()
          : null;
      final isToday = dt != null &&
          dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day;

      if (isToday) {
        todayOrdersCount++;
        todayRevenue += (o['total_amount'] ?? 0).toDouble();
      }

      final status = o['status'];
      if (status == 'pending') pendingCount++;
      if (status == 'accepted') acceptedCount++;
      if (status == 'preparing') preparingCount++;
      if (status == 'ready_for_pickup') readyCount++;
      if (status == 'assigned_to_rider') assignedCount++;
      if (status == 'out_for_delivery') deliveringCount++;
      if (status == 'delivered' && isToday) deliveredTodayCount++;
    }

    if (!_isFirstOrdersLoad && pendingCount > _previousPendingCount) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.bolt, color: Colors.amber),
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
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: widget.onViewOrders,
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF0077B6),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    _isFirstOrdersLoad = false;
    _previousPendingCount = pendingCount;

    List<Map<String, dynamic>> enrichedRecent = [];
    try {
      final res = await supabase
          .from('orders')
          .select(
            '*, profiles!orders_customer_id_fkey(full_name, avatar_url)',
          )
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
        final status = o['status']?.toString();

        ordersTrend7Days[dayOffset] += 1;
        if (status != 'cancelled') {
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

    final double calculatedWeeklyRevenue =
        revenueTrend7Days.fold<double>(0.0, (sum, val) => sum + val);
    final int calculatedWeeklyOrders =
        ordersTrend7Days.fold<int>(0, (sum, val) => sum + val.toInt());

    if (mounted) {
      setState(() {
        _stats = {
          'ordersToday': todayOrdersCount,
          'revenueToday': todayRevenue,
          'pending': pendingCount,
          'accepted': acceptedCount,
          'preparing': preparingCount,
          'ready': readyCount,
          'assigned': assignedCount,
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

  String _formatCurrency(double amount) {
    return '₱${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  List<double> _parseTrend(dynamic rawTrend) {
    if (rawTrend is! List) {
      return const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    }
    try {
      final list = rawTrend
          .map((e) => (e as num?)?.toDouble() ?? 0.0)
          .toList(growable: false);
      return list.length >= 2 ? list : const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    } catch (_) {
      return const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    }
  }

  Widget _buildInventoryCard() {
    final inventory = _inventory;
    return Material(
      color: AppUi.surfaceOf(context),
      borderRadius: AppUi.cardRadius,
      child: InkWell(
        onTap: widget.onOpenInventory,
        borderRadius: AppUi.cardRadius,
        child: Container(
          width: double.infinity,
          padding: AppUi.cardPaddingLoose,
          decoration: AppUi.cardDecorationOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Inventory & containers',
                      style: AppUi.sectionTitle.copyWith(fontSize: 16),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppUi.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (inventory == null)
                Text(
                  'Loading stock levels…',
                  style: TextStyle(color: AppUi.textSecondaryOf(context)),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _inventoryStat(
                        'Filled',
                        '${inventory.filledGallons} gal',
                        inventory.hasLowFilledStock,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _inventoryStat(
                        'Empty',
                        '${inventory.emptyGallons} gal',
                        false,
                      ),
                    ),
                  ],
                ),
                if (inventory.hasLowFilledStock) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Low filled stock — restock before peak hours.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _inventoryStat(String label, String value, bool warning) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppUi.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppUi.captionText),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: warning
                  ? Colors.orange.shade800
                  : AppUi.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidedSetupCard() {
    return GuidedSetupCard(
      role: ExperienceRole.owner,
      title: widget.setupReady ? 'Station is ready' : 'Station setup guide',
      message: widget.setupReady
          ? 'You can accept orders, assign riders, and monitor stock from this dashboard.'
          : 'Complete these basics so customers see accurate prices and delivery details.',
      actionLabel: widget.setupReady ? null : 'Continue setup',
      onAction: widget.setupReady ? null : widget.onOpenAccount,
      steps: [
        ExperienceStep(
          label: 'Station profile',
          helper: 'Name and public details customers recognize.',
          isComplete:
              widget.stationName != null &&
              widget.stationName!.trim().isNotEmpty,
          onTap: widget.onOpenAccount,
        ),
        ExperienceStep(
          label: 'Location pin',
          helper: 'Helps customers and riders find your station.',
          isComplete: widget.hasLocationPin,
          onTap: widget.onOpenAccount,
        ),
        ExperienceStep(
          label: 'Town and barangay',
          helper: 'Keeps station discovery local and accurate.',
          isComplete:
              (widget.town?.trim().isNotEmpty ?? false) &&
              (widget.barangay?.trim().isNotEmpty ?? false),
          onTap: widget.onOpenAccount,
        ),
        ExperienceStep(
          label: 'Pricing and refill product',
          helper: 'Required before accepting customer orders.',
          isComplete:
              widget.baseDeliveryFee > 0 &&
              widget.pricePerGallon > 0 &&
              widget.hasOrderableProduct,
          onTap: () => context.openOwnerServiceCatalog(),
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
                        const Icon(
                          Icons.campaign_rounded,
                          color: AppUi.bluePrimary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Flash Broadcast',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppUi.textPrimaryOf(context),
                            letterSpacing: 0,
                          ),
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
                      decoration: AppUi.fieldDecoration(
                        'Alert Title',
                        prefixIcon: const Icon(Icons.label_outline_rounded),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: messageController,
                      maxLines: 4,
                      maxLength: 160,
                      decoration: AppUi.fieldDecoration(
                        'Type your message...',
                        prefixIcon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                        ),
                      ).copyWith(alignLabelWithHint: true),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
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
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  setState(() => isSending = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppUi.bluePrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppUi.pillRadius,
                          ),
                          elevation: 0,
                        ),
                        child: isSending
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              )
                            : const Text(
                                'Send to all riders',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0,
                                ),
                              ),
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

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          OwnerHeroHeader(
            stationName: widget.stationName ?? 'Water Station',
            location: location.isEmpty ? 'Set your location' : location,
            availability: widget.availability,
            onNotificationTap: () => showNotificationPreviewSheet(
              context,
              onViewAll: () => context.openNotifications(),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _ordersSub?.cancel();
                _setupOrdersListener();
                await _loadInventorySnapshot();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: AppUi.pagePaddingLoose.copyWith(
                      top: AppUi.spacingMd,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (!widget.setupReady)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppUi.spacingLg,
                            ),
                            child: FriendlyFeedbackBanner(
                              title: 'Finish setup before opening',
                              message:
                                  'Customers can order confidently once your profile, location, and pricing are complete.',
                              icon: Icons.lightbulb_outline_rounded,
                              color: AppColors.uiWarning,
                              actionLabel: 'Open account setup',
                              onAction: widget.onOpenAccount,
                            ),
                          ),

                        Container(
                          width: double.infinity,
                          padding: AppUi.cardPaddingLoose,
                          decoration: AppUi.cardDecorationOf(context),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppUi.bluePrimary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: AppUi.cardRadius,
                                ),
                                child: const Icon(
                                  Icons.water_drop_rounded,
                                  color: AppUi.bluePrimary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Station status',
                                      style: AppUi.sectionTitle.copyWith(
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${widget.totalRiders} riders · Pricing ${widget.baseDeliveryFee > 0 && widget.pricePerGallon > 0 && widget.hasOrderableProduct ? 'set' : 'missing'}',
                                      style: AppUi.captionText,
                                    ),
                                  ],
                                ),
                              ),
                              _buildStationSwitch(),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppUi.spacingLg),

                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DashboardStatCard(
                                    label: "Today's revenue",
                                    value: _formatCurrency(
                                      (_stats['revenueToday'] as num?)?.toDouble() ?? 0.0,
                                    ),
                                    icon: Icons.payments_outlined,
                                    color: AppUi.bluePrimary,
                                    delta: '+12%',
                                    trend: _parseTrend(_stats['revenueTrend']),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DashboardStatCard(
                                    label: "Today's orders",
                                    value: '${_stats['ordersToday'] ?? 0}',
                                    icon: Icons.water_drop_outlined,
                                    color: const Color(0xFFF59E0B),
                                    delta: '+8%',
                                    trend: _parseTrend(_stats['ordersTrend']),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Pending',
                                    value: '${_stats['pending'] ?? 0}',
                                    icon: Icons.schedule_rounded,
                                    color: AppUi.accentCyan,
                                    onTap: widget.onViewOrders,
                                    delta: ((_stats['pending'] as num?)?.toInt() ?? 0) > 0 ? 'Active' : 'Clear',
                                    trend: _parseTrend(_stats['pendingTrend']),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Delivered today',
                                    value: '${_stats['delivered'] ?? 0}',
                                    icon: Icons.check_circle_outline_rounded,
                                    color: AppUi.accentGreen,
                                    delta: '+15%',
                                    trend: _parseTrend(_stats['deliveredTrend']),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: AppUi.spacingLg),

                        _buildInventoryCard(),

                        const SizedBox(height: AppUi.spacingMd),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _showBroadcastBottomSheet(context),
                                icon: const Icon(
                                  Icons.campaign_outlined,
                                  size: 18,
                                ),
                                label: const Text('Flash alert'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppUi.bluePrimary,
                                  side: BorderSide(
                                    color: AppUi.borderOf(context),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppUi.controlRadius,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    context.openOwnerServiceCatalog(),
                                icon: const Icon(
                                  Icons.water_drop_outlined,
                                  size: 18,
                                ),
                                label: const Text('Water catalog'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppUi.textPrimaryOf(context),
                                  side: BorderSide(
                                    color: AppUi.borderOf(context),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppUi.controlRadius,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => {},
                            icon: const Icon(
                              Icons.receipt_long_outlined,
                              size: 18,
                              color: Color(0xFFF59E0B),
                            ),
                            label: const Text(
                              'Customer Credits & Utang Ledger',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppUi.textPrimaryOf(context),
                              side: BorderSide(color: AppUi.borderOf(context)),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppUi.controlRadius,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),

                        const SizedBox(height: AppUi.spacingLg),
                        _buildGuidedSetupCard(),
                        const SizedBox(height: AppUi.spacingLg),

                        const Text(
                          'Live refill orders',
                          style: AppUi.sectionTitle,
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildLogisticsChip(
                                'Pending',
                                (_stats['pending'] as num?)?.toInt() ?? 0,
                                OrderStatusColors.getColor('pending'),
                              ),
                              const SizedBox(width: 8),
                              _buildLogisticsChip(
                                'Preparing',
                                (_stats['preparing'] as num?)?.toInt() ?? 0,
                                OrderStatusColors.getColor('preparing'),
                              ),
                              const SizedBox(width: 8),
                              _buildLogisticsChip(
                                'Ready',
                                (_stats['ready'] as num?)?.toInt() ?? 0,
                                OrderStatusColors.getColor('ready_for_pickup'),
                              ),
                              const SizedBox(width: 8),
                              _buildLogisticsChip(
                                'Delivering',
                                (_stats['delivering'] as num?)?.toInt() ?? 0,
                                OrderStatusColors.getColor('out_for_delivery'),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppUi.spacingLg),
                        AxoTipCard(
                          title: 'Peak hours tip',
                          message:
                              'Most refill orders come between 8 AM and 11 AM. Keep riders ready during peak hours.',
                          trailingIcon: Icons.insights_rounded,
                        ),

                        const SizedBox(height: AppUi.spacingLg),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Recent orders',
                              style: AppUi.sectionTitle,
                            ),
                            TextButton(
                              onPressed: widget.onViewOrders,
                              child: const Text('View all'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_recentOrders.isEmpty)
                          AxoEmptyState(
                            pose: AxoPose.empty,
                            title: 'No orders yet today',
                            message:
                                'When customers place refill orders, they will appear here instantly.',
                            compact: true,
                          )
                        else
                          ..._recentOrders.map(
                            (o) => _OrderListItem(
                              order: o,
                              onTap: widget.onViewOrders,
                            ),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogisticsChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppUi.cardRadius,
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationSwitch() {
    return _buildStatusToggle();
  }

  Widget _buildStatusToggle() {
    return PopupMenuButton<String>(
      tooltip: 'Set station availability',
      initialValue: widget.availability,
      onSelected: widget.onAvailabilityChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'open', child: Text('Open')),
        PopupMenuItem(value: 'busy', child: Text('Busy')),
        PopupMenuItem(value: 'maintenance', child: Text('Maintenance')),
        PopupMenuItem(value: 'closed', child: Text('Closed')),
      ],
      child: Container(
        margin: const EdgeInsets.only(left: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppUi.blueSoft,
          borderRadius: AppUi.controlRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded, size: 18, color: AppUi.bluePrimary),
            const SizedBox(width: 6),
            Text(
              widget.availability.replaceAll('_', ' '),
              style: const TextStyle(
                color: AppUi.bluePrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
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
