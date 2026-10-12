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

  /// Synchronously get in-memory cached data if available (0ms).
  T? getMemory<T>(String key) {
    final val = _memoryCache[key];
    if (val is T) return val;
    return null;
  }

  /// Read data from memory or fallback to SharedPreferences disk cache.
  Future<T?> get<T>(String key) async {
    if (_memoryCache.containsKey(key)) {
      final val = _memoryCache[key];
      if (val is T) return val;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      _memoryCache[key] = decoded;
      if (decoded is T) return decoded;
    } catch (e) {
      debugPrint('LocalDataCache get error for $key: $e');
    }
    return null;
  }

  /// Store data in memory immediately and persist to disk in background.
  Future<void> set(String key, dynamic value) async {
    _memoryCache[key] = value;
    try {
      final prefs = await SharedPreferences.getInstance();
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (_) {}
  }

  /// Clear all cached data
  Future<void> clear() async {
    _memoryCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

