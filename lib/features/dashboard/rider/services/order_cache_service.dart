import 'dart:convert';
import 'package:erefill/core/services/local_data_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderCacheService {
  static const String _activeOrdersPrefix = 'cached_active_orders_';
  static const String _historyPrefix = 'cached_history_orders_';

  String get _activeKey {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    return '$_activeOrdersPrefix$userId';
  }

  String get _historyKey {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    return '$_historyPrefix$userId';
  }

  /// Synchronously read cached active orders from memory for instant (0ms) render.
  List<Map<String, dynamic>> getCachedActiveOrdersSync() {
    try {
      final mem = LocalDataCache.instance.getMemory<List<Map<String, dynamic>>>(_activeKey);
      if (mem != null && mem.isNotEmpty) return mem;

      final prefs = LocalDataCache.instance.prefs;
      if (prefs != null) {
        final List<String>? encoded = prefs.getStringList(_activeKey);
        if (encoded != null && encoded.isNotEmpty) {
          final res = encoded.map((s) {
            final decoded = jsonDecode(s);
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
            return <String, dynamic>{};
          }).where((m) => m.isNotEmpty).toList();
          if (res.isNotEmpty) {
            LocalDataCache.instance.setMemory(_activeKey, res);
            return res;
          }
        }
      }
    } catch (_) {}
    return [];
  }

  Future<void> cacheActiveOrders(List<Map<String, dynamic>> orders) async {
    LocalDataCache.instance.setMemory(_activeKey, orders);
    await LocalDataCache.instance.set(_activeKey, orders);
    try {
      final prefs = LocalDataCache.instance.prefs ?? await SharedPreferences.getInstance();
      final List<String> encoded = orders.map((o) => jsonEncode(o)).toList();
      await prefs.setStringList(_activeKey, encoded);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getCachedActiveOrders() async {
    final syncRes = getCachedActiveOrdersSync();
    if (syncRes.isNotEmpty) return syncRes;

    try {
      final disk = await LocalDataCache.instance.get<List<Map<String, dynamic>>>(_activeKey);
      if (disk != null && disk.isNotEmpty) return disk;

      final prefs = LocalDataCache.instance.prefs ?? await SharedPreferences.getInstance();
      final List<String>? encoded = prefs.getStringList(_activeKey);
      if (encoded == null) return [];
      return encoded.map((s) {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        return <String, dynamic>{};
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Synchronously read cached history orders from memory for instant (0ms) render.
  List<Map<String, dynamic>> getCachedHistorySync() {
    try {
      final mem = LocalDataCache.instance.getMemory<List<Map<String, dynamic>>>(_historyKey);
      if (mem != null && mem.isNotEmpty) return mem;

      final prefs = LocalDataCache.instance.prefs;
      if (prefs != null) {
        final List<String>? encoded = prefs.getStringList(_historyKey);
        if (encoded != null && encoded.isNotEmpty) {
          final res = encoded.map((s) {
            final decoded = jsonDecode(s);
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
            return <String, dynamic>{};
          }).where((m) => m.isNotEmpty).toList();
          if (res.isNotEmpty) {
            LocalDataCache.instance.setMemory(_historyKey, res);
            return res;
          }
        }
      }
    } catch (_) {}
    return [];
  }

  Future<void> cacheHistory(List<Map<String, dynamic>> orders) async {
    LocalDataCache.instance.setMemory(_historyKey, orders);
    await LocalDataCache.instance.set(_historyKey, orders);
    try {
      final prefs = LocalDataCache.instance.prefs ?? await SharedPreferences.getInstance();
      final List<String> encoded = orders.map((o) => jsonEncode(o)).toList();
      await prefs.setStringList(_historyKey, encoded);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getCachedHistory() async {
    final syncRes = getCachedHistorySync();
    if (syncRes.isNotEmpty) return syncRes;

    try {
      final prefs = LocalDataCache.instance.prefs ?? await SharedPreferences.getInstance();
      final List<String>? encoded = prefs.getStringList(_historyKey);
      if (encoded == null) return [];
      return encoded.map((s) {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        return <String, dynamic>{};
      }).toList();
    } catch (e) {
      return [];
    }
  }
}
