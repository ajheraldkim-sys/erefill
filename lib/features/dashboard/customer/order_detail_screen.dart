import 'dart:async';
import '../../../core/utils/safe_supabase.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'review_modal.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/models/chat_room.dart';
import '../../../core/constants.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../../../core/widgets/brand/refill_lottie.dart';
import '../../../core/widgets/erefill_header.dart';
import '../../../core/widgets/refill_status_widgets.dart';
import 'checkout_rules.dart';
import 'widgets/payment_status_banner.dart';
import '../../../core/utils/friendly_errors.dart';
import '../../../core/services/payment_launch_service.dart';
import '../../../core/services/local_data_cache.dart';
import '../../../core/services/offline_order_sync_service.dart';

import 'package:erefill/core/utils/money.dart';
class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? order;
  final String? orderId;

  const OrderDetailScreen({super.key, this.order, this.orderId})
    : assert(order != null || orderId != null);

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen>
    with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final _chatService = ChatService();
  RealtimeChannel? _orderChannel;
  Timer? _orderPollingTimer;
  Timer? _reconnectTimer;
  Map<String, dynamic>? _currentOrder;
  Map<String, dynamic>? _riderProfile;
  List<Map<String, dynamic>>? _orderItems;
  bool _hasReviewed = false;
  bool _isLoadingOrder = false;
  bool _isRefreshingOrder = false;
  bool _isAppForeground = true;
  String? _loadError;
  String? _refreshError;
  bool _isRetryingPayment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.order != null) {
      _currentOrder = widget.order;
      final id = _currentOrder?['id']?.toString();
      if (id != null && id.isNotEmpty) {
        unawaited(LocalDataCache.instance.set('order_$id', _currentOrder));
      }
      _bootstrapOrderData();
    } else if (widget.orderId != null) {
      _loadOrderById(widget.orderId!);
    }
  }

  Future<void> _retryOfflineOrderSync() async {
    final orderId = _currentOrder?['id']?.toString();
    if (orderId == null || _isRefreshingOrder) return;
    setState(() {
      _isRefreshingOrder = true;
      _refreshError = null;
    });
    var orderWasQueued = false;
    try {
      orderWasQueued = await OfflineOrderSyncService().retryOrderSync(orderId);
    } catch (e) {
      debugPrint('Offline order retry failed: $e');
      if (mounted) {
        setState(() {
          _refreshError =
              'Could not retry this order. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isRefreshingOrder = false);
    }
    if (!mounted) return;
    if (orderWasQueued) {
      await _refreshOrderState();
    } else {
      setState(() {
        _refreshError =
            'This order is no longer in the local queue. Refresh order status.';
      });
    }
  }

  Future<void> _loadOrderById(String orderId) async {
    setState(() {
      _isLoadingOrder = true;
      _loadError = null;
    });
    try {
      final order = await supabase
          .from('orders')
          .select()
          .eq('id', orderId)
          .single();
      if (!mounted) return;
      setState(() {
        _currentOrder = order;
        _isLoadingOrder = false;
      });
      unawaited(LocalDataCache.instance.set('order_$orderId', order));
      _bootstrapOrderData();
    } catch (e) {
      debugPrint('Error loading order: $e. Checking offline caches...');
      final cached = await LocalDataCache.instance.get<Map<String, dynamic>>(
        'order_$orderId',
      );
      if (cached != null && mounted) {
        setState(() {
          _currentOrder = cached;
          _isLoadingOrder = false;
        });
        _bootstrapOrderData();
        return;
      }
      final offlineList = await OfflineOrderSyncService().getOfflineOrders();
      final offlineMatches = offlineList
          .where((o) => o['id'] == orderId)
          .toList();
      if (offlineMatches.isNotEmpty && mounted) {
        setState(() {
          _currentOrder = offlineMatches.first;
          _isLoadingOrder = false;
        });
        _bootstrapOrderData();
        return;
      }
      if (mounted) {
        setState(() {
          _isLoadingOrder = false;
          _loadError = 'Could not load this order while offline.';
        });
      }
    }
  }

  void _bootstrapOrderData() {
    _loadRiderProfile();
    _loadOrderItems();
    _checkIfReviewed();
    _subscribeToOrderUpdates();
  }

  Future<void> _loadOrderItems() async {
    final orderId = _currentOrder?['id'];
    if (orderId == null) return;

    try {
      final items = await supabase
          .from('order_items')
          .select()
          .eq('order_id', orderId);

      if (mounted) {
        setState(() => _orderItems = List<Map<String, dynamic>>.from(items));
      }
    } catch (e) {
      debugPrint('Error loading order items: $e');
    }

    if ((_orderItems == null || _orderItems!.isEmpty) &&
        _currentOrder?['items'] != null) {
      final raw = _currentOrder!['items'];
      if (raw is List && raw.isNotEmpty && mounted) {
        setState(() {
          _orderItems = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    }
  }

  Future<void> _loadRiderProfile() async {
    final riderId = _currentOrder?['assigned_rider_id'];
    if (riderId == null) return;

    try {
      final riderData = await supabase
          .from('profiles')
          .select('id, full_name, phone')
          .eq('id', riderId)
          .single();

      if (mounted) {
        setState(() => _riderProfile = riderData);
      }
    } catch (e) {
      debugPrint('Error loading rider profile: $e');
    }
  }

  Future<void> _checkIfReviewed() async {
    final orderId = _currentOrder?['id'];
    if (orderId == null) return;

    try {
      final review = await supabase
          .from('reviews')
          .select('id')
          .eq('order_id', orderId)
          .maybeSingle();

      if (mounted) {
        setState(() => _hasReviewed = review != null);
      }
    } catch (e) {
      // Silently fail - review check is not critical
    }
  }

  void _subscribeToOrderUpdates() {
    final orderId = _currentOrder?['id'] ?? widget.orderId;
    if (orderId == null) return;

    final isQueuedLocally =
        _currentOrder?['is_offline_queued'] == true ||
        _currentOrder?['status'] == 'pending_sync';
    if (isQueuedLocally) {
      _startOrderPollingTimer();
      return;
    }

    if (_orderChannel != null) {
      supabase.removeChannel(_orderChannel!);
      _orderChannel = null;
    }
    _reconnectTimer?.cancel();

    _orderChannel = supabase
        .channel('public:orders:$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: orderId,
          ),
          callback: (payload) {
            _refreshOrderState();
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            _reconnectTimer?.cancel();
            _reconnectTimer = Timer(const Duration(seconds: 3), () {
              if (mounted && _isAppForeground) _subscribeToOrderUpdates();
            });
          }
        });

    if (_isAppForeground) _startOrderPollingTimer();
  }

  void _startOrderPollingTimer() {
    if (!_isAppForeground) return;
    _orderPollingTimer?.cancel();
    _orderPollingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      final status = _currentOrder?['status']?.toString();
      if (status != 'delivered' && status != 'cancelled') {
        _refreshOrderState();
      }
    });
  }

  Future<void> _refreshOrderState() async {
    final orderId = _currentOrder?['id'] ?? widget.orderId;
    if (orderId == null || _isRefreshingOrder || !_isAppForeground) return;
    _isRefreshingOrder = true;
    try {
      final currentOrder = _currentOrder;
      final isQueuedLocally =
          currentOrder?['is_offline_queued'] == true ||
          currentOrder?['status'] == 'pending_sync';
      if (isQueuedLocally) {
        final offlineOrders = await OfflineOrderSyncService()
            .getOfflineOrders();
        final localOrder = offlineOrders
            .where((item) => item['id']?.toString() == orderId.toString())
            .firstOrNull;

        if (localOrder != null && localOrder['status'] == 'pending_sync') {
          if (mounted) {
            setState(() {
              _currentOrder = {...?currentOrder, ...localOrder};
              _refreshError = null;
            });
          }
          return;
        }
        if (localOrder?['status'] == 'synced' && mounted) {
          setState(() {
            _currentOrder = {
              ...?currentOrder,
              'status': 'pending',
              'is_offline_queued': false,
              'offline_sync_failed': false,
            };
          });
          HapticFeedback.heavyImpact();
          _showStatusNotification('pending');
        }
      }

      final updated = await supabase
          .from('orders')
          .select()
          .eq('id', orderId)
          .maybeSingle();
      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _refreshError = 'The latest order status could not be found.';
        });
        return;
      }
      if (mounted) {
        final oldStatus = _currentOrder?['status'];
        final newStatus = updated['status'] as String?;
        final oldRiderId = _currentOrder?['assigned_rider_id'];
        final newRiderId = updated['assigned_rider_id'];

        setState(() {
          _currentOrder = {
            ...(_currentOrder ?? {}),
            ...updated,
            'is_offline_queued': false,
            'offline_sync_failed': false,
          };
          _refreshError = null;
        });

        if (newRiderId != null && oldRiderId == null) {
          _loadRiderProfile();
        }

        if (newStatus != oldStatus && newStatus != null) {
          HapticFeedback.heavyImpact();
          _showStatusNotification(newStatus);
        }
      }
    } catch (e) {
      debugPrint('Error polling order state: $e');
      if (mounted) {
        setState(() {
          _refreshError =
              'Could not refresh order updates. Check your connection and retry.';
        });
      }
    } finally {
      _isRefreshingOrder = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppForeground = state == AppLifecycleState.resumed;
    if (_isAppForeground) {
      _refreshOrderState();
      _subscribeToOrderUpdates();
    } else {
      _orderPollingTimer?.cancel();
      _orderPollingTimer = null;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
  }

  void _showStatusNotification(String status) {
    String message;
    switch (status) {
      case 'pending':
        message = 'Your offline order was sent to the station.';
        break;
      case 'accepted':
        message = 'Station has accepted your order!';
        break;
      case 'preparing':
        message = 'Your water refill order is being prepared.';
        break;
      case 'ready_for_pickup':
        message = 'Your water is ready for rider pickup.';
        break;
      case 'assigned_to_rider':
        message = 'A rider has been assigned to your delivery.';
        break;
      case 'out_for_delivery':
        message = 'Rider is heading to your location!';
        break;
      case 'delivered':
        message = 'Your order has been delivered!';
        // Show review modal automatically when delivered and not yet reviewed
        if (!_hasReviewed) {
          _showReviewModal();
        }
        break;
      default:
        message = 'Order status updated: $status';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.uiSuccess,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showReviewModal() {
    final orderId = _currentOrder?['id'];
    final stationId = _currentOrder?['owner_id'];
    final stationName = _currentOrder?['station_name'] ?? 'this station';

    if (orderId == null || stationId == null) return;

    // Delay slightly to let the status notification show first
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      ReviewModal.show(
        context: context,
        orderId: orderId,
        stationId: stationId,
        stationName: stationName,
        onReviewSubmitted: () {
          setState(() => _hasReviewed = true);
        },
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orderPollingTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_orderChannel != null) {
      supabase.removeChannel(_orderChannel!);
    }
    super.dispose();
  }

  bool _isOnlinePayment(Map<String, dynamic> order) {
    return CheckoutRules.isOnlinePayment(order['payment_method']?.toString());
  }

  Future<void> _retryPayment(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString() ?? _currentOrder?['id']?.toString();
    if (orderId == null || !_isOnlinePayment(order)) return;
    if (_isRetryingPayment) return;

    setState(() => _isRetryingPayment = true);

    try {
      // 1. Fetch freshest order record to check current payment status & checkout URL
      Map<String, dynamic>? latestOrder;
      try {
        latestOrder = await supabase
            .from('orders')
            .select()
            .eq('id', orderId)
            .maybeSingle();
      } catch (e) {
        debugPrint(
          '[OrderDetail] Order reload before payment retry failed: $e',
        );
      }

      final activeOrder = latestOrder ?? _currentOrder ?? order;
      if (latestOrder != null && mounted) {
        setState(() => _currentOrder = {...?_currentOrder, ...latestOrder!});
      }

      final paymentStatus = (activeOrder['payment_status'] ?? 'pending')
          .toString()
          .toLowerCase();
      final orderStatus = (activeOrder['status'] ?? 'pending')
          .toString()
          .toLowerCase();

      // If already paid
      if (paymentStatus == 'success' || paymentStatus == 'paid') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment has already been confirmed for this order.'),
            backgroundColor: AppColors.uiSuccess,
          ),
        );
        return;
      }

      // If cancelled or delivered
      if (orderStatus == 'cancelled' || orderStatus == 'delivered') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This order is $orderStatus and is no longer eligible for payment.',
            ),
            backgroundColor: AppColors.uiError,
          ),
        );
        return;
      }

      // 2. Check for an existing valid checkout URL if payment is still pending/processing
      final existingCheckoutUrl =
          (activeOrder['payment_checkout_url'] ??
                  order['payment_checkout_url'] ??
                  _currentOrder?['payment_checkout_url'])
              ?.toString()
              .trim();

      final isFailedState = {'failed', 'expired'}.contains(paymentStatus);
      if (existingCheckoutUrl != null &&
          existingCheckoutUrl.isNotEmpty &&
          !isFailedState &&
          (existingCheckoutUrl.startsWith('http://') ||
              existingCheckoutUrl.startsWith('https://'))) {
        debugPrint(
          '[OrderDetail] Launching existing checkout URL: $existingCheckoutUrl',
        );
        final launched = await PaymentLaunchService.launchCheckoutUrl(
          existingCheckoutUrl,
        );
        if (launched) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Reopened payment checkout in browser.'),
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // 3. If no existing URL or launch failed, create or refresh via edge function
      final rawMethod =
          (activeOrder['payment_method'] ?? order['payment_method'] ?? '')
              .toString();
      final normalizedMethod = rawMethod.trim().toLowerCase().replaceAll(
        'paymaya',
        'maya',
      );

      final response = await supabase.functions.invoke(
        'create-payment-checkout',
        body: {
          'order_id': orderId,
          'payment_method': normalizedMethod,
          // The previous checkout could not be reopened, so do not reuse its
          // inaccessible URL when requesting another payment attempt.
          'force_new_checkout': true,
        },
      );

      final data = response.data;
      final checkoutUrl = data is Map
          ? data['checkout_url']?.toString().trim()
          : null;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('Payment checkout session could not be established.');
      }

      if (mounted) {
        setState(() {
          if (_currentOrder != null) {
            _currentOrder!['payment_checkout_url'] = checkoutUrl;
            _currentOrder!['payment_status'] = 'processing';
          }
        });
      }

      final launched = await PaymentLaunchService.launchCheckoutUrl(
        checkoutUrl,
      );
      if (!launched) {
        throw Exception(
          'Unable to open checkout in browser. Please check your browser or app settings.',
        );
      }
    } catch (e) {
      debugPrint('[OrderDetail] Payment retry failed: $e');
      if (!mounted) return;

      String errorMessage =
          'Could not reopen payment checkout. Please try again.';
      if (e is FunctionException) {
        final details = e.details;
        if (details is Map && details['error'] != null) {
          errorMessage = details['error'].toString();
        } else if (details is String && details.isNotEmpty) {
          errorMessage = details;
        } else if (e.reasonPhrase != null && e.reasonPhrase!.isNotEmpty) {
          errorMessage = e.reasonPhrase!;
        }
      } else {
        errorMessage = FriendlyErrors.message(
          e,
          fallback: 'Could not reopen payment checkout. Please try again.',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.uiError,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRetryingPayment = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _cancelOrder() async {
    final orderId = _currentOrder?['id']?.toString();
    if (orderId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppUi.dialogRadius),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.statusCancelled),
            SizedBox(width: 8),
            Text(
              'Cancel Order?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to cancel this refill order? The station has not started preparing it yet.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusCancelled,
            ),
            child: const Text('Yes, Cancel Order'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final res = await SafeSupabase.transitionOrderStatus(
        orderId: orderId,
        newStatus: 'cancelled',
      );
      if (res['success'] != true) {
        throw StateError(
          res['message']?.toString() ??
              'Order cancellation could not be applied.',
        );
      }

      if (mounted) {
        setState(() {
          if (_currentOrder != null) {
            _currentOrder!['status'] = 'cancelled';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order has been cancelled.'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not cancel order: ${FriendlyErrors.message(e)}'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingOrder) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: const AxoLoader(message: 'Loading order...'),
      );
    }

    final order = _currentOrder;
    if (order == null) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: AxoEmptyState(
          title: _loadError ?? 'Order not found',
          message: 'Return home and open the order from your history.',
          actionLabel: _loadError == null ? null : 'Retry',
          onAction: _loadError == null
              ? null
              : () {
                  final orderId = widget.orderId ?? order?['id']?.toString();
                  if (orderId != null && orderId.isNotEmpty) {
                    _loadOrderById(orderId);
                  }
                },
        ),
      );
    }

    final status = (order['status'] ?? 'pending').toString();
    final stationName = order['station_name'] ?? 'Unknown Station';
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final createdAt =
        DateTime.tryParse(order['created_at']?.toString() ?? '') ??
        DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: ERefillHeader(
        type: ERefillHeaderType.orderDetail,
        title:
            'Order #${((order['id']?.toString() ?? '').length >= 8 ? (order['id']!.toString().substring(0, 8)) : (order['id']?.toString() ?? '')).toUpperCase()}',
        subtitle: 'Track your water refill delivery',
        statusBadge: OrderStatusBadge(status: status),
        actions: [
          IconButton(
            onPressed: () => _contactStation(),
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
              color: AppUi.brandOf(context),
              size: 22,
            ),
            tooltip: 'Chat with station',
          ),
          IconButton(
            onPressed: () => _showOrderDetails(order),
            icon: Icon(
              Icons.receipt_long_rounded,
              color: AppUi.brandOf(context),
              size: 22,
            ),
            tooltip: 'Order details',
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_refreshError != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppUi.warningBg,
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  border: Border.all(
                    color: AppUi.warningFg.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: AppUi.warningFg,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _refreshError!,
                        style: const TextStyle(
                          color: AppUi.warningFg,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isRefreshingOrder ? null : _refreshOrderState,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            // 1. Simple Stepper at the top with large ETA
            _buildTrackingHeaderWithEta(status, order),
            const SizedBox(height: 10),

            // 2. Map underneath stepper
            if (status != 'delivered' && status != 'cancelled') ...[
              _buildMapPreview(status, order),
              const SizedBox(height: 10),
            ],

            // 3. One-tap rider contact buttons (Call, Chat, Track)
            if (status == 'assigned_to_rider' ||
                status == 'rider_assigned' ||
                status == 'out_for_delivery' ||
                status == 'delivering') ...[
              _buildRiderContact(order),
              const SizedBox(height: 10),
            ],

            // 4. Delivery completed summary card
            if (status == 'delivered') ...[
              _buildDeliveryCompleteCompact(),
              const SizedBox(height: 10),
            ],

            // 5. Offline sync & payment notices
            if (order['is_offline_queued'] == true ||
                status == 'pending_sync') ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppUi.warningBg,
                  borderRadius: AppUi.cardRadius,
                  border: Border.all(
                    color: AppUi.warningFg.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      order['offline_sync_failed'] == true
                          ? Icons.cloud_off_rounded
                          : Icons.cloud_upload_outlined,
                      color: AppUi.warningFg,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        order['offline_sync_failed'] == true
                            ? 'This order has not reached the station. Check your connection, then retry.'
                            : 'Saved on this device. The station has not received the order yet.',
                        style: const TextStyle(
                          color: AppUi.warningFg,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isRefreshingOrder
                          ? null
                          : _retryOfflineOrderSync,
                      child: Text(_isRefreshingOrder ? 'Sending…' : 'Retry'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (status == 'cancelled') ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.statusCancelled.withValues(alpha: 0.08),
                  borderRadius: AppUi.cardRadius,
                  border: Border.all(
                    color: AppColors.statusCancelled.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.cancel_rounded,
                      color: AppColors.statusCancelled,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Order cancelled. Contact the station if you need help.',
                        style: TextStyle(
                          color: AppColors.statusCancelled,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_isOnlinePayment(order)) ...[
              PaymentStatusBanner(
                order: order,
                isLoading: _isRetryingPayment,
                onRetry: _isRetryingPayment ? null : () => _retryPayment(order),
              ),
              const SizedBox(height: 10),
            ],

            // 6. Station & Delivery info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? AppUi.surfaceRaisedOf(context)
                    : AppUi.surfaceOf(context),
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                border: Border.all(color: AppUi.borderOf(context)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? AppUi.bluePrimary.withValues(alpha: 0.18)
                          : AppUi.brandSoftOf(context),
                    ),
                    child: Center(
                      child: ClipOval(
                        child: status == 'delivered'
                            ? const RefillLottie.success(width: 44, height: 44)
                            : (status == 'delivering' ||
                                  status == 'assigned_to_rider' ||
                                  status == 'out_for_delivery')
                            ? const RefillLottie.rider(width: 48, height: 48)
                            : (status == 'preparing' ||
                                  status == 'ready_for_pickup')
                            ? const RefillLottie.waterDrop(
                                width: 40,
                                height: 40,
                              )
                            : Icon(
                                Icons.storefront_rounded,
                                color: AppUi.brandOf(context),
                                size: 24,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppUi.textPrimaryOf(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${formatPeso(totalAmount, whole: true)} · ${_formatDate(createdAt)}',
                          style: TextStyle(
                            color: AppUi.textSecondaryOf(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildDeliveryInfo(order),

            // 7. Cancellation action for pending orders
            if (status == 'pending') ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _cancelOrder,
                  icon: const Icon(
                    Icons.cancel_outlined,
                    size: 18,
                    color: AppColors.statusCancelled,
                  ),
                  label: const Text(
                    'Cancel Order',
                    style: TextStyle(
                      color: AppColors.statusCancelled,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.statusCancelled.withValues(alpha: 0.3),
                    ),
                    backgroundColor: AppColors.statusCancelled.withValues(
                      alpha: 0.08,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppUi.cardRadius,
                    ),
                  ),
                ),
              ),
            ],

          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryInfo(Map<String, dynamic> order) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppUi.blueSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.location_pin,
              color: AppUi.brandOf(context),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DELIVERY TO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textSecondaryOf(context),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  order['customer_address'] ?? 'No address provided',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                Text(
                  '${order['customer_barangay'] ?? ''}, ${order['customer_municipality'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return _formatDate(time);
  }

  Widget _buildTrackingHeaderWithEta(
    String status,
    Map<String, dynamic> order,
  ) {
    // Headline + next step come from the real backend status only. No
    // invented ETAs: the backend does not compute delivery estimates.
    final String etaText;
    final String etaSubtitle;
    switch (OrderStatusColors.normalize(status)) {
      case 'pending_sync':
        etaText = 'Saved offline';
        etaSubtitle = 'Sends automatically when you are back online';
        break;
      case 'pending':
        etaText = 'Waiting for the station';
        etaSubtitle = 'The station will accept or decline your order';
        break;
      case 'accepted':
        etaText = 'Order accepted';
        etaSubtitle = 'The station will start preparing your water';
        break;
      case 'preparing':
        etaText = 'Preparing your order';
        etaSubtitle = 'Containers are being sanitized and filled';
        break;
      case 'ready_for_pickup':
        etaText = 'Ready at the station';
        etaSubtitle = 'Waiting for a rider to pick up your order';
        break;
      case 'out_for_delivery':
        final assigned = status == 'assigned_to_rider' ||
            status == 'rider_assigned';
        etaText = assigned ? 'Rider assigned' : 'On the way';
        etaSubtitle = assigned
            ? 'The rider is collecting your order from the station'
            : 'Your rider is heading to your address';
        break;
      case 'delivered':
        etaText = 'Delivered';
        etaSubtitle = 'Thanks for ordering with eRefill';
        break;
      case 'cancelled':
        etaText = 'Order cancelled';
        etaSubtitle = 'This order will not be delivered';
        break;
      case 'rejected':
        etaText = 'Order declined';
        etaSubtitle = 'The station could not take this order';
        break;
      default:
        etaText = OrderStatusColors.getLabel(status);
        etaSubtitle = 'We will update this screen as your order moves';
    }
    final etaIcon = OrderStatusColors.getIcon(status);
    final etaColor = OrderStatusColors.getColor(status);
    final updatedAt = SafeParse.dateTime(order['updated_at']);
    final updatedLabel = updatedAt == null
        ? null
        : _relativeTime(updatedAt.toLocal());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        border: Border.all(color: AppUi.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.2
                  : 0.04,
            ),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: etaColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                ),
                child: Icon(etaIcon, color: etaColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      etaText,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      etaSubtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    if (updatedLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Updated $updatedLabel',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (status == 'pending_sync')
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Order progress starts after the station receives your order.',
                textAlign: TextAlign.center,
              ),
            )
          else
            RefillOrderStatusTimeline(status: status),
        ],
      ),
    );
  }

  Widget _buildMapPreview(String status, Map<String, dynamic> order) {
    final orderId = order['id']?.toString() ?? '';
    final riderId = order['assigned_rider_id']?.toString();
    final isOutForDelivery =
        status == 'out_for_delivery' || status == 'delivering';

    return Container(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        border: Border.all(
          color: isOutForDelivery
              ? OrderStatusColors.outForDelivery
              : AppUi.borderOf(context),
          width: isOutForDelivery ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
              context.openOrderTrackingMap(orderId: orderId, riderId: riderId),
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isOutForDelivery) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppUi.warningBg,
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      border: Border.all(color: AppColors.uiWarning),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.notifications_active_rounded,
                          color: AppUi.warningFg,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Rider is nearby! Please prepare your empty gallons and cash.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppUi.warningFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppUi.brandSoftOf(context),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      child: Icon(
                        Icons.map_rounded,
                        color: AppUi.brandOf(context),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Live Delivery Map',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isOutForDelivery
                                ? 'Tap to view live rider GPS tracking'
                                : 'View station route and delivery destination',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppUi.textSecondaryOf(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppUi.bluePrimary,
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Open Map',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 14,
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

  Widget _buildRiderContact(Map<String, dynamic> order) {
    final riderId = order['assigned_rider_id'] as String?;
    if (riderId == null) return const SizedBox.shrink();

    final riderName = _riderProfile?['full_name'] ?? 'Your Rider';
    final riderPhone = _riderProfile?['phone']?.toString().trim() ?? '';
    final status = (order['status'] ?? '').toString();
    final isOutForDelivery =
        status == 'out_for_delivery' || status == 'delivering';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        border: Border.all(
          color: isOutForDelivery
              ? OrderStatusColors.outForDelivery
              : AppUi.borderOf(context),
          width: isOutForDelivery ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: OrderStatusColors.outForDelivery.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: AppUi.controlRadius,
                ),
                child: const Icon(
                  Icons.delivery_dining_rounded,
                  color: OrderStatusColors.outForDelivery,
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
                          isOutForDelivery
                              ? 'Rider is on the way'
                              : 'Assigned Rider',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: OrderStatusColors.outForDelivery,
                          ),
                        ),
                        if (isOutForDelivery) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppUi.warningBg,
                              borderRadius: BorderRadius.circular(AppUi.radiusFull),
                            ),
                            child: const Text(
                              'Nearby',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppUi.warningFg,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      riderName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (riderPhone.isNotEmpty) ...[
                Expanded(
                  child: SizedBox(
                    height: AppUi.kMinTouchTarget,
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse('tel:$riderPhone')),
                      icon: const Icon(Icons.phone_rounded, size: 18),
                      label: const Text('Call'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.uiSuccess,
                        side: const BorderSide(color: AppColors.uiSuccess),
                        backgroundColor: AppUi.successBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppUi.controlRadius,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SizedBox(
                  height: AppUi.kMinTouchTarget,
                  child: FilledButton.icon(
                    onPressed: () => _contactRider(riderId, riderName),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const Text('Chat'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppUi.bluePrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.controlRadius,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: AppUi.kMinTouchTarget,
                  child: OutlinedButton.icon(
                    onPressed: () => _trackRider(riderId),
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('Track'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppUi.borderOf(context)),
                      foregroundColor: AppUi.textPrimaryOf(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.controlRadius,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildDeliveryCompleteCompact() {
    final deliveryNote =
        _currentOrder?['delivery_note']?.toString().trim() ?? '';
    final emptyReturned =
        (_currentOrder?['empty_gallons_returned'] as num?)?.toInt() ?? 0;
    final hasPhoto =
        _currentOrder?['delivery_photo_url']?.toString().trim().isNotEmpty ??
        false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.statusCompleted.withValues(alpha: 0.1),
        borderRadius: AppUi.cardRadius,
        border: Border.all(
          color: AppColors.statusCompleted.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.celebration_rounded,
                color: AppColors.statusCompleted,
                size: 22,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Water delivered!',
                  style: TextStyle(
                    color: AppColors.statusCompleted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasPhoto)
                IconButton(
                  onPressed: _openDeliveryPhoto,
                  tooltip: 'View delivery proof',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.photo_camera_outlined,
                    color: AppColors.statusCompleted,
                  ),
                ),
            ],
          ),
          if (deliveryNote.isNotEmpty || emptyReturned > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                [
                  if (emptyReturned > 0)
                    '$emptyReturned empty gallon${emptyReturned == 1 ? '' : 's'} returned',
                  if (deliveryNote.isNotEmpty) deliveryNote,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.statusCompleted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: _hasReviewed ? null : _showReviewModal,
              icon: Icon(
                _hasReviewed ? Icons.check_rounded : Icons.star_rounded,
                size: 18,
              ),
              label: Text(
                _hasReviewed ? 'Review shared' : 'Rate your experience',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.statusCompleted,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.statusCompleted,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: AppUi.controlRadius,
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeliveryPhoto() async {
    final photoPath = _currentOrder?['delivery_photo_url']?.toString();
    if (photoPath == null || photoPath.isEmpty) return;

    try {
      final signedUrl = await supabase.storage
          .from('delivery_proofs')
          .createSignedUrl(photoPath, 60 * 10);
      final opened = await launchUrl(
        Uri.parse(signedUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('Could not open the proof image.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery proof could not be opened.')),
      );
    }
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusSheetTop,
        ),
        child: Column(
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
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order Receipt',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Order ID & Date
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppUi.pageBgOf(context),
                        borderRadius: AppUi.cardRadius,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order ID',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppUi.textSecondaryOf(context),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Builder(
                                builder: (context) {
                                  final id = order['id']?.toString() ?? '';
                                  final shortId = id.length >= 12 ? id.substring(0, 12) : id;
                                  return Text(
                                    '#${shortId.toUpperCase()}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppUi.textPrimaryOf(context),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Delivery date',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppUi.textSecondaryOf(context),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                () {
                                  final parsed = DateTime.tryParse(
                                    order['created_at']?.toString() ?? '',
                                  );
                                  return parsed != null
                                      ? '${parsed.day}/${parsed.month}/${parsed.year}'
                                      : '---';
                                }(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppUi.textPrimaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 2. Delivery Address
                    Text(
                      'Delivery address',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textSecondaryOf(context),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          color: AppUi.brandOf(context),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order['customer_address'] ??
                                    'No address provided',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppUi.textPrimaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${order['customer_barangay'] ?? ''}, ${order['customer_municipality'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppUi.textSecondaryOf(context),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // 3. Water refill list
                    Text(
                      'Water refill details',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textSecondaryOf(context),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_orderItems == null)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      ..._orderItems!.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppUi.brandSoftOf(context),
                                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                                ),
                                child: Text(
                                  '${item['quantity']}x',
                                  style: TextStyle(
                                    color: AppUi.brandOf(context),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['product_name'] ??
                                      item['water_type'] ??
                                      'Water refill',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                              Text(
                                '₱${(item['subtotal'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppUi.textPrimaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    Divider(height: 32, color: AppUi.borderOf(context)),

                    // 4. Totals
                    Builder(
                      builder: (context) {
                        final subtotal =
                            (order['subtotal'] as num?)?.toDouble() ?? 0.0;
                        final deliveryFee =
                            (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
                        final totalAmount =
                            (order['total_amount'] as num?)?.toDouble() ??
                            (subtotal + deliveryFee);
                        final explicitFee = (order['platform_fee'] as num?)
                            ?.toDouble();
                        final serviceFee =
                            explicitFee ??
                            ((totalAmount - (subtotal + deliveryFee)) > 0.01
                                ? (totalAmount - (subtotal + deliveryFee))
                                : 0.0);

                        return Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Refill subtotal',
                                  style: TextStyle(
                                    color: AppUi.textSecondaryOf(context),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  formatPeso(subtotal),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Delivery Fee',
                                  style: TextStyle(
                                    color: AppUi.textSecondaryOf(context),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  formatPeso(deliveryFee),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                            if (serviceFee > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Service Fee',
                                        style: TextStyle(
                                          color: AppUi.textSecondaryOf(context),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      GestureDetector(
                                        onTap: () {
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: Row(
                                                children: [
                                                  Icon(
                                                    Icons.info_outline_rounded,
                                                    color: AppUi.brandOf(context),
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'What is this fee?',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              content: const Text(
                                                'A small fee that covers 24/7 app maintenance, real-time rider tracking, and customer support so your water refills arrive smoothly.',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  height: 1.45,
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx),
                                                  child: const Text('Got it'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        child: const Icon(
                                          Icons.info_outline_rounded,
                                          size: 15,
                                          color: AppUi.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    formatPeso(serviceFee),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppUi.textPrimaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    if (order['notes'] != null &&
                        order['notes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Notes',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppUi.textSecondaryOf(context),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order['notes'],
                        style: TextStyle(
                          fontSize: 12,
                          color: AppUi.textSecondaryOf(context),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    Divider(height: 32, color: AppUi.borderOf(context)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total to Pay',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                        Text(
                          '₱${(order['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: AppUi.brandOf(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppUi.chipBgOf(context),
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          ),
                          child: Text(
                            (order['payment_method'] ?? 'COD')
                                .toString()
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    if ((order['status'] ?? 'pending').toString() ==
                        'pending') ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _cancelOrder();
                          },
                          icon: const Icon(
                            Icons.cancel_outlined,
                            color: AppColors.uiError,
                            size: 18,
                          ),
                          label: const Text(
                            'Cancel Order',
                            style: TextStyle(
                              color: AppColors.uiError,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppUi.error.withValues(alpha: 0.55),
                            ),
                            backgroundColor: AppUi.surfaceOf(context),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppUi.cardRadius,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 6. Report Issue & Close
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _fileDispute();
                        },
                        icon: const Icon(
                          Icons.report_problem_rounded,
                          color: AppColors.uiError,
                          size: 18,
                        ),
                        label: const Text(
                          'Report an Issue',
                          style: TextStyle(
                            color: AppColors.uiError,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppUi.error,
                          backgroundColor: AppUi.surfaceOf(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppUi.cardRadius,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: AppUi.cardRadius,
                          ),
                          side: BorderSide(color: AppUi.borderOf(context)),
                        ),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppUi.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fileDispute() async {
    final reasons = [
      'Not Delivered',
      'Wrong Location',
      'Damaged / Incomplete',
      'Rider Issue',
      'Other',
    ];
    String selectedReason = reasons.first;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report a Problem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'What issue are you facing with this order?',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: reasons.contains(selectedReason)
                    ? selectedReason
                    : reasons.first,
                items: reasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedReason = v!),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Describe the issue...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final orderId = _currentOrder?['id'];
                final reporterId = supabase.auth.currentUser?.id;
                if (orderId == null || reporterId == null) return;

                Navigator.pop(context); // Close dialog

                try {
                  await supabase.from('disputes').insert({
                    'order_id': orderId,
                    'reporter_id': reporterId,
                    'reason': selectedReason,
                    'description': controller.text,
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Issue reported. We will investigate.'),
                        backgroundColor: AppColors.uiWarning,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed: ${FriendlyErrors.message(e)}'),
                        backgroundColor: AppColors.uiError,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.uiError,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
  }

  void _contactStation() async {
    final orderId = _currentOrder?['id'];
    final ownerId = _currentOrder?['owner_id'];
    final customerId = _currentOrder?['customer_id'];
    final stationName = _currentOrder?['station_name'] ?? 'Station';
    if (orderId == null || ownerId == null || customerId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final customerName = _currentOrder?['customer_name']?.toString();
      final room = await _chatService.getOrCreateCustomerOwnerRoom(
        orderId: orderId,
        customerId: customerId,
        ownerId: ownerId,
        stationName: stationName,
        customerName: customerName,
      );

      if (mounted) Navigator.pop(context);

      if (mounted) {
        context.openChat(
          roomId: room.id,
          roomTitle: 'Chat with $stationName',
          roomType: ChatRoomType.customerSupport,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.message(
                e,
                fallback:
                    'Unable to open station chat right now. Please try again.',
              ),
            ),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  void _contactRider(String riderId, String riderName) async {
    final orderId = _currentOrder?['id'];
    final ownerId = _currentOrder?['owner_id'];
    final customerId = _currentOrder?['customer_id'];
    if (orderId == null || ownerId == null || customerId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final customerName = _currentOrder?['customer_name']?.toString();
      final room = await _chatService.getOrCreateCustomerRiderRoom(
        orderId: orderId,
        customerId: customerId,
        riderId: riderId,
        customerName: customerName,
        riderName: riderName,
      );

      if (mounted) Navigator.pop(context);

      if (mounted) {
        context.openChat(
          roomId: room.id,
          roomTitle: 'Chat with $riderName',
          roomType: ChatRoomType.orderDelivery,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.message(
                e,
                fallback:
                    'Unable to open rider chat right now. Please try again.',
              ),
            ),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  void _trackRider(String riderId) {
    final orderId = _currentOrder?['id']?.toString() ?? '';
    context.openOrderTrackingMap(orderId: orderId, riderId: riderId);
  }
}
