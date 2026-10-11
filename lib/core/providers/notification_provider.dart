import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/features/chat/models/system_notification.dart';
import 'package:erefill/core/services/notification_service.dart';

class NotificationProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<SystemNotification> _notifications = [];
  bool _isLoading = true;
  StreamSubscription? _notifSub;
  StreamSubscription<AuthState>? _authSub;
  final Set<String> _knownIds = {};
  bool _initialLoadCompleted = false;
  int _listenGeneration = 0;

  List<SystemNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  NotificationProvider() {
    _init();
  }

  void _init() {
    // Ensure NotificationService is initialized
    NotificationService.instance.initialize().catchError((e) {
      debugPrint('NotificationService init error in provider: $e');
    });

    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      _fetchAndListen(userId);
    }

    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final user = session?.user;
      if (user != null) {
        _fetchAndListen(user.id);
      } else {
        _listenGeneration++;
        _notifications = [];
        _knownIds.clear();
        _initialLoadCompleted = false;
        _isLoading = false;
        _notifSub?.cancel();
        _notifSub = null;
        notifyListeners();
      }
    });
  }

  Future<void> _fetchAndListen(String userId) async {
    final generation = ++_listenGeneration;
    await _notifSub?.cancel();
    if (generation != _listenGeneration) return;

    _isLoading = true;
    _initialLoadCompleted = false;
    _knownIds.clear();
    _notifications = [];
    notifyListeners();

    try {
      _notifSub = SafeSupabase.listen(
        _supabase
            .from('system_notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', userId),
        (data) async {
          if (generation != _listenGeneration) return;

          final incoming = data
              .map((json) => SystemNotification.fromJson(json))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (_initialLoadCompleted) {
            for (final notification in incoming) {
              if (!_knownIds.contains(notification.id) &&
                  !notification.isRead) {
                final payloadJson = jsonEncode({
                  'notification_id': notification.id,
                  'order_id': notification.metadata['order_id'],
                  'route': notification.actionUrl,
                });
                await NotificationService.instance.show(
                  title: notification.title,
                  body: notification.content,
                  type: notification.type,
                  priority: notification.priority,
                  payload: payloadJson,
                );
              }
            }
          }

          _knownIds
            ..clear()
            ..addAll(incoming.map((notification) => notification.id));
          _notifications = incoming;
          _initialLoadCompleted = true;
          _isLoading = false;
          notifyListeners();
        },
        onError: (error, stackTrace) {
          debugPrint('Notification stream error: $error');
          debugPrint('Notification stream stack: $stackTrace');
          if (generation == _listenGeneration) {
            _isLoading = false;
            notifyListeners();
          }
        },
      );
    } catch (e) {
      debugPrint('Error in NotificationProvider: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Trigger a manual local OS notification and in-app banner.
  Future<void> notifyLocal({
    required String title,
    required String body,
    NotificationType type = NotificationType.systemAlert,
    NotificationPriority priority = NotificationPriority.high,
    String? orderId,
    String? route,
    VoidCallback? onTap,
  }) async {
    final payload = <String, dynamic>{};
    if (orderId != null) payload['order_id'] = orderId;
    if (route != null) payload['route'] = route;
    final payloadJson = jsonEncode(payload);

    await NotificationService.instance.show(
      title: title,
      body: body,
      type: type,
      priority: priority,
      payload: payloadJson,
      onTap: onTap,
    );
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase
          .from('system_notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId);

      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        _notifications[index] = _notifications[index].copyWith(
          isRead: true,
          readAt: DateTime.now(),
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase
          .from('system_notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('is_read', false);

      _notifications = _notifications
          .map((n) => n.copyWith(isRead: true, readAt: DateTime.now()))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  @override
  void dispose() {
    _listenGeneration++;
    _notifSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
