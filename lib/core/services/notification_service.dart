import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../constants.dart';
import '../routing/app_router.dart';
import '../routing/app_routes.dart';
import '../../features/chat/models/system_notification.dart';

/// Local system-tray notifications and foreground in-app alerts for eRefill.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  OverlayEntry? _activeInAppOverlay;
  Timer? _inAppDismissTimer;

  /// The chat room ID currently active in the foreground, if any.
  /// When set, notifications for this chat room are suppressed so the user
  /// is not disturbed with banners while actively messaging in the room.
  String? activeChatRoomId;

  static const String _channelId = 'erefill_alerts';
  static const String _channelName = 'eRefill Notifications';
  static const String _channelDesc =
      'Real-time alerts for water refills, deliveries, orders, and chats.';

  /// Initialize system notification plugin and notification channels.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Android settings - matches brand launcher icon
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/launcher_icon',
      );

      // 2. iOS settings
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _localNotifs.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Register high-priority notification channel & request permissions on Android
      if (!kIsWeb && Platform.isAndroid) {
        final androidImpl = _localNotifs
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        const alertChannel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
          showBadge: true,
        );
        await androidImpl?.createNotificationChannel(alertChannel);

        final permissionGranted = await androidImpl
            ?.requestNotificationsPermission();
        if (permissionGranted == false) {
          debugPrint(
            'Notification permission is disabled; system notifications will not appear.',
          );
        }
      }

      // Handle cold start app launch via system notification tap
      final launchDetails = await _localNotifs.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchDetails?.notificationResponse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _onNotificationTapped(launchDetails!.notificationResponse!);
        });
      }

      _isInitialized = true;
      debugPrint('NotificationService initialized successfully.');
    } catch (e) {
      debugPrint('NotificationService initialization failed: $e');
    }
  }

  /// Handle notification tap from system notification tray.
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = jsonDecode(payload);
      final context = AppRouter.rootNavigatorKey.currentContext;
      if (context == null) return;

      if (data is Map) {
        final orderId = data['order_id']?.toString();
        final roomId = data['room_id']?.toString() ??
            data['chat_room_id']?.toString();
        final route = data['route']?.toString();

        if (orderId != null && orderId.isNotEmpty) {
          context.push(AppRoutes.orderById(orderId));
          return;
        }

        if (roomId != null && roomId.isNotEmpty) {
          context.push('${AppRoutes.chat}?roomId=$roomId');
          return;
        }

        if (route != null && route.isNotEmpty) {
          context.push(route);
          return;
        }
      }
      // Default fallback
      context.push(AppRoutes.notifications);
    } catch (e) {
      debugPrint('Failed to handle notification payload: $e');
    }
  }

  /// Show a local notification in the OS notification shade.
  Future<void> showSystemNotification({
    int? id,
    required String title,
    required String body,
    String? payload,
    NotificationPriority priority = NotificationPriority.high,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final notifId = id ??
          (payload != null
              ? payload.hashCode.abs() % 2147483647
              : DateTime.now().millisecondsSinceEpoch ~/ 1000);

      final androidPriority = switch (priority) {
        NotificationPriority.urgent => Priority.max,
        NotificationPriority.high => Priority.high,
        NotificationPriority.normal => Priority.defaultPriority,
        NotificationPriority.low => Priority.low,
      };

      final androidImportance = switch (priority) {
        NotificationPriority.urgent => Importance.max,
        NotificationPriority.high => Importance.high,
        NotificationPriority.normal => Importance.defaultImportance,
        NotificationPriority.low => Importance.low,
      };

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: androidImportance,
        priority: androidPriority,
        showWhen: true,
        icon: '@mipmap/launcher_icon',
        enableVibration: true,
        playSound: true,
        channelShowBadge: true,
        category: AndroidNotificationCategory.status,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _localNotifs.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Failed to show system notification: $e');
    }
  }

  /// Show an in-app heads-up floating notification banner at the top of the screen.
  void showInAppNotification({
    required String title,
    required String body,
    NotificationType? type,
    NotificationPriority priority = NotificationPriority.normal,
    String? payload,
    VoidCallback? onTap,
    Duration displayDuration = const Duration(seconds: 4),
  }) {
    final overlayState = AppRouter.rootNavigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    // Trigger haptic alert
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    // Dismiss existing banner if visible
    dismissInAppNotification();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _InAppBannerWidget(
          title: title,
          body: body,
          type: type ?? NotificationType.systemAlert,
          priority: priority,
          onDismiss: dismissInAppNotification,
          onTap: () {
            dismissInAppNotification();
            if (onTap != null) {
              onTap();
            } else if (payload != null && payload.isNotEmpty) {
              try {
                final data = jsonDecode(payload);
                if (data is Map) {
                  final orderId = data['order_id']?.toString();
                  final roomId = data['room_id']?.toString() ??
                      data['chat_room_id']?.toString();
                  final route = data['route']?.toString();

                  if (orderId != null && orderId.isNotEmpty) {
                    context.push(AppRoutes.orderById(orderId));
                    return;
                  }

                  if (roomId != null && roomId.isNotEmpty) {
                    context.push('${AppRoutes.chat}?roomId=$roomId');
                    return;
                  }

                  if (route != null && route.isNotEmpty) {
                    context.push(route);
                    return;
                  }
                }
              } catch (_) {}
              context.push(AppRoutes.notifications);
            } else {
              context.push(AppRoutes.notifications);
            }
          },
        );
      },
    );

    _activeInAppOverlay = entry;
    overlayState.insert(entry);

    _inAppDismissTimer = Timer(displayDuration, () {
      dismissInAppNotification();
    });
  }

  /// Dismiss the current in-app banner if any.
  void dismissInAppNotification() {
    _inAppDismissTimer?.cancel();
    _inAppDismissTimer = null;
    if (_activeInAppOverlay != null) {
      try {
        _activeInAppOverlay?.remove();
      } catch (_) {}
      _activeInAppOverlay = null;
    }
  }

  /// Convenience method to show BOTH system tray notification and in-app banner.
  Future<void> show({
    required String title,
    required String body,
    NotificationType type = NotificationType.systemAlert,
    NotificationPriority priority = NotificationPriority.high,
    String? payload,
    VoidCallback? onTap,
    bool showSystem = true,
    bool showInApp = true,
  }) async {
    if (showSystem) {
      await showSystemNotification(
        title: title,
        body: body,
        payload: payload,
        priority: priority,
      );
    }

    if (showInApp) {
      showInAppNotification(
        title: title,
        body: body,
        type: type,
        priority: priority,
        payload: payload,
        onTap: onTap,
      );
    }
  }
}

/// Floating Heads-Up Banner Widget
class _InAppBannerWidget extends StatefulWidget {
  final String title;
  final String body;
  final NotificationType type;
  final NotificationPriority priority;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _InAppBannerWidget({
    required this.title,
    required this.body,
    required this.type,
    required this.priority,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  State<_InAppBannerWidget> createState() => _InAppBannerWidgetState();
}

class _InAppBannerWidgetState extends State<_InAppBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _offsetAnimation =
        Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Dismissible(
            key: const Key('in_app_banner_dismiss'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismiss(),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.35 : 0.12,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: widget.type.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.type.icon,
                          color: widget.type.color,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white
                                          : AppUi.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Just now',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : AppUi.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: isDark
                                    ? const Color(0xFFCBD5E1)
                                    : AppUi.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : AppUi.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
