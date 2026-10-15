import 'package:flutter/material.dart';
import 'package:erefill/core/theme/app_colors.dart';

enum NotificationType {
  orderAssigned,
  earningsPayout,
  systemAlert,
  stationBroadcast,
  orderCancelled,
  newMessage,
  deliveryReminder;

  String get value {
    switch (this) {
      case NotificationType.orderAssigned:
        return 'order_assigned';
      case NotificationType.earningsPayout:
        return 'earnings_payout';
      case NotificationType.systemAlert:
        return 'system_alert';
      case NotificationType.stationBroadcast:
        return 'station_broadcast';
      case NotificationType.orderCancelled:
        return 'order_cancelled';
      case NotificationType.newMessage:
        return 'new_message';
      case NotificationType.deliveryReminder:
        return 'delivery_reminder';
    }
  }

  static NotificationType fromString(String value) {
    switch (value) {
      case 'order_assigned':
        return NotificationType.orderAssigned;
      case 'earnings_payout':
        return NotificationType.earningsPayout;
      case 'system_alert':
        return NotificationType.systemAlert;
      case 'station_broadcast':
        return NotificationType.stationBroadcast;
      case 'order_cancelled':
        return NotificationType.orderCancelled;
      case 'new_message':
        return NotificationType.newMessage;
      case 'delivery_reminder':
        return NotificationType.deliveryReminder;
      default:
        return NotificationType.systemAlert;
    }
  }

  String get displayName {
    switch (this) {
      case NotificationType.orderAssigned:
        return 'New Order';
      case NotificationType.earningsPayout:
        return 'Earnings';
      case NotificationType.systemAlert:
        return 'System';
      case NotificationType.stationBroadcast:
        return 'Broadcast';
      case NotificationType.orderCancelled:
        return 'Cancelled';
      case NotificationType.newMessage:
        return 'Message';
      case NotificationType.deliveryReminder:
        return 'Reminder';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationType.orderAssigned:
        return Icons.local_shipping;
      case NotificationType.earningsPayout:
        return Icons.account_balance_wallet;
      case NotificationType.systemAlert:
        return Icons.info;
      case NotificationType.stationBroadcast:
        return Icons.campaign;
      case NotificationType.orderCancelled:
        return Icons.cancel;
      case NotificationType.newMessage:
        return Icons.message;
      case NotificationType.deliveryReminder:
        return Icons.access_time;
    }
  }

  Color get color {
    switch (this) {
      case NotificationType.orderAssigned:
        return AppColors.statusConfirmed;
      case NotificationType.earningsPayout:
        return AppColors.statusPending;
      case NotificationType.systemAlert:
        return AppColors.uiInfo;
      case NotificationType.stationBroadcast:
        return AppColors.brandPrimary;
      case NotificationType.orderCancelled:
        return AppColors.statusCancelled;
      case NotificationType.newMessage:
        return AppColors.brandPrimary;
      case NotificationType.deliveryReminder:
        return AppColors.statusOutForDelivery;
    }
  }
}

enum NotificationPriority {
  low,
  normal,
  high,
  urgent;

  String get value {
    switch (this) {
      case NotificationPriority.low:
        return 'low';
      case NotificationPriority.normal:
        return 'normal';
      case NotificationPriority.high:
        return 'high';
      case NotificationPriority.urgent:
        return 'urgent';
    }
  }

  static NotificationPriority fromString(String value) {
    switch (value) {
      case 'low':
        return NotificationPriority.low;
      case 'normal':
        return NotificationPriority.normal;
      case 'high':
        return NotificationPriority.high;
      case 'urgent':
        return NotificationPriority.urgent;
      default:
        return NotificationPriority.normal;
    }
  }

  Color get color {
    switch (this) {
      case NotificationPriority.low:
        return AppColors.statusNeutral;
      case NotificationPriority.normal:
        return AppColors.uiInfo;
      case NotificationPriority.high:
        return AppColors.uiWarning;
      case NotificationPriority.urgent:
        return AppColors.uiError;
    }
  }
}

class SystemNotification {
  final String id;
  final String userId;
  final NotificationType type;
  final NotificationPriority priority;
  final String title;
  final String content;
  final Map<String, dynamic> metadata;
  final bool isRead;
  final DateTime? readAt;
  final String? actionUrl;
  final DateTime createdAt;
  final DateTime? expiresAt;

  SystemNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.priority,
    required this.title,
    required this.content,
    this.metadata = const {},
    this.isRead = false,
    this.readAt,
    this.actionUrl,
    required this.createdAt,
    this.expiresAt,
  });

  factory SystemNotification.fromJson(Map<String, dynamic> json) {
    return SystemNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: NotificationType.fromString(json['type'] as String),
      priority: NotificationPriority.fromString(json['priority'] as String),
      title: json['title'] as String,
      content: json['content'] as String,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      actionUrl: json['action_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.value,
      'priority': priority.value,
      'title': title,
      'content': content,
      'metadata': metadata,
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'action_url': actionUrl,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isActionable => actionUrl != null && actionUrl!.isNotEmpty;

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  SystemNotification copyWith({
    String? id,
    String? userId,
    NotificationType? type,
    NotificationPriority? priority,
    String? title,
    String? content,
    Map<String, dynamic>? metadata,
    bool? isRead,
    DateTime? readAt,
    String? actionUrl,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return SystemNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      title: title ?? this.title,
      content: content ?? this.content,
      metadata: metadata ?? this.metadata,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      actionUrl: actionUrl ?? this.actionUrl,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  String toString() =>
      'SystemNotification(id: $id, type: ${type.displayName}, title: $title)';
}
