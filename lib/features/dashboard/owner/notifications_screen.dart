import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/widgets/notification_detail_dialog.dart';
import 'package:erefill/core/theme/app_colors.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  StreamSubscription? _notificationSub;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _systemAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToNotifications();
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Load notifications
      final notifications = await supabase
          .from('system_notifications')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      // Load system alerts
      final alerts = await _generateSystemAlerts();

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(notifications);
          _systemAlerts = alerts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _generateSystemAlerts() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final List<Map<String, dynamic>> alerts = [];
    final now = DateTime.now();

    try {
      // Check for pending orders
      final pendingOrdersResponse = await supabase
          .from('orders')
          .select('id')
          .eq('owner_id', user.id)
          .eq('status', 'pending')
          .count();

      final pendingOrders = pendingOrdersResponse.count;

      if (pendingOrders > 0) {
        alerts.add({
          'id': 'pending_orders',
          'title':
              '$pendingOrders Pending Order${pendingOrders > 1 ? 's' : ''}',
          'message': 'New refill orders waiting for acceptance',
          'type': 'urgent',
          'icon': Icons.notifications_active,
          'color': OrderStatusColors.pending,
          'time': now,
          'action': 'View Orders',
        });
      }

      final readyOrdersResponse = await supabase
          .from('orders')
          .select('id')
          .eq('owner_id', user.id)
          .eq('status', 'ready_for_pickup')
          .count();

      final readyOrders = readyOrdersResponse.count;
      if (readyOrders > 0) {
        alerts.add({
          'id': 'ready_for_pickup',
          'title': '$readyOrders Ready Refill${readyOrders > 1 ? 's' : ''}',
          'message': 'Assign a rider to start delivery',
          'type': 'urgent',
          'icon': Icons.assignment_ind_rounded,
          'color': OrderStatusColors.readyForDelivery,
          'time': now,
          'action': 'View Orders',
        });
      }

      // Check for out for delivery orders
      final deliveringOrdersResponse = await supabase
          .from('orders')
          .select('id')
          .eq('owner_id', user.id)
          .eq('status', 'out_for_delivery')
          .count();

      final deliveringOrders = deliveringOrdersResponse.count;

      if (deliveringOrders > 0) {
        alerts.add({
          'id': 'delivering',
          'title':
              '$deliveringOrders Order${deliveringOrders > 1 ? 's' : ''} Out for Delivery',
          'message': 'Track your riders in real-time',
          'type': 'info',
          'icon': Icons.delivery_dining,
          'color': OrderStatusColors.outForDelivery,
          'time': now,
          'action': 'Track',
        });
      }

      final delayedOrders = await supabase
          .from('sla_violations')
          .select('order_id, violation_type')
          .eq('owner_id', user.id);
      if (delayedOrders.isNotEmpty) {
        alerts.insert(0, {
          'id': 'sla_violations',
          'title':
              '${delayedOrders.length} Delayed Refill${delayedOrders.length > 1 ? 's' : ''}',
          'message': 'Orders need attention to keep delivery times on track',
          'type': 'urgent',
          'icon': Icons.timer_outlined,
          'color': AppColors.statusCancelled,
          'time': now,
          'action': 'View Orders',
        });
      }

      final failedPayments = await supabase
          .from('payment_checkouts')
          .select('id')
          .eq('owner_id', user.id)
          .inFilter('status', ['failed', 'expired']);
      if (failedPayments.isNotEmpty) {
        alerts.add({
          'id': 'failed_payments',
          'title':
              '${failedPayments.length} Payment Issue${failedPayments.length > 1 ? 's' : ''}',
          'message':
              'Online checkout failed or expired; customer may need help',
          'type': 'urgent',
          'icon': Icons.payment_outlined,
          'color': AppColors.uiError,
          'time': now,
          'action': 'View Orders',
        });
      }

      try {
        final webhookFailures = await supabase
            .from('payment_webhook_events')
            .select('id')
            .eq('owner_id', user.id)
            .eq('processing_status', 'failed')
            .gte(
              'created_at',
              now.subtract(const Duration(days: 7)).toIso8601String(),
            );
        if (webhookFailures.isNotEmpty) {
          alerts.insert(0, {
            'id': 'payment_webhook_failures',
            'title':
                '${webhookFailures.length} Payment Update Failure${webhookFailures.length > 1 ? 's' : ''}',
            'message':
                'A PayMongo callback could not be applied; review the affected orders',
            'type': 'urgent',
            'icon': Icons.sync_problem_rounded,
            'color': AppColors.uiError,
            'time': now,
            'action': 'View Orders',
          });
        }
      } catch (e) {
        debugPrint('Payment callback monitoring not available yet: $e');
      }

      try {
        final syncFailures = await supabase
            .from('domain_events')
            .select('id')
            .eq('actor_id', user.id)
            .eq('event_type', 'DELIVERY_SYNC_FAILED')
            .gte(
              'created_at',
              now.subtract(const Duration(days: 7)).toIso8601String(),
            );
        if (syncFailures.isNotEmpty) {
          alerts.add({
            'id': 'delivery_sync_failures',
            'title':
                '${syncFailures.length} Offline Sync Failure${syncFailures.length > 1 ? 's' : ''}',
            'message':
                'Delivery log updates could not reach the server; open offline logs and sync again',
            'type': 'urgent',
            'icon': Icons.cloud_off_rounded,
            'color': AppColors.uiWarning,
            'time': now,
            'action': 'View Logs',
          });
        }
      } catch (e) {
        debugPrint('Delivery sync monitoring not available yet: $e');
      }
    } catch (e) {
      debugPrint('Error generating alerts: $e');
    }

    return alerts;
  }

  void _subscribeToNotifications() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _notificationSub = SafeSupabase.listen(
      supabase
          .from('system_notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id),
      (data) {
        if (mounted) {
          setState(() {
            _notifications = List<Map<String, dynamic>>.from(data);
          });
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Owner notifications stream error: $error');
        debugPrint('Owner notifications stream stack: $stackTrace');
      },
    );
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await supabase
          .from('system_notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase
          .from('system_notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);

      await _loadNotifications();
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications
        .where((n) => !(n['is_read'] ?? false))
        .length;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Notifications',
            subtitle: unreadCount > 0
                ? '$unreadCount unread system alerts'
                : 'System alerts and refill updates',
            actions: unreadCount > 0
                ? [
                    TextButton(
                      onPressed: _markAllAsRead,
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(
                          color: AppUi.bluePrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]
                : null,
          ),
          Expanded(
            child: _isLoading
                ? const AxoLoader(message: 'Loading notifications...')
                : SingleChildScrollView(
                    padding: AppUi.pagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // System Alerts Section
                        if (_systemAlerts.isNotEmpty) ...[
                          Text(
                            'System Alerts',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                          AppUi.vGapMd,
                          ..._systemAlerts.map(
                            (alert) => _buildAlertCard(alert),
                          ),
                          AppUi.vGapXl,
                        ],

                        // Notifications Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recent Notifications',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppUi.textPrimaryOf(context),
                              ),
                            ),
                            if (unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$unreadCount new',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        AppUi.vGapMd,
                        if (_notifications.isEmpty)
                          const SizedBox(
                            height: 220,
                            child: AxoEmptyState(
                              title: 'No notifications yet',
                              message:
                                  'Refill orders, payment updates, and delivery alerts will appear here.',
                              compact: true,
                            ),
                          )
                        else
                          ..._notifications.map((notification) {
                            final isRead = notification['is_read'] ?? false;
                            final type = notification['type'] ?? 'general';
                            final title =
                                (notification['title'] ?? 'Notification')
                                    .toString();
                            final message =
                                (notification['content'] ??
                                        notification['message'] ??
                                        '')
                                    .toString();
                            final createdAt = DateTime.tryParse(
                                  notification['created_at']?.toString() ?? '',
                                ) ??
                                DateTime.now();

                            return Container(
                              margin: const EdgeInsets.only(
                                bottom: AppUi.spacingSm,
                              ),
                              child: InkWell(
                                onTap: () {
                                  showNotificationDetailDialogFromMap(
                                    context,
                                    notification,
                                    onMarkRead: () {
                                      if (!isRead) {
                                        _markAsRead(notification['id']);
                                      }
                                    },
                                  );
                                },
                                borderRadius: AppUi.cardRadius,
                                child: Container(
                                  padding: AppUi.cardPadding,
                                  decoration: BoxDecoration(
                                    color: isRead
                                        ? AppUi.surfaceOf(context)
                                        : AppUi.bluePrimary.withValues(
                                            alpha: 0.08,
                                          ),
                                    borderRadius: AppUi.cardRadius,
                                    border: isRead
                                        ? Border.all(
                                            color: AppUi.borderOf(context),
                                          )
                                        : Border.all(
                                            color: AppUi.bluePrimary.withValues(
                                              alpha: 0.25,
                                            ),
                                          ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x06000000),
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: _getTypeColor(
                                            type,
                                          ).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          _getTypeIcon(type),
                                          color: _getTypeColor(type),
                                          size: 24,
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
                                              style: TextStyle(
                                                fontWeight: isRead
                                                    ? FontWeight.w600
                                                    : FontWeight.w800,
                                                fontSize: 15,
                                                color: AppUi.textPrimaryOf(context),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              message,
                                              style: TextStyle(
                                                color: AppUi.textSecondaryOf(context),
                                                fontSize: 13,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatTime(createdAt),
                                              style: TextStyle(
                                                color: AppUi.textSecondaryOf(context),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!isRead)
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: const BoxDecoration(
                                            color: AppUi.bluePrimary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (alert['color'] as Color).withValues(alpha: 0.1),
        borderRadius: AppUi.cardRadius,
        border: Border.all(
          color: (alert['color'] as Color).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (alert['color'] as Color).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              alert['icon'] as IconData,
              color: alert['color'] as Color,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert['title'],
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alert['message'],
                  style: TextStyle(
                    color: AppUi.textSecondaryOf(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              final action = alert['action']?.toString() ?? 'Open';
              if (action == 'View Logs') {
                
              } else {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.openOrderList();
                }
              }
            },
            child: Text(alert['action']),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'order':
        return OrderStatusColors.confirmed;
      case 'rider':
        return OrderStatusColors.outForDelivery;
      case 'system':
        return AppColors.brandPrimary;
      default:
        return AppUi.textSecondaryOf(context);
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'order':
        return Icons.receipt_long;
      case 'rider':
        return Icons.delivery_dining;
      case 'system':
        return Icons.info;
      default:
        return Icons.notifications;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
