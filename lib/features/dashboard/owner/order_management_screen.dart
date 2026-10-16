import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/providers/notification_provider.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'add_order_dialog.dart';
import '../customer/checkout_rules.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/services/local_data_cache.dart';
import 'package:uuid/uuid.dart';
import 'package:erefill/core/services/offline_queue_service.dart';
import 'package:erefill/core/widgets/press_bounce.dart';
import 'package:erefill/core/utils/app_haptics.dart';
import 'owner_order_queue.dart';

class OrderManagementScreen extends StatefulWidget {
  const OrderManagementScreen({super.key});

  @override
  State<OrderManagementScreen> createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  bool _isAssigning = false;
  bool _isKanbanView = false;
  List<Map<String, dynamic>> _riders = [];
  String _selectedStatus = 'all';
  String _searchQuery = '';
  late TabController _tabController;
  RealtimeChannel? _ordersChannel;

  // New: Reactive order list state
  StreamController<List<Map<String, dynamic>>>? _ordersStreamController;
  List<Map<String, dynamic>>? _cachedOrders;
  Timer? _pollingTimer;
  bool _isRefreshingOrders = false;
  String? _ordersLoadError;

  static const List<String> _statusFilters = [
    'all',
    'pending',
    'in_prep',
    'dispatched',
  ];

