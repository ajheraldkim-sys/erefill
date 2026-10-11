import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_room.dart';

class ChatCacheService {
  static const String _roomsKeyPrefix = 'cached_chat_rooms_';

  String get _roomsKey {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    return '$_roomsKeyPrefix$userId';
  }

  Future<void> cacheChatRooms(List<ChatRoom> rooms) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> encodedRooms = rooms
        .map((r) => jsonEncode(r.toJson()))
        .toList();
    await prefs.setStringList(_roomsKey, encodedRooms);
  }

  Future<List<ChatRoom>> getCachedChatRooms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? encodedRooms = prefs.getStringList(_roomsKey);
      if (encodedRooms == null) return [];

      return encodedRooms
          .map((s) => ChatRoom.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roomsKey);
  }

  /// Clear all cached rooms for all users (use on full logout)
  Future<void> clearAllCaches() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (k) => k.startsWith(_roomsKeyPrefix) || k.startsWith('cached_msgs_'),
    );
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  // --- MESSAGES CACHE ---

  String _messagesKey(String roomId) => 'cached_msgs_$roomId';

  Future<void> cacheMessages(String roomId, List<dynamic> messages) async {
    final prefs = await SharedPreferences.getInstance();
    // Cap cache at latest 40 messages to prevent unbounded XML storage and memory bloat
    final recent = messages.length > 40
        ? messages.sublist(messages.length - 40)
        : messages;
    final List<String> encoded = recent.map((m) {
      try {
        return jsonEncode(m.toJson());
      } catch (_) {
        return jsonEncode(m);
      }
    }).toList();
    await prefs.setStringList(_messagesKey(roomId), encoded);
  }

  Future<List<dynamic>> getCachedMessages(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? encoded = prefs.getStringList(_messagesKey(roomId));
      if (encoded == null) return [];
      return encoded.map((s) => jsonDecode(s)).toList();
    } catch (e) {
      return [];
    }
  }
}
