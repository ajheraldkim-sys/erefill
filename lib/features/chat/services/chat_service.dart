import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_room.dart';
import '../models/quick_reply.dart';
import '../models/system_notification.dart';
import 'chat_cache_service.dart';

/// Enhanced ChatService with room-based architecture
/// Supports all three roles: Customer, Rider, Owner
class ChatService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ChatCacheService _cache = ChatCacheService();

  // ==================== ROOM MANAGEMENT ====================

  /// Get all chat rooms for the current user
  Stream<List<ChatRoom>> getChatRoomsForUser() async* {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      yield [];
      return;
    }

    // A helper to fetch everything in one go with direct fallback and enrichment
    Future<List<ChatRoom>> fetchAll() async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      List<ChatRoom> rooms = [];
      try {
        final response = await _supabase.rpc('get_my_chat_rooms');
        if (response is List) {
          rooms = response.map((json) => ChatRoom.fromJson(json)).toList();
        }
      } catch (e) {
        debugPrint('Error fetching aggregated chat rooms via RPC: $e');
      }

      // If RPC returned nothing or failed, try direct table fetch
      if (rooms.isEmpty) {
        rooms = await _fetchRoomsDirect(userId);
      }

      // Enrich with participant profiles & order metadata
      final enriched = await _enrichRooms(rooms);
      _cache.cacheChatRooms(enriched);
      return enriched;
    }

    // Initial fetch from cache then RPC/direct
    final cached = await _cache.getCachedChatRooms();
    if (cached.isNotEmpty) yield cached;
    yield await fetchAll();

    // Throttled fetch to protect database from RPC storms during real-time bursts
    DateTime? lastFetchTime;
    Future<List<ChatRoom>> throttledFetchAll() async {
      final now = DateTime.now();
      if (lastFetchTime != null &&
          now.difference(lastFetchTime!).inMilliseconds < 1500) {
        return await _cache.getCachedChatRooms();
      }
      lastFetchTime = now;
      return await fetchAll();
    }

    // Listen for room updates with throttling
    yield* _supabase
        .from('chat_rooms')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false)
        .handleError((error, stackTrace) {
          debugPrint('Chat room stream error: $error');
          debugPrint('Chat room stream stack: $stackTrace');
          return <Map<String, dynamic>>[];
        })
        .asyncMap((_) => throttledFetchAll());
  }

  /// Get chat rooms by type for the current user
  Stream<List<ChatRoom>> getChatRoomsByType(ChatRoomType type) async* {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      yield [];
      return;
    }

    Future<List<ChatRoom>> fetchAndFilter() async {
      final all = await _fetchAllRoomsForUser(userId);
      return all.where((r) => r.roomType == type).toList();
    }

    // Yield filtered cache first
    final cached = await _cache.getCachedChatRooms();
    final typeFiltered = cached.where((r) => r.roomType == type).toList();
    if (typeFiltered.isNotEmpty) yield typeFiltered;
    yield await fetchAndFilter();

    DateTime? lastFilteredFetchTime;
    Future<List<ChatRoom>> throttledFetchAndFilter() async {
      final now = DateTime.now();
      if (lastFilteredFetchTime != null &&
          now.difference(lastFilteredFetchTime!).inMilliseconds < 1500) {
        final currentCached = await _cache.getCachedChatRooms();
        return currentCached.where((r) => r.roomType == type).toList();
      }
      lastFilteredFetchTime = now;
      return await fetchAndFilter();
    }

    // Listen for room updates with throttling
    yield* _supabase
        .from('chat_rooms')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false)
        .handleError((error, stackTrace) {
          debugPrint('Chat room filtered stream error: $error');
          debugPrint('Chat room filtered stream stack: $stackTrace');
          return <Map<String, dynamic>>[];
        })
        .asyncMap((_) => throttledFetchAndFilter());
  }

  Future<List<ChatRoom>> _fetchAllRoomsForUser(String userId) async {
    List<ChatRoom> rooms = [];
    try {
      final response = await _supabase.rpc('get_my_chat_rooms');
      if (response is List) {
        rooms = response.map((json) => ChatRoom.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching chat rooms by type RPC: $e');
    }

    if (rooms.isEmpty) {
      rooms = await _fetchRoomsDirect(userId);
    }

    final enriched = await _enrichRooms(rooms);
    _cache.cacheChatRooms(enriched);
    return enriched;
  }

  /// Get cached rooms for instant UI rendering
  Future<List<ChatRoom>> getCachedRooms() => _cache.getCachedChatRooms();

  /// Get a specific chat room by ID
  Future<ChatRoom?> getChatRoom(String roomId) async {
    try {
      final response = await _supabase
          .from('chat_rooms')
          .select()
          .eq('id', roomId)
          .single();

      final participants = await _getParticipants(roomId);
      final lastMessage = await _getLastMessage(roomId);

      final room = ChatRoom.fromJson({
        ...response,
        'participants': participants.map((p) => p.toJson()).toList(),
        'last_message': lastMessage?.toJson(),
      });

      final enriched = await _enrichRooms([room]);
      return enriched.first;
    } catch (e) {
      return null;
    }
  }

  /// Get or create order delivery chat room
  Future<ChatRoom> getOrCreateOrderChatRoom({
    required String orderId,
    required String customerId,
    required String ownerId,
    String? riderId,
  }) async {
    // 0. Pre-check: see if chat room for this order already exists
    try {
      final existing = await _supabase
          .from('chat_rooms')
          .select()
          .eq('reference_id', orderId)
          .maybeSingle();

      if (existing != null) {
        final roomId = existing['id'].toString();
        final currentUserId = _supabase.auth.currentUser?.id;
        if (currentUserId != null) {
          try {
            final myP = await _supabase
                .from('chat_participants')
                .select('id')
                .eq('room_id', roomId)
                .eq('user_id', currentUserId)
                .maybeSingle();
            if (myP == null) {
              await _supabase.from('chat_participants').insert({
                'room_id': roomId,
                'user_id': currentUserId,
                'role_in_room': currentUserId == ownerId
                    ? 'owner'
                    : (currentUserId == riderId ? 'rider' : 'customer'),
              });
            }
          } catch (_) {}
        }
        final participants = await _getParticipants(roomId);
        final room = ChatRoom.fromJson({
          ...Map<String, dynamic>.from(existing),
          'participants': participants.map((p) => p.toJson()).toList(),
        });
        final enriched = await _enrichRooms([room]);
        return enriched.first;
      }
    } catch (e) {
      debugPrint('Preliminary check for existing order chat room: $e');
    }

    // 1. Try RPC function to create/get chat room
    try {
      final rpcParams = <String, dynamic>{
        'p_order_id': orderId,
        'p_customer_id': customerId,
        'p_owner_id': ownerId,
      };
      if (riderId != null && riderId.isNotEmpty) {
        rpcParams['p_rider_id'] = riderId;
      }

      final response = await _supabase.rpc(
        'create_order_chat_room',
        params: rpcParams,
      );

      if (response != null && response is Map) {
        final roomData = Map<String, dynamic>.from(response);
        final participantsJson =
            roomData['participants'] as List<dynamic>? ?? [];
        final participants = <ChatParticipant>[];

        for (final p in participantsJson) {
          try {
            if (p is Map) {
              participants.add(
                  ChatParticipant.fromJson(Map<String, dynamic>.from(p)));
            }
          } catch (e) {
            debugPrint('Error parsing participant: $e');
          }
        }

        final roomJson = {
          'id': roomData['id']?.toString(),
          'room_type': roomData['room_type']?.toString() ?? 'order_delivery',
          'reference_id': roomData['reference_id']?.toString(),
          'owner_id': roomData['owner_id']?.toString(),
          'title': roomData['title']?.toString(),
          'status': roomData['status']?.toString() ?? 'active',
          'created_at': roomData['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'updated_at': roomData['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'participants': participants.map((p) => p.toJson()).toList(),
        };

        final room = ChatRoom.fromJson(roomJson);
        final enriched = await _enrichRooms([room]);
        return enriched.first;
      }
    } catch (e) {
      debugPrint(
          'create_order_chat_room RPC error, falling back to direct table: $e');
    }

    // Direct table fallback
    return await _getOrCreateOrderRoomDirect(
      orderId: orderId,
      customerId: customerId,
      ownerId: ownerId,
      riderId: riderId,
    );
  }

  /// Create customer support chat room
  Future<ChatRoom> createSupportChatRoom({
    required String customerId,
    required String ownerId,
    String? stationName,
  }) async {
    try {
      final response = await _supabase.rpc(
        'create_support_chat_room',
        params: {
          'p_customer_id': customerId,
          'p_owner_id': ownerId,
          'p_title':
              'Support Enquiry${stationName != null ? " - $stationName" : ""}',
        },
      );

      if (response != null && response is Map) {
        final roomData = Map<String, dynamic>.from(response);
        final roomId = roomData['id']?.toString();
        if (roomId != null) {
          final participants = await _getParticipants(roomId);
          final room = ChatRoom.fromJson({
            ...roomData,
            'participants': participants.map((p) => p.toJson()).toList(),
          });
          final enriched = await _enrichRooms([room]);
          return enriched.first;
        }
      }
    } catch (e) {
      debugPrint('create_support_chat_room RPC error, trying direct table fallback: $e');
    }

    // Direct table fallback
    return await _getOrCreateSupportRoomDirect(
      customerId: customerId,
      ownerId: ownerId,
      stationName: stationName,
    );
  }

  /// Archive a chat room (read-only)
  Future<void> archiveChatRoom(String roomId) async {
    await _supabase
        .from('chat_rooms')
        .update({
          'status': ChatRoomStatus.archived.value,
          'archived_at': DateTime.now().toIso8601String(),
        })
        .eq('id', roomId);
  }

  // ==================== MESSAGE MANAGEMENT ====================

  /// Get messages for a chat room
  Stream<List<Message>> getMessagesForRoom(String roomId) async* {
    // 1. Auto-sync: Instantly yield messages saved to local phone storage
    final cachedRows = await _cache.getCachedMessages(roomId);
    if (cachedRows.isNotEmpty) {
      yield await _messagesFromRows(
        cachedRows
            .where((row) => row['deleted_at'] == null)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(),
      );
    }

    // 2. Continuous real-time stream + save to local phone storage
    yield* _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .asyncMap((rows) async {
          // Fire-and-forget: save latest realtime data to local base
          _cache.cacheMessages(roomId, rows);

          return _messagesFromRows(
            rows
                .where((row) => row['deleted_at'] == null)
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
          );
        });
  }

  Future<List<Message>> _messagesFromRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final signedRows = await Future.wait(rows.map(_withSignedImageUrl));
    return signedRows.map((row) => Message.fromJson(row)).toList();
  }

  Future<Map<String, dynamic>> _withSignedImageUrl(
    Map<String, dynamic> row,
  ) async {
    final metadata = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    var imagePath = metadata['image_path']?.toString();
    final legacyImageUrl = metadata['image_url']?.toString();
    if ((imagePath == null || imagePath.isEmpty) &&
        legacyImageUrl != null &&
        legacyImageUrl.isNotEmpty) {
      const marker = '/chat_attachments/';
      final markerIndex = legacyImageUrl.indexOf(marker);
      if (markerIndex != -1) {
        imagePath = Uri.decodeFull(
          legacyImageUrl.substring(markerIndex + marker.length),
        );
      }
    }
    if (imagePath == null || imagePath.isEmpty) return row;

    try {
      metadata['image_url'] = await _supabase.storage
          .from('chat_attachments')
          .createSignedUrl(imagePath, 60 * 30);
      return {...row, 'metadata': metadata};
    } catch (e) {
      debugPrint('Could not sign chat attachment URL: $e');
      return row;
    }
  }

  /// Send a text message
  Future<void> sendMessage({
    required String roomId,
    required String content,
    MessageType type = MessageType.text,
    Map<String, dynamic> metadata = const {},
  }) async {
    final senderId = _supabase.auth.currentUser?.id;
    if (senderId == null) throw Exception('Not authenticated');

    await _supabase.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'message_type': type.value,
      'metadata': metadata,
    });
  }

  /// Send a system message
  Future<void> sendSystemMessage({
    required String roomId,
    required String content,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await _supabase.from('messages').insert({
        'room_id': roomId,
        'sender_id': null, // System message has no sender
        'content': content,
        'message_type': MessageType.system.value,
        'metadata': metadata,
      });
    } catch (e) {
      debugPrint('sendSystemMessage ignored due to policy or trigger: $e');
    }
  }

  /// Send a quick reply message (for riders)
  Future<void> sendQuickReplyMessage({
    required String roomId,
    required QuickReply quickReply,
  }) async {
    final senderId = _supabase.auth.currentUser?.id;
    if (senderId == null) throw Exception('Not authenticated');

    await _supabase.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'content': quickReply.messageText,
      'message_type': MessageType.quickReply.value,
      'metadata': {
        'quick_reply_id': quickReply.id,
        'quick_reply_label': quickReply.label,
      },
    });
  }

  /// Upload and send image message
  Future<void> sendImageMessage({
    required String roomId,
    required File file,
    required String fileName,
  }) async {
    final senderId = _supabase.auth.currentUser?.id;
    if (senderId == null) throw Exception('Not authenticated');

    // Upload to storage
    final path = 'chats/$roomId/$fileName';
    await _supabase.storage.from('chat_attachments').upload(path, file);
    // Send message
    await _supabase.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'content': 'Photo',
      'message_type': MessageType.image.value,
      'metadata': {'image_path': path},
    });
  }

  /// Delete specific messages (Soft Delete)
  Future<void> deleteMessages(List<String> messageIds) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    await _supabase
        .from('messages')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .inFilter('id', messageIds)
        .eq('sender_id', myId);
  }

  /// Clear all messages in a room (Soft Delete)
  Future<void> clearChat(String roomId) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    await _supabase
        .from('messages')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('room_id', roomId)
        .eq('sender_id', myId);
  }

  /// Mark all messages in a room as read
  Future<void> markAsRead(String roomId) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      await _supabase.rpc(
        'mark_messages_as_read',
        params: {'p_room_id': roomId, 'p_user_id': myId},
      );
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  // ==================== QUICK REPLIES (RIDER) ====================

  /// Get quick replies for current rider
  Future<List<QuickReply>> getQuickReplies() async {
    final riderId = _supabase.auth.currentUser?.id;
    if (riderId == null) return [];

    final response = await _supabase
        .from('quick_replies')
        .select()
        .eq('rider_id', riderId)
        .eq('is_active', true)
        .order('sort_order', ascending: true);

    return response.map((json) => QuickReply.fromJson(json)).toList();
  }

  /// Create a new quick reply
  Future<QuickReply> createQuickReply({
    required String label,
    required String messageText,
    int sortOrder = 0,
  }) async {
    final riderId = _supabase.auth.currentUser?.id;
    if (riderId == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('quick_replies')
        .insert({
          'rider_id': riderId,
          'label': label,
          'message_text': messageText,
          'sort_order': sortOrder,
        })
        .select()
        .single();

    return QuickReply.fromJson(response);
  }

  /// Update a quick reply
  Future<void> updateQuickReply(QuickReply quickReply) async {
    await _supabase
        .from('quick_replies')
        .update(quickReply.toInsertJson())
        .eq('id', quickReply.id);
  }

  /// Delete a quick reply
  Future<void> deleteQuickReply(String quickReplyId) async {
    await _supabase.from('quick_replies').delete().eq('id', quickReplyId);
  }

  // ==================== SYSTEM NOTIFICATIONS ====================

  /// Get notifications for current user
  Stream<List<SystemNotification>> getNotifications() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value([]);

    return _supabase
        .from('system_notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((json) => SystemNotification.fromJson(json))
              .where((n) => !n.isExpired)
              .toList(),
        );
  }

  /// Get unread notification count
  Future<int> getUnreadNotificationCount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 0;

    final response = await _supabase.rpc(
      'get_unread_notification_count',
      params: {'p_user_id': userId},
    );

    return response as int? ?? 0;
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    await _supabase.rpc(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
  }

  /// Mark all notifications as read
  Future<void> markAllNotificationsAsRead() async {
    await _supabase.rpc('mark_all_notifications_read');
  }

  /// Send broadcast to all riders (Owner only)
  Future<int> broadcastToRiders({
    required String title,
    required String content,
    NotificationType type = NotificationType.stationBroadcast,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    final response = await _supabase.rpc(
      'broadcast_to_riders',
      params: {
        'p_owner_id': _supabase.auth.currentUser?.id,
        'p_title': title,
        'p_content': content,
        'p_type': type.value,
        'p_priority': priority.value,
      },
    );

    return response as int? ?? 0;
  }

  // ==================== HELPER METHODS ====================

  Future<List<ChatParticipant>> _getParticipants(String roomId) async {
    try {
      final response = await _supabase
          .from('chat_participants')
          .select('*, profiles(full_name, username, avatar_url)')
          .eq('room_id', roomId);

      return (response as List)
          .map((json) => ChatParticipant.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching participants with profiles: $e');

      // Fallback: Fetch without profiles join
      final response = await _supabase
          .from('chat_participants')
          .select()
          .eq('room_id', roomId);

      final participants = <ChatParticipant>[];
      for (final json in (response as List)) {
        final p = ChatParticipant.fromJson(json);
        // Attempt to fetch profile separately for each participant if needed
        // but to keep it simple and avoid loading loops, just return basic info
        participants.add(p);
      }
      return participants;
    }
  }

  Future<Message?> _getLastMessage(String roomId) async {
    final response = await _supabase
        .from('messages')
        .select()
        .eq('room_id', roomId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return response != null ? Message.fromJson(response) : null;
  }

  /// Get user display name
  Future<String> getUserDisplayName(String userId) async {
    final res = await _supabase
        .from('profiles')
        .select('full_name, username')
        .eq('id', userId)
        .maybeSingle();

    if (res == null) return 'Unknown';
    final name = (res['full_name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    return (res['username'] as String?) ?? 'Unknown';
  }

  /// Get other participant in a 1:1 or order chat (for display)
  Future<Map<String, dynamic>?> getOtherParticipant(String roomId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await _supabase
        .from('chat_participants')
        .select('user_id, role_in_room, profiles(full_name, username)')
        .eq('room_id', roomId)
        .neq('user_id', userId)
        .limit(1)
        .maybeSingle();

    return response;
  }

  Future<List<ChatRoom>> _fetchRoomsDirect(String userId) async {
    try {
      final myParticipants = await _supabase
          .from('chat_participants')
          .select('room_id')
          .eq('user_id', userId);

      final roomIds = (myParticipants as List)
          .map((p) => p['room_id']?.toString())
          .whereType<String>()
          .toList();

      if (roomIds.isEmpty) return [];

      final rawRooms = await _supabase
          .from('chat_rooms')
          .select()
          .inFilter('id', roomIds)
          .order('updated_at', ascending: false);

      final rooms = <ChatRoom>[];
      for (final json in (rawRooms as List)) {
        try {
          rooms.add(ChatRoom.fromJson(json));
        } catch (_) {}
      }
      return rooms;
    } catch (e) {
      debugPrint('Direct rooms fetch error: $e');
      return [];
    }
  }

  Future<List<ChatRoom>> _enrichRooms(List<ChatRoom> rooms) async {
    if (rooms.isEmpty) return rooms;

    // 1. Collect rooms that need participants/profiles
    final needsParticipants = rooms
        .where((r) =>
            r.participants == null ||
            r.participants!.isEmpty ||
            r.participants!.every((p) => p.userProfile == null))
        .toList();

    final roomParticipantsMap = <String, List<ChatParticipant>>{};

    if (needsParticipants.isNotEmpty) {
      final roomIds = needsParticipants.map((r) => r.id).toList();
      try {
        final pData = await _supabase
            .from('chat_participants')
            .select(
                'id, room_id, user_id, role_in_room, joined_at, profiles(full_name, username, avatar_url)')
            .inFilter('room_id', roomIds);

        for (final row in (pData as List)) {
          final rId = row['room_id']?.toString();
          if (rId != null) {
            roomParticipantsMap
                .putIfAbsent(rId, () => [])
                .add(ChatParticipant.fromJson(row));
          }
        }
      } catch (e) {
        debugPrint('Error enriching chat participants: $e');
      }
    }

    // 2. Collect order delivery rooms to enrich customer & station name
    final orderRooms =
        rooms.where((r) => r.isOrderDelivery && r.referenceId != null).toList();
    final orderMap = <String, Map<String, dynamic>>{};
    if (orderRooms.isNotEmpty) {
      final orderIds =
          orderRooms.map((r) => r.referenceId!).toSet().toList();
      try {
        final ordersData = await _supabase
            .from('orders')
            .select('id, customer_name, station_name, assigned_rider_id')
            .inFilter('id', orderIds);
        for (final o in (ordersData as List)) {
          final oId = o['id']?.toString();
          if (oId != null) {
            orderMap[oId] = Map<String, dynamic>.from(o);
          }
        }
      } catch (e) {
        debugPrint('Error enriching order metadata: $e');
      }
    }

    // 3. Merge into rooms
    return rooms.map((room) {
      final participants =
          roomParticipantsMap[room.id] ?? room.participants;

      final metadata = Map<String, dynamic>.from(room.metadata);
      if (room.referenceId != null &&
          orderMap.containsKey(room.referenceId)) {
        final order = orderMap[room.referenceId]!;
        if (order['customer_name'] != null) {
          metadata['customer_name'] = order['customer_name'];
        }
        if (order['station_name'] != null) {
          metadata['station_name'] = order['station_name'];
        }
        if (order['assigned_rider_id'] != null) {
          metadata['assigned_rider_id'] = order['assigned_rider_id'];
        }
      }

      return room.copyWith(
        participants: participants,
        metadata: metadata,
      );
    }).toList();
  }

  Future<ChatRoom> _getOrCreateOrderRoomDirect({
    required String orderId,
    required String customerId,
    required String ownerId,
    String? riderId,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isOwner = currentUserId != null && currentUserId == ownerId;

    // 1. Check if room exists for this order
    Map<String, dynamic>? roomRow;
    String? roomId;

    try {
      final existing = await _supabase
          .from('chat_rooms')
          .select()
          .eq('reference_id', orderId)
          .maybeSingle();

      if (existing != null) {
        roomId = existing['id'].toString();
        roomRow = Map<String, dynamic>.from(existing);
      }
    } catch (e) {
      debugPrint('Direct check existing order room error: $e');
    }

    // 2. If room does not exist yet, attempt insert
    if (roomRow == null || roomId == null) {
      final preferredType = isOwner ? 'order_delivery' : 'customer_support';
      final fallbackType = isOwner ? 'customer_support' : 'order_delivery';

      Map<String, dynamic>? inserted;

      try {
        final res = await _supabase
            .from('chat_rooms')
            .insert({
              'reference_id': orderId,
              'room_type': preferredType,
              'owner_id': ownerId,
              'title': 'Refill Order Chat',
              'status': 'active',
            })
            .select()
            .single();
        inserted = Map<String, dynamic>.from(res);
      } catch (insertErr) {
        debugPrint('Direct chat room insert with $preferredType failed: $insertErr');
        try {
          final res2 = await _supabase
              .from('chat_rooms')
              .insert({
                'reference_id': orderId,
                'room_type': fallbackType,
                'owner_id': ownerId,
                'title': 'Refill Order Chat',
                'status': 'active',
              })
              .select()
              .single();
          inserted = Map<String, dynamic>.from(res2);
        } catch (insertErr2) {
          debugPrint('Direct chat room insert with $fallbackType failed: $insertErr2');
        }
      }

      if (inserted != null) {
        roomId = inserted['id'].toString();
        roomRow = inserted;
      } else {
        try {
          final recheck = await _supabase
              .from('chat_rooms')
              .select()
              .eq('reference_id', orderId)
              .maybeSingle();
          if (recheck != null) {
            roomId = recheck['id'].toString();
            roomRow = Map<String, dynamic>.from(recheck);
          }
        } catch (_) {}
      }
    }

    if (roomId == null || roomRow == null) {
      throw Exception('Could not initialize chat room for this order.');
    }

    // 3. Ensure current user is in participants first (authorized by RLS)
    if (currentUserId != null) {
      try {
        final existingP = await _supabase
            .from('chat_participants')
            .select('id')
            .eq('room_id', roomId)
            .eq('user_id', currentUserId)
            .maybeSingle();
        if (existingP == null) {
          final roleInRoom = isOwner
              ? 'owner'
              : (currentUserId == riderId ? 'rider' : 'customer');
          await _supabase.from('chat_participants').insert({
            'room_id': roomId,
            'user_id': currentUserId,
            'role_in_room': roleInRoom,
          });
        }
      } catch (e) {
        debugPrint('Error inserting current user as participant: $e');
      }
    }

    // 4. Try ensuring other participants
    final otherParticipants = [
      if (customerId != currentUserId)
        {'user_id': customerId, 'role_in_room': 'customer'},
      if (ownerId != currentUserId)
        {'user_id': ownerId, 'role_in_room': 'owner'},
      if (riderId != null && riderId.isNotEmpty && riderId != currentUserId)
        {'user_id': riderId, 'role_in_room': 'rider'},
    ];

    for (final p in otherParticipants) {
      try {
        final existingP = await _supabase
            .from('chat_participants')
            .select('id')
            .eq('room_id', roomId)
            .eq('user_id', p['user_id']!)
            .maybeSingle();
        if (existingP == null) {
          await _supabase.from('chat_participants').insert({
            'room_id': roomId,
            'user_id': p['user_id'],
            'role_in_room': p['role_in_room'],
          });
        }
      } catch (e) {
        debugPrint('Safe ignore - adding other participant: $e');
      }
    }

    final participants = await _getParticipants(roomId);
    final room = ChatRoom.fromJson({
      ...roomRow,
      'participants': participants.map((p) => p.toJson()).toList(),
    });

    final enriched = await _enrichRooms([room]);
    return enriched.first;
  }

  Future<ChatRoom> _getOrCreateSupportRoomDirect({
    required String customerId,
    required String ownerId,
    String? stationName,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isOwner = currentUserId != null && currentUserId == ownerId;

    // 1. Look for existing active support chat room
    Map<String, dynamic>? roomRow;
    String? roomId;

    try {
      final existing = await _supabase
          .from('chat_rooms')
          .select()
          .eq('owner_id', ownerId)
          .eq('room_type', 'customer_support')
          .eq('status', 'active')
          .maybeSingle();

      if (existing != null) {
        roomId = existing['id'].toString();
        roomRow = Map<String, dynamic>.from(existing);
      }
    } catch (e) {
      debugPrint('Direct check existing support room error: $e');
    }

    // 2. If none found, insert new support chat room
    if (roomRow == null || roomId == null) {
      final title =
          'Support Enquiry${stationName != null ? " - $stationName" : ""}';
      try {
        final inserted = await _supabase
            .from('chat_rooms')
            .insert({
              'room_type': 'customer_support',
              'owner_id': ownerId,
              'title': title,
              'status': 'active',
            })
            .select()
            .single();
        roomId = inserted['id'].toString();
        roomRow = Map<String, dynamic>.from(inserted);
      } catch (insertErr) {
        debugPrint('Support room direct insert error: $insertErr');
      }
    }

    if (roomId == null || roomRow == null) {
      throw Exception('Could not start support conversation with this station.');
    }

    // 3. Ensure current user is in participants
    if (currentUserId != null) {
      try {
        final existingP = await _supabase
            .from('chat_participants')
            .select('id')
            .eq('room_id', roomId)
            .eq('user_id', currentUserId)
            .maybeSingle();
        if (existingP == null) {
          await _supabase.from('chat_participants').insert({
            'room_id': roomId,
            'user_id': currentUserId,
            'role_in_room': isOwner ? 'owner' : 'customer',
          });
        }
      } catch (e) {
        debugPrint('Error inserting self into support room: $e');
      }
    }

    // 4. Try adding the other party
    final otherUserId = isOwner ? customerId : ownerId;
    final otherRole = isOwner ? 'customer' : 'owner';
    try {
      final existingOther = await _supabase
          .from('chat_participants')
          .select('id')
          .eq('room_id', roomId)
          .eq('user_id', otherUserId)
          .maybeSingle();
      if (existingOther == null) {
        await _supabase.from('chat_participants').insert({
          'room_id': roomId,
          'user_id': otherUserId,
          'role_in_room': otherRole,
        });
      }
    } catch (e) {
      debugPrint('Safe ignore - adding other party to support room: $e');
    }

    final participants = await _getParticipants(roomId);
    final room = ChatRoom.fromJson({
      ...roomRow,
      'participants': participants.map((p) => p.toJson()).toList(),
    });

    final enriched = await _enrichRooms([room]);
    return enriched.first;
  }
}
