import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/features/chat/models/system_notification.dart';
import 'package:erefill/core/services/notification_service.dart';
import 'package:erefill/core/services/local_data_cache.dart';

class NotificationProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<SystemNotification> _notifications = [];
  bool _isLoading = true;
  StreamSubscription? _notifSub;
  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _ordersChannel;
  final Set<String> _knownIds = {};
  bool _initialLoadCompleted = false;
  int _listenGeneration = 0;

  int _unreadChatCount = 0;
  int _newOrdersCount = 0;

  List<SystemNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  int get unreadChatCount => _unreadChatCount;
  int get newOrdersCount => _newOrdersCount;

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
        _unreadChatCount = 0;
        _newOrdersCount = 0;
        _initialLoadCompleted = false;
        _isLoading = false;
        _cleanupChannels();
        _notifSub?.cancel();
        _notifSub = null;
        notifyListeners();
      }
    });
  }

  void _cleanupChannels() {
    if (_messagesChannel != null) {
      _supabase.removeChannel(_messagesChannel!);
      _messagesChannel = null;
    }
    if (_ordersChannel != null) {
      _supabase.removeChannel(_ordersChannel!);
      _ordersChannel = null;
    }
  }

  Future<void> _fetchAndListen(String userId) async {
    final generation = ++_listenGeneration;
    await _notifSub?.cancel();
    _cleanupChannels();
    if (generation != _listenGeneration) return;

    final cacheKey = 'system_notifications_$userId';
    final chatCacheKey = 'unread_chat_count_$userId';
    final ordersCacheKey = 'new_orders_count_$userId';

    // 0ms instant offline load from disk
    final cached = await LocalDataCache.instance.get<List<dynamic>>(cacheKey);
    final cachedChat = await LocalDataCache.instance.get<int>(chatCacheKey);
    final cachedOrders = await LocalDataCache.instance.get<int>(ordersCacheKey);

    if (generation == _listenGeneration) {
      if (cachedChat != null) _unreadChatCount = cachedChat;
      if (cachedOrders != null) _newOrdersCount = cachedOrders;

      if (cached != null && cached.isNotEmpty) {
        final list = cached
            .map((item) =>
                SystemNotification.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _notifications = list;
        _knownIds.addAll(list.map((n) => n.id));
        _isLoading = false;
        notifyListeners();
      } else {
        _isLoading = true;
        _initialLoadCompleted = false;
        _knownIds.clear();
        _notifications = [];
        notifyListeners();
      }
    }

    // Subscribe to system notifications stream
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

          bool hasNewMessages = false;
          bool hasNewOrders = false;

          if (_initialLoadCompleted) {
            for (final notification in incoming) {
              if (!_knownIds.contains(notification.id) &&
                  !notification.isRead) {
                final roomId = notification.metadata['room_id']?.toString() ??
                    notification.metadata['chat_room_id']?.toString();

                final isActiveChat =
                    notification.type == NotificationType.newMessage &&
                        roomId != null &&
                        NotificationService.instance.activeChatRoomId == roomId;

                final payloadJson = jsonEncode({
                  'notification_id': notification.id,
                  'order_id': notification.metadata['order_id'],
                  'room_id': roomId,
                  'route': notification.actionUrl,
                });

                if (!isActiveChat) {
                  await NotificationService.instance.show(
                    title: notification.title,
                    body: notification.content,
                    type: notification.type,
                    priority: notification.priority,
                    payload: payloadJson,
                  );
                }

                if (notification.type == NotificationType.newMessage) {
                  hasNewMessages = true;
                }
                if (notification.type == NotificationType.orderAssigned) {
                  hasNewOrders = true;
                }
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

          unawaited(
            LocalDataCache.instance.set(
              cacheKey,
              incoming.map((n) => n.toJson()).toList(),
            ),
          );

          if (hasNewMessages || hasNewOrders) {
            _fetchNotificationCounts(userId, generation);
          }
        },
        onError: (error, stackTrace) {
          debugPrint('Notification stream error: $error (resilient REST fallback active)');
          if (generation == _listenGeneration) {
            _isLoading = false;
            notifyListeners();
            _fetchNotificationsRest(userId, generation);
          }
        },
      );

      _fetchNotificationsRest(userId, generation);
      _fetchNotificationCounts(userId, generation);
      _setupRealtimeChannels(userId, generation);
    } catch (e) {
      debugPrint('Error in NotificationProvider: $e');
      _isLoading = false;
      notifyListeners();
      _fetchNotificationsRest(userId, generation);
      _fetchNotificationCounts(userId, generation);
    }
  }

  void _setupRealtimeChannels(String userId, int generation) {
    try {
      _messagesChannel = _supabase
          .channel('rt_messages_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (payload) {
              if (generation == _listenGeneration) {
                _fetchNotificationCounts(userId, generation);
              }
            },
          )
          .subscribe();

      _ordersChannel = _supabase
          .channel('rt_orders_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (payload) {
              if (generation == _listenGeneration) {
                _fetchNotificationCounts(userId, generation);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Error setting up notification realtime channels: $e');
    }
  }

  Future<void> refreshCounts() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _fetchNotificationCounts(userId, _listenGeneration);
  }

  Future<void> _fetchNotificationCounts(String userId, int generation) async {
    if (generation != _listenGeneration) return;

    try {
      final dynamic res = await _supabase.rpc('get_user_notification_counts');
      if (generation != _listenGeneration) return;

      if (res is Map) {
        final parsedChats = (res['unread_chats'] as num?)?.toInt() ?? 0;
        final parsedOrders = (res['new_orders'] as num?)?.toInt() ?? 0;

        _unreadChatCount = parsedChats;
        _newOrdersCount = parsedOrders;
        notifyListeners();

        unawaited(
          LocalDataCache.instance.set('unread_chat_count_$userId', _unreadChatCount),
        );
        unawaited(
          LocalDataCache.instance.set('new_orders_count_$userId', _newOrdersCount),
        );
        return;
      }
    } catch (_) {
      // get_user_notification_counts RPC not present; fallback below takes over
    }

    // Resilient Fallback 1: get_total_unread_chat_count RPC
    try {
      final chatRes = await _supabase.rpc('get_total_unread_chat_count');
      if (generation != _listenGeneration) return;
      _unreadChatCount = (chatRes as num?)?.toInt() ?? 0;
    } catch (_) {
      // Direct message query fallback
      try {
        final unreadRes = await _supabase
            .from('messages')
            .select('id')
            .neq('sender_id', userId)
            .not('read_by', 'cs', '{"$userId"}')
            .limit(100);
        if (generation == _listenGeneration) {
          _unreadChatCount = (unreadRes as List).length;
        }
      } catch (_) {}
    }

    // Resilient Fallback 2: get_station_new_orders_count RPC
    try {
      final ordersRes = await _supabase.rpc('get_station_new_orders_count');
      if (generation != _listenGeneration) return;
      _newOrdersCount = (ordersRes as num?)?.toInt() ?? 0;
    } catch (_) {
      // Direct orders query fallback
      try {
        final pendingRes = await _supabase
            .from('orders')
            .select('id')
            .eq('status', 'pending')
            .isFilter('owner_acknowledged_at', null)
            .limit(100);
        if (generation == _listenGeneration) {
          _newOrdersCount = (pendingRes as List).length;
        }
      } catch (_) {}
    }

    if (generation == _listenGeneration) {
      notifyListeners();
      unawaited(
        LocalDataCache.instance.set('unread_chat_count_$userId', _unreadChatCount),
      );
      unawaited(
        LocalDataCache.instance.set('new_orders_count_$userId', _newOrdersCount),
      );
    }
  }

  Future<void> acknowledgeOrder(String orderId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.rpc('acknowledge_order', params: {'p_order_id': orderId});
    } catch (e) {
      try {
        await _supabase.from('orders').update({
          'owner_acknowledged_at': DateTime.now().toIso8601String(),
        }).eq('id', orderId);
      } catch (err) {
        debugPrint('Failed to acknowledge order $orderId: $err');
      }
    }

    if (_newOrdersCount > 0) {
      _newOrdersCount = (_newOrdersCount - 1).clamp(0, 999999);
      notifyListeners();
    }
    _fetchNotificationCounts(userId, _listenGeneration);
  }

  Future<void> _fetchNotificationsRest(String userId, int generation) async {
    try {
      final res = await _supabase
          .from('system_notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      if (generation != _listenGeneration) return;
      final list = (res as List)
          .map((json) => SystemNotification.fromJson(json as Map<String, dynamic>))
          .toList();
      _knownIds
        ..clear()
        ..addAll(list.map((n) => n.id));
      _notifications = list;
      _initialLoadCompleted = true;
      _isLoading = false;
      notifyListeners();
      unawaited(
        LocalDataCache.instance.set(
          'system_notifications_$userId',
          list.map((n) => n.toJson()).toList(),
        ),
      );
    } catch (e) {
      debugPrint('Error fetching notifications via REST: $e');
    }
  }

  /// Trigger a manual local OS notification and in-app banner.
  Future<void> notifyLocal({
    required String title,
    required String body,
    NotificationType type = NotificationType.systemAlert,
    NotificationPriority priority = NotificationPriority.high,
    String? orderId,
    String? roomId,
    String? route,
    VoidCallback? onTap,
  }) async {
    final payload = <String, dynamic>{};
    if (orderId != null) payload['order_id'] = orderId;
    if (roomId != null) payload['room_id'] = roomId;
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
    final userId = _supabase.auth.currentUser?.id;
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
        if (userId != null) {
          unawaited(
            LocalDataCache.instance.set(
              'system_notifications_$userId',
              _notifications.map((n) => n.toJson()).toList(),
            ),
          );
        }
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
      unawaited(
        LocalDataCache.instance.set(
          'system_notifications_$userId',
          _notifications.map((n) => n.toJson()).toList(),
        ),
      );
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  @override
  void dispose() {
    _listenGeneration++;
    _cleanupChannels();
    _notifSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
