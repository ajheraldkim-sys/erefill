import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// High-performance disk-backed cache for instant screen rendering
/// across all roles (Customer, Owner, Rider, Admin).
///
/// Features:
/// 1. Instant synchronous/cached memory read on screen open (0ms).
/// 2. Asynchronous disk persistence via SharedPreferences.
/// 3. In-flight request deduplication so slow networks don't hammer the database.
/// 4. Graceful offline fallback when queries timeout or connectivity drops.
class LocalDataCache {
  LocalDataCache._internal();
  static final LocalDataCache instance = LocalDataCache._internal();

  static const String _prefix = 'erefill_disk_cache_';
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, Future<dynamic>> _inFlight = {};
  SharedPreferences? _prefs;

  SharedPreferences? get prefs => _prefs;

  /// Warm up cache on app launch so all screens load synchronously in 0ms.
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      for (final key in _prefs!.getKeys()) {
        if (key.startsWith(_prefix)) {
          final cleanKey = key.substring(_prefix.length);
          final raw = _prefs!.getString(key);
          if (raw != null) {
            try {
              _memoryCache[cleanKey] = jsonDecode(raw);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('LocalDataCache init error: $e');
    }
  }

  /// Synchronously get in-memory cached data if available (0ms).
  T? getMemory<T>(String key) {
    final val = _memoryCache[key];
    if (val is T) return val;
    if (val is Map && T == (Map<String, dynamic>)) {
      try {
        return Map<String, dynamic>.from(val) as T;
      } catch (_) {}
    }
    if (val is List && T == (List<Map<String, dynamic>>)) {
      try {
        return val.map((e) => Map<String, dynamic>.from(e as Map)).toList() as T;
      } catch (_) {}
    }
    if (val is List && T == (List<dynamic>)) {
      return List<dynamic>.from(val) as T;
    }
    return null;
  }

  /// Store data in memory immediately (synchronous 0ms).
  void setMemory(String key, dynamic value) {
    _memoryCache[key] = value;
  }

  /// Read data from memory or fallback to SharedPreferences disk cache.
  Future<T?> get<T>(String key) async {
    final mem = getMemory<T>(key);
    if (mem != null) return mem;

    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      _memoryCache[key] = decoded;
      return getMemory<T>(key);
    } catch (e) {
      debugPrint('LocalDataCache get error for $key: $e');
    }
    return null;
  }

  /// Store data in memory immediately and persist to disk in background.
  Future<void> set(String key, dynamic value) async {
    _memoryCache[key] = value;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      if (value == null) {
        await prefs.remove('$_prefix$key');
      } else {
        await prefs.setString('$_prefix$key', jsonEncode(value));
      }
    } catch (e) {
      debugPrint('LocalDataCache set error for $key: $e');
    }
  }

  /// Deduplicate concurrent network fetches while instantly returning or saving cache.
  Future<T> fetchWithCache<T>({
    required String key,
    required Future<T> Function() networkFetch,
    Duration? staleTimeout,
  }) async {
    // If request already in flight, reuse it
    if (_inFlight.containsKey(key)) {
      final res = await _inFlight[key];
      if (res is T) return res;
    }

    final future = networkFetch();
    _inFlight[key] = future;

    try {
      final result = await future;
      // Asynchronously cache result
      set(key, result);
      return result;
    } catch (e) {
      // On network failure or slow internet timeout, fallback to disk cache if available
      final cached = await get<T>(key);
      if (cached != null) {
        debugPrint('LocalDataCache: returned cached fallback for $key due to: $e');
        return cached;
      }
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Invalidate cache for a specific key
  Future<void> invalidate(String key) async {
    _memoryCache.remove(key);
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.remove('$_prefix$key');
    } catch (_) {}
  }

  /// Clear all cached data
  Future<void> clear() async {
    _memoryCache.clear();
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

