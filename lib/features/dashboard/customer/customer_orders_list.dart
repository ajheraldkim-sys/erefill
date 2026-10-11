import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:erefill/models/cart_model.dart';
import '../../../core/routing/app_navigation.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/widgets/refill_components.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:erefill/core/utils/order_product_helpers.dart';
import '../../../core/services/offline_order_sync_service.dart';
import 'package:flutter/services.dart';

class CustomerOrdersList extends StatefulWidget {
  final VoidCallback? onNavigateToStations;
  const CustomerOrdersList({super.key, this.onNavigateToStations});

  @override
  State<CustomerOrdersList> createState() => _CustomerOrdersListState();
}

class _CustomerOrdersListState extends State<CustomerOrdersList> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _myOrders = [];
  bool _isLoading = true;
  RealtimeChannel? _ordersChannel;
  final Map<String, RealtimeChannel> _riderChannels = {};
  final Map<String, LatLng> _riderLocations = {};
  int _activeSegment = 0;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _subscribeToOrderChanges();
  }

  void _syncRiderLocationSubscriptions() {
    final activeRiderIds = _myOrders
        .where((order) => order['status'] == 'out_for_delivery')
        .map((order) => order['assigned_rider_id'])
        .whereType<String>()
        .toSet();

    for (final riderId in activeRiderIds) {
      if (!_riderChannels.containsKey(riderId)) {
        _subscribeToRiderLocation(riderId);
      }
    }

    final toRemove = _riderChannels.keys
        .where((id) => !activeRiderIds.contains(id))
        .toList();
    for (final riderId in toRemove) {
      final channel = _riderChannels.remove(riderId);
      if (channel != null) {
        supabase.removeChannel(channel);
      }
      _riderLocations.remove(riderId);
    }
  }

  void _subscribeToRiderLocation(String riderId) {
    final channel = supabase
        .channel('public:profiles:rider:$riderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: riderId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            final lat = (newRecord['latitude'] as num?)?.toDouble();
            final lng = (newRecord['longitude'] as num?)?.toDouble();
            if (lat == null || lng == null || !mounted) return;

            setState(() {
              _riderLocations[riderId] = LatLng(lat, lng);
            });
          },
        )
        .subscribe();

    _riderChannels[riderId] = channel;
  }

  @override
  void dispose() {
    if (_ordersChannel != null) {
      supabase.removeChannel(_ordersChannel!);
    }
    for (final channel in _riderChannels.values) {
      supabase.removeChannel(channel);
    }
    _riderChannels.clear();
    _riderLocations.clear();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final rows = await supabase
          .from('orders')
          .select('*, profiles:owner_id(station_name), order_items(*)')
          .eq('customer_id', userId)
          .order('created_at', ascending: false);

      final onlineOrders = List<Map<String, dynamic>>.from(rows);
      final offlineOrders =
          await OfflineOrderSyncService().getOfflineOrders();

      final onlineIds = onlineOrders.map((o) => o['id']).toSet();
      final pendingOffline = offlineOrders
          .where(
            (o) =>
                o['status'] == 'pending_sync' && !onlineIds.contains(o['id']),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _myOrders = [...pendingOffline, ...onlineOrders];
        _isLoading = false;
      });
      _syncRiderLocationSubscriptions();
    } catch (e) {
      debugPrint('Online orders fetch error, loading from local SQLite: $e');
      final offlineOrders =
          await OfflineOrderSyncService().getOfflineOrders();
      if (!mounted) return;
      setState(() {
        _myOrders = offlineOrders;
        _isLoading = false;
      });
    }
  }

  void _subscribeToOrderChanges() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _ordersChannel = supabase
        .channel('orders_list:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: userId,
          ),
          callback: (_) => _fetchOrders(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (_) => _fetchOrders(),
        )
        .subscribe();
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
      final productName = (raw['product_name'] ?? 'Purified Water refill')
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
            subtitle: 'Order tracking',
            actions: [
              SizedBox(
                width: 176,
                child: _buildSegmentControl(
                  activeOrders.length,
                  pastOrders.length,
                ),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppUi.bluePrimary,
              onRefresh: _fetchOrders,
              child: currentList.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.45,
                          child: _buildEmptyState(),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: AppUi.pagePadding.copyWith(top: 12, bottom: 96),
                      itemCount: currentList.length,
                      itemBuilder: (context, index) {
                        final order = currentList[index];
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
    return Row(
      children: [
        _segmentChip('Active', activeCount, 0),
        const SizedBox(width: 4),
        _segmentChip('History', historyCount, 1),
      ],
    );
  }

  Widget _segmentChip(String label, int count, int index) {
    final selected = _activeSegment == index;
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
        borderRadius: AppUi.pillRadius,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _activeSegment = index);
          },
          borderRadius: AppUi.pillRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppUi.bluePrimary : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppUi.bluePrimary.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: selected ? AppUi.bluePrimary : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
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
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final createdAtRaw = order['created_at']?.toString();
    final date = DateTime.tryParse(createdAtRaw ?? '') ?? DateTime.now();
    final statusLabel = OrderStatusPresentation.fromStatus(status).label;
    final isActive = _activeSegment == 0;

    if (isActive) {
      return ActiveOrderCard(
        order: order,
        statusLabel: statusLabel,
        onTap: () => _openOrder(order),
      );
    }

    return Material(
      color: AppUi.surfaceOf(context),
      borderRadius: AppUi.cardRadius,
      child: InkWell(
        onTap: () => _openOrder(order),
        borderRadius: AppUi.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppUi.cardDecorationOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppUi.blueSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.water_drop_rounded,
                      color: AppUi.bluePrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stationName, style: AppUi.sectionTitle),
                        const SizedBox(height: 3),
                        Text(
                          'Order #${order['id'].toString().substring(0, 8).toUpperCase()} · ${date.day}/${date.month}/${date.year}',
                          style: AppUi.captionText,
                        ),
                      ],
                    ),
                  ),
                  OrderStatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _buildOrderItemsString(order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppUi.captionText.copyWith(
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ),
                  Text(
                    '₱${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppUi.bluePrimary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              if (status != 'cancelled') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _handleBuyAgain(order);
                    },
                    icon: const Icon(Icons.replay_rounded, size: 16),
                    label: const Text('Reorder refill'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _buildOrderItemsString(Map<String, dynamic> order) {
    if ((order['order_items'] as List?)?.isNotEmpty ?? false) {
      final items = (order['order_items'] as List);
      return items
          .map((i) {
            final quantity = i['quantity'] ?? 1;
            final name = i['product_name'] ?? i['water_type'] ?? 'Water refill';
            return '${quantity}x $name';
          })
          .join(', ');
    }
    return '${order['quantity'] ?? 1}x ${order['water_type'] ?? 'Water refill'}';
  }

  Widget _buildEmptyState() {
    final isActive = _activeSegment == 0;
    return AxoEmptyState(
      pose: isActive ? AxoPose.thinking : AxoPose.happy,
      title: isActive ? 'No active refills' : 'No order history yet',
      message: isActive
          ? 'When you order water from a station, your active deliveries will show up here.'
          : 'Completed and cancelled orders will appear here after your first delivery.',
      actionLabel: isActive ? 'Find a station' : null,
      onAction: isActive
          ? (widget.onNavigateToStations ??
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Open the Stations tab to browse water refilling stations.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                })
          : null,
    );
  }
}