  static const Map<String, String> _statusLabels = {
    'all': 'All',
    'pending': 'Pending',
    'in_prep': 'In Prep',
    'dispatched': 'Dispatched',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusFilters.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedStatus = _statusFilters[_tabController.index]);
      }
    });

    final ownerId = supabase.auth.currentUser?.id;
    if (ownerId != null) {
      final cached = LocalDataCache.instance.getMemory<List<dynamic>>(
        'owner_orders_$ownerId',
      );
      if (cached != null && cached.isNotEmpty) {
        _cachedOrders = cached
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    }

    _loadRiders();
    _loadDiskCache();
    _initOrdersStream();
  }

  Future<void> _loadDiskCache() async {
    final ownerId = supabase.auth.currentUser?.id;
    if (ownerId == null) return;
    final cached = await LocalDataCache.instance.get<List<dynamic>>(
      'owner_orders_$ownerId',
    );
    if (cached != null && cached.isNotEmpty && mounted) {
      final list = cached
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _cachedOrders = list;
      if (_ordersStreamController != null &&
          !_ordersStreamController!.isClosed) {
        _ordersStreamController!.add(list);
      }
      setState(() {});
    }
  }

  void _initOrdersStream() {
    _ordersStreamController =
        StreamController<List<Map<String, dynamic>>>.broadcast();
    _refreshOrders();
    _subscribeToOrders();
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshOrders();
    });
  }

  Future<void> _refreshOrders() async {
    final ownerId = supabase.auth.currentUser?.id;
    if (ownerId == null || _isRefreshingOrders) return;

    _isRefreshingOrders = true;
    if (mounted) setState(() {});
    try {
      final data = await _fetchOrdersWithCustomers(ownerId);
      _cachedOrders = data;
      _ordersLoadError = null;
      if (mounted) {
        if (_ordersStreamController != null &&
            !_ordersStreamController!.isClosed) {
          _ordersStreamController!.add(data);
        }
        setState(() {});
      }
      LocalDataCache.instance.set('owner_orders_$ownerId', data);
      LocalDataCache.instance.invalidate('owner_overview_$ownerId');
    } catch (error) {
      debugPrint('Error refreshing owner orders: $error');
      _ordersLoadError = FriendlyErrors.message(
        error,
        fallback: 'Could not refresh orders. Check your connection and retry.',
      );
      if (mounted) setState(() {});
    } finally {
      _isRefreshingOrders = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pollingTimer?.cancel();
    if (_ordersChannel != null) supabase.removeChannel(_ordersChannel!);
    _ordersStreamController?.close();
    super.dispose();
  }

  void _subscribeToOrders() {
    final ownerId = supabase.auth.currentUser?.id;
    if (ownerId == null) return;

    if (_ordersChannel != null) {
      supabase.removeChannel(_ordersChannel!);
      _ordersChannel = null;
    }

    _ordersChannel = supabase
        .channel('order_mgmt_updates:$ownerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            debugPrint('Order updated via Realtime: ${payload.eventType}');
            final record = payload.newRecord;
            final recordOwnerId = record['owner_id']?.toString();
            if (recordOwnerId != null && recordOwnerId != ownerId) {
              return;
            }

            if (payload.eventType == PostgresChangeEvent.insert) {
              AppHaptics.orderAlert();
              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.bolt, color: Colors.amber),
                        SizedBox(width: 8),
                        Text('New incoming refill order received!'),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Color(0xFF0077B6),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            }
            _refreshOrders();
          },
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

  bool _matchesOrderSearch(Map<String, dynamic> order) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final customer = order['customer'] as Map<String, dynamic>?;
    final values = [
      order['id'],
      order['customer_name'],
      order['customer_phone'],
      order['customer_address'],
      customer?['full_name'],
      customer?['phone'],
      customer?['complete_address'],
      order['status'],
      order['payment_method'],
    ];

    return values
        .whereType<Object>()
        .map((value) => value.toString().toLowerCase())
        .any((value) => value.contains(query));
  }

  Future<void> _loadRiders() async {
    final ownerId = supabase.auth.currentUser?.id;
    if (ownerId == null) return;
    try {
      final ridersData = await supabase
          .from('profiles')
          .select('id, full_name, username, reliability_score, flagged_count')
          .eq('owner_id', ownerId)
          .eq('role', 'rider')
          .order('reliability_score', ascending: false);
      if (!mounted) return;
      setState(() {
        _riders = List<Map<String, dynamic>>.from(ridersData);
      });
    } catch (e) {
      debugPrint('Error loading riders: $e');
    }
  }

  // ─── Formatters ───────────────────────────────────────────────────────────

  String _formatPeso(dynamic value) {
    final numVal = value is num ? value : num.tryParse('${value ?? 0}') ?? 0;
    return '₱${numVal.toStringAsFixed(2)}';
  }

  String _formatStatus(dynamic status) {
    final raw = (status ?? 'pending').toString();
    return _statusLabels[raw] ??
        raw
            .split('_')
            .map(
              (s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}',
            )
            .join(' ');
  }

  String _shortOrderId(String orderId) => orderId.length > 8
      ? '#${orderId.substring(0, 8).toUpperCase()}'
      : '#${orderId.toUpperCase()}';

  String _elapsedLabel(dynamic createdAt) {
    final dt = SafeParse.dateTime(createdAt);
    if (dt == null) return 'recent';

    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _statusColor(String status) {
    return OrderStatusColors.getColor(status);
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _assignRider({
    required String orderId,
    required String riderId,
    required String riderName,
  }) async {
    if (_isAssigning) return;
    HapticFeedback.mediumImpact();
    setState(() => _isAssigning = true);
    try {
      final success =
          await supabase.rpc(
                'assign_rider_safely',
                params: {'p_order_id': orderId, 'p_rider_id': riderId},
              )
              as bool;

      if (!success) {
        final reason = await _getRiderAssignmentFailureReason(
          orderId: orderId,
          riderId: riderId,
        );
        await _refreshOrders();
        throw Exception('$reason Orders were refreshed.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$riderName assigned successfully'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );
      await _refreshOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign rider: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  Future<String> _getRiderAssignmentFailureReason({
    required String orderId,
    required String riderId,
  }) async {
    final ownerId = supabase.auth.currentUser?.id;
    if (ownerId == null) {
      return 'Your owner session has expired. Sign in again.';
    }

    final order = await supabase
        .from('orders')
        .select('status, assigned_rider_id')
        .eq('id', orderId)
        .eq('owner_id', ownerId)
        .maybeSingle();

    if (order == null) {
      return 'This order is no longer available to your station.';
    }

    final assignedRiderId = order['assigned_rider_id']?.toString();
    if (assignedRiderId != null && assignedRiderId.isNotEmpty) {
      return 'This order has already been assigned to another rider.';
    }

    final status = (order['status'] ?? 'unknown').toString();
    if (status != 'ready_for_pickup') {
      return 'This order is now ${_formatStatus(status)}; rider assignment '
          'is only available when it is Ready for Pickup.';
    }

    final rider = await supabase
        .from('profiles')
        .select('role, owner_id')
        .eq('id', riderId)
        .maybeSingle();
    if (rider == null ||
        rider['role'] != 'rider' ||
        rider['owner_id']?.toString() != ownerId) {
      return 'The selected rider is no longer assigned to your station.';
    }

    return 'The assignment was rejected although the order and rider still '
        'appear eligible. Apply the latest remote_catchup.sql database changes '
        'in Supabase, then retry.';
  }

  Future<void> _updateStatus(
    String orderId,
    String newStatus, {
    String? cancelReason,
  }) async {
    HapticFeedback.lightImpact();
    Map<String, dynamic>? originalOrder;

    // Optimistically update local state for instant UI response
    if (_cachedOrders != null) {
      final index = _cachedOrders!.indexWhere(
        (o) => o['id']?.toString() == orderId,
      );
      if (index != -1) {
        final updatedList = List<Map<String, dynamic>>.from(_cachedOrders!);
        originalOrder = Map<String, dynamic>.from(updatedList[index]);
        final updatedOrder = Map<String, dynamic>.from(updatedList[index]);
        updatedOrder['status'] = newStatus;
        if (cancelReason != null && cancelReason.isNotEmpty) {
          updatedOrder['notes'] = 'Declined: $cancelReason';
        }
        updatedList[index] = updatedOrder;
        _cachedOrders = updatedList;
        _ordersStreamController?.add(updatedList);
        if (mounted) setState(() {});
      }
    }

    try {
      context.read<NotificationProvider>().acknowledgeOrder(orderId);
    } catch (_) {}

    try {
      final result = await SafeSupabase.transitionOrderStatus(
        orderId: orderId,
        newStatus: newStatus,
        reason: cancelReason,
      );
      if (result['success'] != true) {
        throw StateError(
          result['message']?.toString() ?? 'Order status update was rejected.',
        );
      }
      if (cancelReason != null && cancelReason.isNotEmpty) {
        try {
          await supabase
              .from('orders')
              .update({'notes': 'Declined: $cancelReason'})
              .eq('id', orderId);
        } catch (error) {
          debugPrint('Could not save order cancellation reason: $error');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to ${_formatStatus(newStatus)}'),
          backgroundColor: _statusColor(newStatus),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );
      await _refreshOrders();
    } catch (e) {
      debugPrint('Error updating order status: $e');
      final errStr = e.toString().toLowerCase();
      final isOffline =
          errStr.contains('socket') ||
          errStr.contains('network') ||
          errStr.contains('timeout') ||
          errStr.contains('connection') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('clientexception');
      if (isOffline) {
        try {
          await OfflineQueueService.queueAction(
            OfflineAction(
              id: const Uuid().v4(),
              actionType: 'UPDATE_ORDER_STATUS',
              payload: {
                'order_id': orderId,
                'new_status': newStatus,
                if (cancelReason != null && cancelReason.isNotEmpty)
                  'reason': cancelReason,
              },
            ),
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Status updated locally. Changes will sync once connected.',
              ),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(12),
            ),
          );
          return;
        } catch (queueErr) {
          debugPrint('Error queueing offline status transition: $queueErr');
        }
      }

      _restoreOptimisticOrder(orderId, originalOrder);
      await _refreshOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FriendlyErrors.message(
              e,
              fallback: 'Could not update this order status. Please try again.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _restoreOptimisticOrder(
    String orderId,
    Map<String, dynamic>? originalOrder,
  ) {
    final orders = _cachedOrders;
    if (orders == null || originalOrder == null) return;

    final index = orders.indexWhere(
      (order) => order['id']?.toString() == orderId,
    );
    if (index == -1) return;

    final restored = List<Map<String, dynamic>>.from(orders)
      ..[index] = originalOrder;
    _cachedOrders = restored;
    if (_ordersStreamController != null && !_ordersStreamController!.isClosed) {
      _ordersStreamController!.add(restored);
    }
    if (mounted) setState(() {});
  }

  Future<void> _showDeclineOrderDialog(String orderId) async {
    String selectedReason = 'Out of stock';
    final customReasonController = TextEditingController();
    final reasons = [
      'Out of stock',
      'Outside delivery area',
      'No riders available currently',
      'Station closing early',
      'Customer requested cancellation',
      'Other reason',
    ];

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppUi.dialogRadius),
          title: const Row(
            children: [
              Icon(Icons.cancel_outlined, color: AppUi.error),
              SizedBox(width: 8),
              Text(
                'Decline / Cancel Order',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a reason for declining or cancelling this order:',
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 12),
                ...reasons.map((r) {
                  final isSelected = selectedReason == r;
                  return InkWell(
                    onTap: () => setDialogState(() => selectedReason = r),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 20,
                            color: isSelected
                                ? AppUi.bluePrimary
                                : AppUi.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppUi.textPrimary
                                    : AppUi.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (selectedReason == 'Other reason') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customReasonController,
                    decoration: const InputDecoration(
                      hintText: 'Enter specific reason...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Keep Order'),
            ),
            FilledButton(
              onPressed: () {
                final chosen =
                    selectedReason == 'Other reason' &&
                        customReasonController.text.trim().isNotEmpty
                    ? customReasonController.text.trim()
                    : selectedReason;
                Navigator.pop(ctx, chosen);
              },
              style: FilledButton.styleFrom(backgroundColor: AppUi.error),
              child: const Text('Decline Order'),
            ),
          ],
        ),
      ),
    );

    if (reason != null) {
      await _updateStatus(orderId, 'cancelled', cancelReason: reason);
    }
  }

  // ─── Fetch refill details ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchOrderItems(String orderId) async {
    final res = await supabase
        .from('order_items')
        .select('product_name, quantity, price_at_purchase, subtotal')
        .eq('order_id', orderId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  void _openAddOrderDialog() {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AddOrderDialog(
        ownerId: myId,
        riders: _riders,
        onOrderAdded: () {
          _refreshOrders();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Manual refill order recorded successfully!'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        },
      ),
    );
  }

  // ─── Bottom Sheet Detail ──────────────────────────────────────────────────

  void _showOrderDetail(Map<String, dynamic> order) {
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isNotEmpty && order['owner_acknowledged_at'] == null) {
      order['owner_acknowledged_at'] = DateTime.now().toIso8601String();
      try {
        context.read<NotificationProvider>().acknowledgeOrder(orderId);
      } catch (e) {
        debugPrint('Error triggering acknowledgeOrder in details: $e');
      }
    }
    final rawStatus = (order['status'] ?? 'pending').toString();
    final assignedRiderId = order['assigned_rider_id'];

    // Snapshot-based fields for absolute precision
    final customerName = order['customer_name'] ?? 'Guest Customer';
    final address = order['customer_address'] ?? 'Station Pickup';
    final barangay = order['customer_barangay'] ?? '';
    final landmark = order['customer_landmark'] ?? '';
    final phone = order['customer_phone'] ?? 'No phone';

    final payment = (order['payment_method'] ?? 'COD').toString().toUpperCase();
    final elapsed = _elapsedLabel(order['created_at']);
    final total = _formatPeso(order['total_amount']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              borderRadius: AppUi.radiusSheetTop,
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: AppUi.borderOf(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppUi.screenPaddingWide,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _shortOrderId(orderId),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                color: AppUi.textPrimaryOf(context),
                              ),
                            ),
                            AppUi.vGapXs,
                            Row(
                              children: [
                                Text(
                                  '$elapsed • $payment',
                                  style: TextStyle(
                                    color: AppUi.textSecondaryOf(context),
                                    fontSize: 13,
                                  ),
                                ),
                                // Urgency Logic (Step 5)
                                if (rawStatus == 'pending' &&
                                    elapsed.contains('m') &&
                                    int.tryParse(elapsed.split('m').first)! >
                                        10)
                                  Container(
                                    margin: const EdgeInsets.only(
                                      left: AppUi.spacingSm,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'SLA breach',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _statusBadge(rawStatus),
                    ],
                  ),
                ),

                AppUi.vGapLg,
                Divider(
                  height: 1,
                  indent: AppUi.screenPaddingWide,
                  endIndent: AppUi.screenPaddingWide,
                  color: AppUi.dividerOf(context),
                ),

                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: AppUi.pagePaddingLoose,
                    children: [
                      // Customer info
                      _detailSection(
                        icon: Icons.person,
                        title: 'Customer',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: AppUi.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phone,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppUi.bluePrimary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      _detailSection(
                        icon: Icons.location_on,
                        title: 'Delivery Address',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              address,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppUi.textPrimaryOf(context),
                              ),
                            ),
                            if (barangay.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Brgy. $barangay',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppUi.textPrimaryOf(context),
                                ),
                              ),
                            ],
                            if (landmark.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppUi.blueSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.assistant_direction_rounded,
                                      size: 16,
                                      color: AppUi.bluePrimary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        landmark,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: AppUi.bluePrimaryDark,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Refill details
                      _detailSection(
                        icon: Icons.water_drop,
                        title: 'Refill Details',
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: _fetchOrderItems(orderId),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const LinearProgressIndicator();
                            }
                            final items = snapshot.data ?? [];
                            if (items.isEmpty) {
                              return const Text('No refill details found');
                            }
                            return Column(
                              children: items.map((item) {
                                final quantity = item['quantity'] ?? 1;
                                final name =
                                    item['product_name'] ??
                                    item['water_type'] ??
                                    'Water refill';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: AppUi.blueSoft,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.water_drop,
                                          size: 14,
                                          color: AppUi.bluePrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '$quantity× $name',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatPeso(item['subtotal']),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AppUi.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                      if (rawStatus == 'delivered') ...[
                        const SizedBox(height: 16),
                        _detailSection(
                          icon: Icons.recycling_rounded,
                          title: 'Empty containers',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${(order['empty_gallons_returned'] as num?)?.toInt() ?? 0} gallon(s) returned',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: AppUi.textPrimary,
                                ),
                              ),
                              if ((order['delivery_note']?.toString().trim() ??
                                      '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  order['delivery_note'].toString(),
                                  style: const TextStyle(
                                    color: AppUi.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Total and Payment
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppUi.pageBgOf(context),
                          borderRadius: AppUi.cardRadius,
                          border: Border.all(color: AppUi.borderColor),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Amount',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppUi.textSecondary,
                                  ),
                                ),
                                Text(
                                  total,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    color: AppUi.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Payment Status',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppUi.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _buildPaymentDetailPill(order),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (CheckoutRules.isOnlinePayment(
                            order['payment_method']?.toString(),
                          ) &&
                          (order['payment_status'] ?? '')
                                  .toString()
                                  .toLowerCase() !=
                              'success' &&
                          (order['payment_status'] ?? '')
                                  .toString()
                                  .toLowerCase() !=
                              'paid') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFD97706),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  {
                                        'failed',
                                        'expired',
                                        'cancelled',
                                        'canceled',
                                      }.contains(
                                        (order['payment_status'] ?? '')
                                            .toString()
                                            .toLowerCase(),
                                      )
                                      ? 'Customer payment has failed. Do not fulfill this order.'
                                      : 'Online payment via $payment is awaiting confirmation. Please verify before dispatching.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // The assignment RPC only accepts orders ready for pickup.
                      if (rawStatus == 'ready_for_pickup' &&
                          assignedRiderId == null &&
                          _riders.isNotEmpty) ...[
                        const Text(
                          'Assign Rider',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppUi.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _riders.map((rider) {
                            final riderId = (rider['id'] ?? '').toString();
                            final riderName =
                                (rider['full_name'] ??
                                        rider['username'] ??
                                        'Rider')
                                    .toString();
                            return GestureDetector(
                              onTap: _isAssigning
                                  ? null
                                  : () async {
                                      Navigator.pop(context);
                                      await _assignRider(
                                        orderId: orderId,
                                        riderId: riderId,
                                        riderName: riderName,
                                      );
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppUi.bluePrimary,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppUi.bluePrimary.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.delivery_dining,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      riderName.split(' ').first,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Reliability Score Display
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.star_rounded,
                                            size: 10,
                                            color: Colors.amber,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            (rider['reliability_score'] ?? 5.0)
                                                .toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if ((rider['flagged_count'] ?? 0) > 0)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Tooltip(
                                          message: 'Flagged Activity',
                                          child: Icon(
                                            Icons.error_rounded,
                                            color: Colors.orangeAccent,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if ((rawStatus == 'accepted' ||
                              rawStatus == 'preparing' ||
                              rawStatus == 'ready_for_pickup') &&
                          assignedRiderId == null &&
                          _riders.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppUi.warningBg,
                            borderRadius: AppUi.controlRadius,
                          ),
                          child: const Text(
                            'Add an available rider before dispatching this delivery.',
                            style: TextStyle(
                              color: AppUi.warningFg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (assignedRiderId != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: AppUi.controlRadius,
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF10B981),
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Rider Assigned',
                                style: const TextStyle(
                                  color: Color(0xFF065F46),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Order Action Buttons
                      if (rawStatus == 'pending') ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showDeclineOrderDialog(orderId);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppUi.error,
                                  side: const BorderSide(color: AppUi.error),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppUi.cardRadius,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.cancel_outlined,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Decline',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _updateStatus(orderId, 'accepted');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _statusColor('accepted'),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppUi.cardRadius,
                                  ),
                                  elevation: 0,
                                ),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Accept Order',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ] else if (rawStatus == 'accepted') ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showDeclineOrderDialog(orderId);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppUi.error,
                                  side: const BorderSide(color: AppUi.error),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppUi.cardRadius,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.cancel_outlined,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _updateStatus(orderId, 'preparing');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _statusColor('preparing'),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppUi.cardRadius,
                                  ),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.arrow_forward, size: 18),
                                label: const Text(
                                  'Start Preparing',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ] else if (rawStatus == 'preparing') ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _updateStatus(orderId, 'ready_for_pickup');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _statusColor('ready_for_pickup'),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppUi.cardRadius,
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text(
                              'Mark Ready for Pickup',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
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

  // ─── Widgets ──────────────────────────────────────────────────────────────

  Widget _detailSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppUi.textMuted),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppUi.textMuted,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _statusBadge(String status) {
    return OrderStatusBadge(status: status, showIcon: true, uppercase: true);
  }

  Widget _buildPaymentStatusBadge(
    Map<String, dynamic> order, {
    bool onFullColor = false,
  }) {
    final method = (order['payment_method'] ?? 'cod').toString().toLowerCase();
    final status = (order['payment_status'] ?? 'pending')
        .toString()
        .toLowerCase();
    final orderStatus = (order['status'] ?? '').toString().toLowerCase();

    final isPaid = status == 'success' || status == 'paid';
    final isCod = method == 'cod' || method == 'cash';
    final isFailed = {
      'failed',
      'expired',
      'cancelled',
      'canceled',
    }.contains(status);

    if (onFullColor) {
      final String label;
      final IconData icon;
      final Color bg;
      final Color border;

      if (isPaid) {
        label = 'Paid (${CheckoutRules.paymentLabel(method)})';
        icon = Icons.check_circle_rounded;
        bg = Colors.white.withValues(alpha: 0.22);
        border = Colors.white.withValues(alpha: 0.35);
      } else if (isCod) {
        if (orderStatus == 'delivered') {
          label = 'Paid (COD)';
          icon = Icons.check_circle_rounded;
          bg = Colors.white.withValues(alpha: 0.22);
          border = Colors.white.withValues(alpha: 0.35);
        } else {
          label = 'COD • Collect';
          icon = Icons.payments_outlined;
          bg = Colors.black.withValues(alpha: 0.18);
          border = Colors.white.withValues(alpha: 0.25);
        }
      } else if (isFailed) {
        label = 'Payment Failed';
        icon = Icons.error_outline_rounded;
        bg = Colors.black.withValues(alpha: 0.3);
        border = const Color(0xFFFCA5A5).withValues(alpha: 0.5);
      } else {
        label = 'Awaiting ${CheckoutRules.paymentLabel(method)}';
        icon = Icons.schedule_rounded;
        bg = Colors.black.withValues(alpha: 0.18);
        border = Colors.white.withValues(alpha: 0.25);
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
    }

    if (isPaid) {
      return Text(
        'Paid (${CheckoutRules.paymentLabel(method)})',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Color(0xFF10B981),
          letterSpacing: 0.3,
        ),
      );
    }

    if (isCod) {
      if (orderStatus == 'delivered') {
        return const Text(
          'Paid (COD)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Color(0xFF10B981),
            letterSpacing: 0.3,
          ),
        );
      }
      return const Text(
        'COD • Collect',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Color(0xFFD97706),
          letterSpacing: 0.3,
        ),
      );
    }

    if (isFailed) {
      return const Text(
        'Payment Failed',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Color(0xFFEF4444),
          letterSpacing: 0.3,
        ),
      );
    }

    return Text(
      'Awaiting ${CheckoutRules.paymentLabel(method)}',
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: Color(0xFFF59E0B),
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildPaymentDetailPill(Map<String, dynamic> order) {
    final method = (order['payment_method'] ?? 'cod').toString().toLowerCase();
    final status = (order['payment_status'] ?? 'pending')
        .toString()
        .toLowerCase();
    final orderStatus = (order['status'] ?? '').toString().toLowerCase();

    final isPaid = status == 'success' || status == 'paid';
    final isCod = method == 'cod' || method == 'cash';
    final isFailed = {
      'failed',
      'expired',
      'cancelled',
      'canceled',
    }.contains(status);

    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final String label;

    if (isPaid) {
      bgColor = const Color(0xFFECFDF5);
      borderColor = const Color(0xFFA7F3D0);
      textColor = const Color(0xFF059669);
      label =
          'PAID ONLINE (${CheckoutRules.paymentLabel(method).toUpperCase()})';
    } else if (isCod) {
      if (orderStatus == 'delivered') {
        bgColor = const Color(0xFFECFDF5);
        borderColor = const Color(0xFFA7F3D0);
        textColor = const Color(0xFF059669);
        label = 'PAID (CASH ON DELIVERY)';
      } else {
        bgColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFDE68A);
        textColor = const Color(0xFFD97706);
        label = 'COLLECT CASH ON DELIVERY';
      }
    } else if (isFailed) {
      bgColor = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFECACA);
      textColor = const Color(0xFFDC2626);
      label = 'PAYMENT FAILED';
    } else {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFDE68A);
      textColor = const Color(0xFFD97706);
      label =
          'AWAITING PAYMENT (${CheckoutRules.paymentLabel(method).toUpperCase()})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.right,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: textColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = (order['id'] ?? '').toString();
    final rawStatus = (order['status'] ?? 'pending').toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = OrderStatusStyle.resolve(rawStatus, isDark: isDark);

    // Snapshot-based fields for flawless performance
    final customerName = order['customer_name'] ?? 'Guest Customer';
    final address = order['customer_address'] ?? 'Station Pickup';
    final barangay = order['customer_barangay'] ?? '';
    final landmark = order['customer_landmark'] ?? '';

    final total = _formatPeso(order['total_amount']);
    final elapsed = _elapsedLabel(order['created_at']);
    final payment = (order['payment_method'] ?? 'COD').toString().toUpperCase();

    final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '');
    final minutesAgo = createdAt != null
        ? DateTime.now().difference(createdAt).inMinutes
        : 0;
    final isSlaUrgent =
        (rawStatus == 'pending' || rawStatus == 'in_prep') && minutesAgo >= 15;

    return RepaintBoundary(
      child: PressBounce(
        onTap: () {
          HapticFeedback.selectionClick();
          _showOrderDetail(order);
        },
        pressedScale: 0.985,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: style.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: style.primaryColor.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Order ID chip + SLA + Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _shortOrderId(orderId),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (isSlaUrgent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.alarm_rounded,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${minutesAgo}m',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    OrderStatusChip(
                      status: rawStatus,
                      onFullColorSurface: true,
                      uppercase: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Middle: Customer icon + Name & Elapsed + Total & Payment badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: AppUi.controlRadius,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$elapsed • $payment',
                            style: TextStyle(
                              color: style.cardSecondaryText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          total,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildPaymentStatusBadge(order, onFullColor: true),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Address container with dark translucent background
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$address${barangay.isNotEmpty ? " • $barangay" : ""}',
                              style: TextStyle(
                                color: style.cardSecondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (landmark.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.assistant_direction_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                landmark,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Bottom Row: Manage action pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Manage Order',
                            style: TextStyle(
                              color: style.primaryColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: style.primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTab(String status, int count) {
    final label = _statusLabels[status] ?? _formatStatus(status);
    final color = status == 'all' ? AppUi.bluePrimary : _statusColor(status);
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Fetch Orders with Customer Data ───────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchOrdersWithCustomers(
    String ownerId,
  ) async {
    List<Map<String, dynamic>> mapRawOrders(List<Map<String, dynamic>> raw) {
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
      final response = await supabase
          .from('orders')
          .select('''
            *,
            customer:profiles!orders_customer_id_fkey(full_name, complete_address, phone, barangay, landmark)
          ''')
          .eq('owner_id', ownerId)
          .inFilter('status', [
            'pending',
            'accepted',
            'preparing',
            'ready_for_pickup',
            'assigned_to_rider',
            'out_for_delivery',
          ])
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> raw = List<Map<String, dynamic>>.from(
        response,
      );

      return mapRawOrders(raw);
    } catch (e) {
      debugPrint(
        'Primary joined order fetch failed, attempting resilient fallbacks: $e',
      );
    }

    // 2. Fallback Attempt A: Simple direct select on orders without foreign key join
    try {
      final response = await supabase
          .from('orders')
          .select('*')
          .eq('owner_id', ownerId)
          .inFilter('status', [
            'pending',
            'accepted',
            'preparing',
            'ready_for_pickup',
            'assigned_to_rider',
            'out_for_delivery',
          ])
          .order('created_at', ascending: false);

      return mapRawOrders(List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint('Direct inFilter order fetch failed: $e');
    }

    // 3. Fallback Attempt B: In case inFilter enum fails (e.g. 22P02 or schema mismatch)
    try {
      final response = await supabase
          .from('orders')
          .select('*')
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false)
          .limit(50);

      final all = List<Map<String, dynamic>>.from(response);
      final active = all.where((o) {
        final s = (o['status'] ?? '').toString().toLowerCase();
        return s != 'delivered' && s != 'cancelled' && s != 'declined';
      }).toList();

      return mapRawOrders(active);
    } catch (e) {
      debugPrint('Broad orders fetch failed: $e');
      rethrow;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ownerId = supabase.auth.currentUser?.id;
    if (ownerId == null) {
      return const Scaffold(
        body: Center(child: Text('Please login as owner.')),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ordersStreamController?.stream,
      initialData: _cachedOrders,
      builder: (context, snapshot) {
        if (_isRefreshingOrders && !snapshot.hasData && _cachedOrders == null) {
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

        final allOrders = prioritizeOwnerOrders(snapshot.data ?? []);

        final incoming = allOrders
            .where(
              (o) => [
                'pending',
                'accepted',
                'preparing',
                'ready_for_pickup',
                'assigned_to_rider',
                'out_for_delivery',
              ].contains((o['status'] ?? 'pending').toString()),
            )
            .toList();

        final pendingCount = incoming
            .where((o) => (o['status'] ?? 'pending') == 'pending')
            .length;
        final prepCount = incoming
            .where(
              (o) => [
                'accepted',
                'preparing',
                'ready_for_pickup',
              ].contains(o['status']),
            )
            .length;
        final dispatchedCount = incoming
            .where(
              (o) => [
                'assigned_to_rider',
                'out_for_delivery',
              ].contains(o['status']),
            )
            .length;

        final Map<String, int> counts = {
          'all': incoming.length,
          'pending': pendingCount,
          'in_prep': prepCount,
          'dispatched': dispatchedCount,
        };

        final statusOrders = switch (_selectedStatus) {
          'all' => incoming,
          'pending' =>
            incoming
                .where((o) => (o['status'] ?? 'pending') == 'pending')
                .toList(),
          'in_prep' =>
            incoming
                .where(
                  (o) => [
                    'accepted',
                    'preparing',
                    'ready_for_pickup',
                  ].contains(o['status']),
                )
                .toList(),
          'dispatched' =>
            incoming
                .where(
                  (o) => [
                    'assigned_to_rider',
                    'out_for_delivery',
                  ].contains(o['status']),
                )
                .toList(),
          _ =>
            incoming
                .where((o) => (o['status'] ?? 'pending') == _selectedStatus)
                .toList(),
        };
        final orders = statusOrders.where(_matchesOrderSearch).toList();

        return Scaffold(
          backgroundColor: AppUi.pageBgOf(context),
          body: Column(
            children: [
              TabScreenHeroHeader(
                title: 'Refill orders',
                subtitle: _isKanbanView
                    ? '${incoming.length} active · Kanban pipeline'
                    : '${incoming.length} active · ${_statusLabels[_selectedStatus]}',
                actions: [
                  IconButton(
                    onPressed: () =>
                        setState(() => _isKanbanView = !_isKanbanView),
                    icon: Icon(
                      _isKanbanView
                          ? Icons.view_agenda_rounded
                          : Icons.view_kanban_rounded,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : AppUi.textPrimary,
                      size: 22,
                    ),
                    tooltip: _isKanbanView
                        ? 'Switch to list view'
                        : 'Switch to Kanban pipeline',
                  ),
                  IconButton(
                    onPressed: _openAddOrderDialog,
                    icon: Icon(
                      Icons.add_rounded,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : AppUi.textPrimary,
                      size: 24,
                    ),
                    tooltip: 'Add manual refill',
                  ),
                ],
                bottom: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: AppUi.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'Search order, customer, or address',
                      hintStyle: const TextStyle(
                        color: AppUi.textMuted,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: AppUi.textSecondary,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(99),
                        borderSide: BorderSide(color: AppUi.borderOf(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(99),
                        borderSide: BorderSide(color: AppUi.borderOf(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(99),
                        borderSide: const BorderSide(
                          color: AppUi.bluePrimary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
              ),
              if (!_isKanbanView)
                Material(
                  color: AppUi.surfaceOf(context),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(
                        width: 3,
                        color: AppUi.bluePrimary,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    labelColor: AppUi.bluePrimary,
                    unselectedLabelColor: AppUi.textMuted,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    tabs: _statusFilters
                        .map((s) => _buildStatusTab(s, counts[s] ?? 0))
                        .toList(),
                  ),
                ),
              if (_ordersLoadError != null && allOrders.isNotEmpty)
                _buildStaleOrdersBanner(),
              Expanded(
                child: _ordersLoadError != null && allOrders.isEmpty
                    ? _buildOrdersLoadError()
                    : _isKanbanView
                    ? _buildKanbanPipeline(
                        incoming.where(_matchesOrderSearch).toList(),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _loadRiders();
                          await _refreshOrders();
                        },
                        color: AppUi.bluePrimary,
                        child: orders.isEmpty
                            ? ListView(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                children: [_buildEmptyState()],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                itemCount: orders.length,
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  child: _buildOrderCard(orders[index]),
                                ),
                              ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStaleOrdersBanner() {
    return Material(
      color: AppColors.uiWarningBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.uiWarning),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Showing saved orders. The latest refresh failed.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: _isRefreshingOrders ? null : _refreshOrders,
              child: _isRefreshingOrders
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppUi.textMuted,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              _ordersLoadError ?? 'Orders could not be loaded.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppUi.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isRefreshingOrders ? null : _refreshOrders,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKanbanPipeline(List<Map<String, dynamic>> orders) {
    final stages = [
      {
        'id': 'pending',
        'title': 'Pending',
        'color': OrderStatusColors.getColor('pending'),
        'filter': (Map<String, dynamic> o) =>
            (o['status'] ?? 'pending') == 'pending',
      },
      {
        'id': 'in_prep',
        'title': 'In Prep',
        'color': OrderStatusColors.getColor('preparing'),
        'filter': (Map<String, dynamic> o) {
          final s = (o['status'] ?? '').toString();
          return s == 'accepted' || s == 'preparing' || s == 'ready_for_pickup';
        },
      },
      {
        'id': 'dispatched',
        'title': 'Dispatched',
        'color': OrderStatusColors.getColor('out_for_delivery'),
        'filter': (Map<String, dynamic> o) {
          final s = (o['status'] ?? '').toString();
          return s == 'assigned_to_rider' || s == 'out_for_delivery';
        },
      },
      {
        'id': 'delivered',
        'title': 'Delivered',
        'color': OrderStatusColors.getColor('delivered'),
        'filter': (Map<String, dynamic> o) =>
            (o['status'] ?? '') == 'delivered',
      },
    ];

    return RefreshIndicator(
      onRefresh: () async {
        await _loadRiders();
        await _refreshOrders();
      },
      color: AppUi.bluePrimary,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        scrollDirection: Axis.horizontal,
        itemCount: stages.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final stage = stages[index];
          final color = stage['color'] as Color;
          final title = stage['title'] as String;
          final filterFn =
              stage['filter'] as bool Function(Map<String, dynamic>);
          final stageOrders = orders.where(filterFn).toList();

          return DragTarget<Map<String, dynamic>>(
            onWillAcceptWithDetails: (details) {
              final droppedOrder = details.data;
              final isCurrentStage = filterFn(droppedOrder);
              return !isCurrentStage;
            },
            onAcceptWithDetails: (details) {
              HapticFeedback.heavyImpact();
              _handleKanbanDrop(details.data, stage['id'] as String);
            },
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;

              return Container(
                width: 310,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isHovered
                      ? color.withValues(alpha: 0.08)
                      : AppUi.surfaceOf(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isHovered ? color : AppUi.borderOf(context),
                    width: isHovered ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isHovered
                          ? color.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.04),
                      blurRadius: isHovered ? 12 : 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        border: Border(
                          bottom: BorderSide(color: AppUi.borderOf(context)),
                          top: BorderSide(color: color, width: 3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${stageOrders.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: stageOrders.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  isHovered
                                      ? 'Drop here to move to $title'
                                      : 'No $title orders',
                                  style: TextStyle(
                                    color: isHovered ? color : AppUi.textMuted,
                                    fontWeight: isHovered
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(10),
                              itemCount: stageOrders.length,
                              itemBuilder: (context, i) {
                                final orderItem = stageOrders[i];
                                return LongPressDraggable<Map<String, dynamic>>(
                                  data: orderItem,
                                  feedback: Material(
                                    elevation: 8,
                                    borderRadius: AppUi.cardRadius,
                                    child: SizedBox(
                                      width: 290,
                                      child: Opacity(
                                        opacity: 0.9,
                                        child: _buildOrderCard(orderItem),
                                      ),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.35,
                                    child: _buildOrderCard(orderItem),
                                  ),
                                  child: _buildOrderCard(orderItem),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _handleKanbanDrop(Map<String, dynamic> order, String targetStageId) {
    final orderId = (order['id'] ?? '').toString();
    final currentStatus = (order['status'] ?? 'pending').toString();

    if (targetStageId == 'in_prep') {
      if (currentStatus == 'pending') {
        _updateStatus(orderId, 'accepted');
      } else if (currentStatus == 'accepted') {
        _updateStatus(orderId, 'preparing');
      }
    } else if (targetStageId == 'dispatched') {
      final assignedRider = order['assigned_rider_id'] ?? order['rider_id'];
      if (assignedRider == null) {
        _showOrderDetail(order);
      } else {
        _updateStatus(orderId, 'out_for_delivery');
      }
    } else if (targetStageId == 'delivered') {
      _updateStatus(orderId, 'delivered');
    }
  }

  Widget _buildEmptyState() {
    final isAll = _selectedStatus == 'all';
    return AxoEmptyState(
      pose: isAll ? AxoPose.happy : AxoPose.thinking,
      compact: true,
      title: isAll
          ? 'No active refill orders'
          : 'No ${_formatStatus(_selectedStatus)} orders',
      message: isAll
          ? 'New customer refill requests will appear here in real time.'
          : 'No refill orders currently match this status filter.',
    );
  }
}
