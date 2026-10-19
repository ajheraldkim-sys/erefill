import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/providers/notification_provider.dart';
import 'package:erefill/core/widgets/notification_detail_dialog.dart';
import 'package:erefill/features/chat/models/system_notification.dart';

void showNotificationPreviewSheet(
  BuildContext context, {
  required VoidCallback onViewAll,
}) {
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
              const _NotificationSheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Consumer<NotificationProvider>(
                      builder: (context, provider, _) => TextButton(
                        onPressed: provider.unreadCount == 0
                            ? null
                            : provider.markAllAsRead,
                        child: const Text('Mark all read'),
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
                child: Consumer<NotificationProvider>(
                  builder: (context, provider, _) {
                    if (provider.isLoading) {
                      return const Center(
                        child: CircularProgressIndicator.adaptive(),
                      );
                    }
                    if (provider.notifications.isEmpty) {
                      return const _NotificationSheetEmptyState();
                    }
                    final notifications = provider.notifications.take(8);
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: notifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final notification = notifications.elementAt(index);
                        return _NotificationPreviewTile(
                          notification: notification,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            showNotificationDetailDialog(
                              context,
                              notification: notification,
                            );
                          },
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
                      onViewAll();
                    },
                    child: const Text('View all notifications'),
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

class _NotificationSheetHandle extends StatelessWidget {
  const _NotificationSheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      decoration: BoxDecoration(
        color: AppUi.textMuted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppUi.radiusFull),
      ),
    );
  }
}

class _NotificationSheetEmptyState extends StatelessWidget {
  const _NotificationSheetEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 34,
              color: AppUi.textMuted,
            ),
            const SizedBox(height: 10),
            const Text(
              'You’re all caught up.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppUi.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationPreviewTile extends StatelessWidget {
  final SystemNotification notification;
  final VoidCallback onTap;

  const _NotificationPreviewTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = notification.type.color;
    return Material(
      color: notification.isRead
          ? AppUi.pageBgOf(context)
          : color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppUi.radiusSheet),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                ),
                child: Icon(notification.type.icon, color: color, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppUi.bluePrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppUi.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notification.formattedTime,
                      style: const TextStyle(
                        color: AppUi.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
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
}
