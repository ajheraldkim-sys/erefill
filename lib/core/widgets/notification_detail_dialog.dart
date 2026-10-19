import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../providers/notification_provider.dart';
import '../routing/app_navigation.dart';
import '../../features/chat/models/chat_room.dart';
import '../../features/chat/models/system_notification.dart';

/// Shows a rich popup dialog displaying the full details of a notification.
Future<void> showNotificationDetailDialog(
  BuildContext context, {
  required SystemNotification notification,
  VoidCallback? onMarkRead,
}) async {
  // Automatically mark notification as read upon viewing
  if (!notification.isRead) {
    try {
      context.read<NotificationProvider>().markAsRead(notification.id);
    } catch (_) {}
    onMarkRead?.call();
  }

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Notification Detail',
    barrierColor: Colors.black.withValues(alpha: 0.54),
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1.0).animate(curvedAnimation),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final type = notification.type;
      final typeColor = type.color;
      final formattedDate =
          DateFormat('MMM d, yyyy · h:mm a').format(notification.createdAt);
      final timeAgo = notification.formattedTime;

      final metadata = notification.metadata;
      final orderId = metadata['order_id']?.toString() ??
          metadata['orderId']?.toString();
      final roomId = metadata['room_id']?.toString() ??
          metadata['chat_room_id']?.toString();
      final status = metadata['status']?.toString();
      final amount = metadata['amount'] ?? metadata['total'];
      final stationName = metadata['station_name']?.toString() ??
          metadata['stationName']?.toString();

      return Dialog(
        backgroundColor: AppUi.surfaceOf(dialogContext),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusPill),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top header with Icon, Type Pill, Time & Close button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      alignment: Alignment.center,
                      child: Icon(type.icon, color: typeColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(AppUi.radiusSm),
                                ),
                                child: Text(
                                  type.displayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: typeColor,
                                  ),
                                ),
                              ),
                              if (notification.priority ==
                                      NotificationPriority.high ||
                                  notification.priority ==
                                      NotificationPriority.urgent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: notification.priority.color
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(AppUi.radiusSm),
                                  ),
                                  child: Text(
                                    notification.priority.value.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: notification.priority.color,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$formattedDate ($timeAgo)',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppUi.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppUi.textSecondaryOf(dialogContext),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Title
                Text(
                  notification.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(dialogContext),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),

                // Full message content
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      notification.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppUi.textSecondaryOf(dialogContext),
                        height: 1.5,
                      ),
                    ),
                  ),
                ),

                // Contextual Metadata Card (if order or amounts present)
                if (orderId != null ||
                    status != null ||
                    amount != null ||
                    stationName != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppUi.pageBgOf(dialogContext),
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      border: Border.all(
                        color: AppUi.borderOf(dialogContext),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (orderId != null)
                          _buildDetailRow(
                            'Order ID',
                            '#${orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId}',
                          ),
                        if (stationName != null) ...[
                          const SizedBox(height: 6),
                          _buildDetailRow('Station', stationName),
                        ],
                        if (status != null) ...[
                          const SizedBox(height: 6),
                          _buildDetailRow('Status', status.toUpperCase()),
                        ],
                        if (amount != null) ...[
                          const SizedBox(height: 6),
                          _buildDetailRow(
                            'Amount',
                            '₱${amount is num ? amount.toStringAsFixed(2) : amount}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppUi.radiusCard),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                    if (orderId != null && orderId.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            context.openOrderById(orderId);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppUi.bluePrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppUi.radiusCard),
                            ),
                          ),
                          child: const Text('View Order'),
                        ),
                      ),
                    ] else if (roomId != null && roomId.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            context.openChat(
                              roomId: roomId,
                              roomTitle: notification.title,
                              roomType: ChatRoomType.orderDelivery,
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppUi.bluePrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppUi.radiusCard),
                            ),
                          ),
                          child: const Text('Open Chat'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Helper to show notification details when working with raw database map rows.
Future<void> showNotificationDetailDialogFromMap(
  BuildContext context,
  Map<String, dynamic> map, {
  VoidCallback? onMarkRead,
}) {
  final notification = SystemNotification(
    id: map['id']?.toString() ?? '',
    userId: map['user_id']?.toString() ?? '',
    type: NotificationType.fromString(map['type']?.toString() ?? 'system_alert'),
    priority: NotificationPriority.fromString(
      map['priority']?.toString() ?? 'normal',
    ),
    title: (map['title'] ?? 'Notification').toString(),
    content: (map['content'] ?? map['message'] ?? '').toString(),
    metadata: (map['metadata'] as Map<String, dynamic>?) ?? {},
    isRead: map['is_read'] == true,
    actionUrl: map['action_url']?.toString(),
    createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );

  return showNotificationDetailDialog(
    context,
    notification: notification,
    onMarkRead: onMarkRead,
  );
}

Widget _buildDetailRow(String label, String value) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppUi.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(
        value,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
