import 'dart:convert';
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

  Future<void> cacheActiveOrders(List<Map<String, dynamic>> orders) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> encoded = orders.map((o) => jsonEncode(o)).toList();
    await prefs.setStringList(_activeKey, encoded);
  }

  Future<List<Map<String, dynamic>>> getCachedActiveOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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

  Future<void> cacheHistory(List<Map<String, dynamic>> orders) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> encoded = orders.map((o) => jsonEncode(o)).toList();
    await prefs.setStringList(_historyKey, encoded);
  }

  Future<List<Map<String, dynamic>>> getCachedHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
