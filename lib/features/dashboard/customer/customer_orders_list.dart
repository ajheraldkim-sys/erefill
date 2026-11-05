import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/models/cart_model.dart';
import '../../../core/routing/app_navigation.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/state_cards.dart';
import 'package:erefill/core/widgets/refill_components.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:erefill/core/utils/order_product_helpers.dart';
import '../../../core/services/offline_order_sync_service.dart';
import '../../../core/sync/realtime_hub.dart';
import '../../../core/sync/sync_resources.dart';
import '../../../core/sync/sync_store.dart';
import '../../../core/sync/synced_state.dart';
import 'package:flutter/services.dart';
import 'review_modal.dart';
import 'widgets/customer_orders_load_notice.dart';
import '../../subscriptions/widgets/customer_subscriptions_tab.dart';

class CustomerOrdersList extends StatefulWidget {
  final VoidCallback? onNavigateToStations;
  const CustomerOrdersList({super.key, this.onNavigateToStations});

  @override
  State<CustomerOrdersList> createState() => _CustomerOrdersListState();
}

class _CustomerOrdersListState extends State<CustomerOrdersList>
    with SyncedState {
  final supabase = Supabase.instance.client;

  /// Server orders, cache-first and kept live by the sync layer.
  SyncedResource<CustomerOrdersData>? _orders;

  /// Orders placed offline that the server has not received yet.
  List<Map<String, dynamic>> _queuedOrders = const [];
  StreamSubscription<int>? _queuedSub;
  final Map<String, StreamSubscription<RealtimeEvent>> _riderWatches = {};
  final Map<String, LatLng> _riderLocations = {};
  int _activeSegment = 0;

  List<Map<String, dynamic>> get _serverOrders =>
      _orders?.data?.orders ?? const [];

  Map<String, int> get _reviewedOrderRatings =>
      _orders?.data?.reviewRatings ?? const {};

  /// Queued orders first, then everything the server has.
  List<Map<String, dynamic>> get _myOrders {
    final serverIds = _serverOrders.map((o) => o['id']).toSet();
    return [
      ..._queuedOrders.where(
        (o) => o['status'] == 'pending_sync' && !serverIds.contains(o['id']),
      ),
      ..._serverOrders,
    ];
  }

  bool get _isLoading =>
      (_orders?.isLoading ?? false) && _queuedOrders.isEmpty;

  bool get _ordersFetchFailed => _orders?.lastRefreshFailed ?? false;

  @override
  void initState() {
    super.initState();
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      _orders = useSynced(SyncResources.customerOrders(userId))
        ..addListener(_syncRiderLocationSubscriptions);
      _syncRiderLocationSubscriptions();
    }
    _loadQueuedOrders();
    _queuedSub = OfflineOrderSyncService().onPendingCountChanged.listen(
      (_) => _loadQueuedOrders(),
    );
  }

  Future<void> _loadQueuedOrders() async {
    final queued = await OfflineOrderSyncService().getOfflineOrders();
    if (mounted) setState(() => _queuedOrders = queued);
  }

  Future<void> _fetchOrders() async {
    await Future.wait([
      if (_orders != null) _orders!.refresh(),
      _loadQueuedOrders(),
    ]);
  }

  void _syncRiderLocationSubscriptions() {
    final activeRiderIds = _serverOrders
        .where((order) => order['status'] == 'out_for_delivery')
        .map((order) => order['assigned_rider_id'])
        .whereType<String>()
        .toSet();

    for (final riderId in activeRiderIds) {
      _riderWatches.putIfAbsent(
        riderId,
        () => watchTable(
          TableWatch('profiles', column: 'id', value: riderId),
          (event) {
            final newRecord = event.payload?.newRecord;
            if (newRecord == null) return;
            final lat = (newRecord['latitude'] as num?)?.toDouble();
            final lng = (newRecord['longitude'] as num?)?.toDouble();
            if (lat == null || lng == null) return;
            setState(() => _riderLocations[riderId] = LatLng(lat, lng));
          },
        ),
      );
    }

    final toRemove = _riderWatches.keys
        .where((id) => !activeRiderIds.contains(id))
        .toList();
    for (final riderId in toRemove) {
      unwatchTable(_riderWatches.remove(riderId)!);
      _riderLocations.remove(riderId);
    }
  }

  @override
  void dispose() {
    _orders?.removeListener(_syncRiderLocationSubscriptions);
    _queuedSub?.cancel();
    super.dispose();
  }

  Future<void> _handleBuyAgain(Map<String, dynamic> order) async {
    final ownerId = order['owner_id']?.toString();
    final station = order['profiles'] as Map<String, dynamic>?;
    if (ownerId == null || station == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Station details unavailable for reorder.'),
        ),
      );
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final items = (order['order_items'] as List?) ?? const [];
    final validItems = items
        .whereType<Map<String, dynamic>>()
        .where((raw) => OrderProductHelpers.isValidProductId(raw['product_id']))
        .toList();

    if (validItems.isEmpty) {
      if (!mounted) return;
      context.openStationDetails({
        'id': ownerId,
        'station_name': station['station_name'] ?? 'Water Station',
        'is_open': true,
      });
      return;
    }

    cart.clearCart();

    for (final raw in validItems) {
      final productId = raw['product_id'].toString();
      final productName = (raw['product_name'] ?? 'Water refill')
          .toString();
      final price = ((raw['price_at_purchase'] as num?) ?? 0).toDouble();
      final qty = ((raw['quantity'] as num?) ?? 1).toInt();

      cart.addItem(productId, productName, price);
      if (qty > 1) {
        cart.updateQuantity(productId, qty);
      }
    }

    if (!mounted) return;
    context.openCheckout({
      'id': ownerId,
      'station_name': station['station_name'] ?? 'Unknown Station',
      'is_open': true,
    });
  }

  void _openOrder(Map<String, dynamic> order) {
    context.openOrderTracker(order);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(height: 96, borderRadius: 24),
                const SizedBox(height: 18),
                const Skeleton(width: 180, height: 20, borderRadius: 10),
                const SizedBox(height: 10),
                const Skeleton(width: 120, height: 14, borderRadius: 8),
                const SizedBox(height: 18),
                Expanded(
                  child: SkeletonList(
                    itemCount: 4,
                    itemDelegate: (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: CardSkeleton(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activeOrders = _myOrders
        .where((o) => o['status'] != 'delivered' && o['status'] != 'cancelled')
        .toList();
    final pastOrders = _myOrders
        .where((o) => o['status'] == 'delivered' || o['status'] == 'cancelled')
        .toList();
    final currentList = _activeSegment == 0 ? activeOrders : pastOrders;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'My refills',
            subtitle: 'Order tracking & routine',
            bottom: _buildSegmentControl(
              activeOrders.length,
              pastOrders.length,
            ),
          ),
          Expanded(
            child: _activeSegment == 2
                ? CustomerSubscriptionsTab(
                    onBrowseStations: widget.onNavigateToStations,
                  )
                : RefreshIndicator(
                    color: AppUi.bluePrimary,
                    onRefresh: _fetchOrders,
                    child: currentList.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: AppUi.pagePadding.copyWith(
                              top: 12,
                              bottom: 96,
                            ),
                            children: _ordersFetchFailed
                                ? [
                                    CustomerOrdersLoadNotice(
                                      hasSavedOrders: _myOrders.isNotEmpty,
                                      onRetry: _fetchOrders,
                                    ),
                                  ]
                                : [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.45,
                                      child: _buildEmptyState(),
                                    ),
                                  ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: AppUi.pagePadding.copyWith(
                              top: 12,
                              bottom: 96,
                            ),
                            itemCount:
                                currentList.length +
                                (_ordersFetchFailed ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_ordersFetchFailed && index == 0) {
                                return CustomerOrdersLoadNotice(
                                  hasSavedOrders: _myOrders.isNotEmpty,
                                  onRetry: _fetchOrders,
                                );
                              }
                              final order =
                                  currentList[index -
                                      (_ordersFetchFailed ? 1 : 0)];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildOrderCard(order),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentControl(int activeCount, int historyCount) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.08)
            : AppUi.lightSurfaceRaised,
        borderRadius: BorderRadius.circular(AppUi.radiusFull),
        border: Border.all(color: AppUi.borderOf(context), width: 0.8),
      ),
      child: Row(
        children: [
          _segmentChip('Active', activeCount, 0),
          const SizedBox(width: 4),
          _segmentChip('History', historyCount, 1),
          const SizedBox(width: 4),
          _segmentChip('Routine', null, 2),
        ],
      ),
    );
  }

  Widget _segmentChip(String label, int? count, int index) {
    final selected = _activeSegment == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: Material(
        color: selected
            ? (isDark ? AppUi.darkSurfaceRaised : Colors.white)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppUi.radiusFull),
        elevation: selected ? 1 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _activeSegment = index);
          },
          borderRadius: BorderRadius.circular(AppUi.radiusFull),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppUi.brandOf(context)
                        : (isDark ? Colors.white70 : AppUi.textSecondary),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppUi.brandSoftOf(context)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.06)),
                      borderRadius: BorderRadius.circular(AppUi.radiusFull),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: selected
                            ? AppUi.brandOf(context)
                            : (isDark ? Colors.white70 : AppUi.textSecondary),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = (order['status'] ?? 'pending').toString();
    final station = order['profiles'] as Map<String, dynamic>?;
    final stationName = station?['station_name'] ?? 'Water station';
    final statusLabel = OrderStatusPresentation.fromStatus(status).label;
    final isActive = _activeSegment == 0;

    if (isActive) {
      return ActiveOrderCard(
        order: order,
        statusLabel: statusLabel,
        onTap: () => _openOrder(order),
      );
    }

    Widget? bottomAction;
    if (status == 'delivered') {
      final orderIdStr = order['id']?.toString() ?? '';
      final reviewedRating = _reviewedOrderRatings[orderIdStr];

      if (reviewedRating != null) {
        bottomAction = Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    reviewedRating > 0 ? 'Rated $reviewedRating/5' : 'Reviewed',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _handleBuyAgain(order);
                },
                icon: const Icon(Icons.replay_rounded, size: 16),
                label: const Text('Reorder refill'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: OrderStatusColors.getColor('delivered'),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                ),
              ),
            ),
          ],
        );
      } else {
        bottomAction = Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ReviewModal.show(
                    context: context,
                    orderId: orderIdStr,
                    stationId: (order['owner_id'] ?? '').toString(),
                    stationName: stationName,
                    onReviewSubmitted: _fetchOrders,
                  );
                },
                icon: const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: AppColors.uiWarning,
                ),
                label: const Text('Rate refill'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppUi.textPrimary, // fixed-light: on a fixed white button
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _handleBuyAgain(order);
                },
                icon: const Icon(Icons.replay_rounded, size: 16),
                label: const Text('Reorder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: OrderStatusColors.getColor('delivered'),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                ),
              ),
            ),
          ],
        );
      }
    } else if (status != 'cancelled') {
      bottomAction = SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            HapticFeedback.lightImpact();
            _handleBuyAgain(order);
          },
          icon: const Icon(Icons.replay_rounded, size: 16),
          label: const Text('Reorder refill'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppUi.brandOf(context),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
            ),
          ),
        ),
      );
    }

    return OrderCard(
      order: order,
      role: OrderCardRole.customer,
      onTap: () => _openOrder(order),
      bottomAction: bottomAction,
    );
  }

  Widget _buildEmptyState() {
    final isActive = _activeSegment == 0;
    return EmptyStateCard(
      visual: isActive ? EmptyStateVisual.thinking : EmptyStateVisual.happy,
      title: isActive ? 'No active refills' : 'No order history yet',
      message: isActive
          ? 'When you order water from a station, your active deliveries will show up here.'
          : 'Completed and cancelled orders will appear here after your first delivery.',
      actionLabel: 'Find a station',
      onAction: widget.onNavigateToStations ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Open the Stations tab to browse water refilling stations.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
    );
  }
}
