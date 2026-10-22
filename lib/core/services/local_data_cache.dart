import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Persistent, disk-backed cache for instant screen rendering across all
/// roles (Customer, Owner, Rider, Admin).
///
/// Features:
/// 1. Every entry is loaded into memory by [init], so screens read cached data
///    synchronously on their first frame.
/// 2. Entries are persisted one row at a time in a local SQLite database, so a
///    large order list does not rewrite every other cached value on each save.
///    Where SQLite is unavailable (widget tests, desktop without FFI) it falls
///    back to SharedPreferences transparently.
/// 3. In-flight request deduplication so slow networks don't hammer the database.
/// 4. Graceful offline fallback when queries timeout or connectivity drops.
class LocalDataCache {
  LocalDataCache._internal();
  static final LocalDataCache instance = LocalDataCache._internal();

  static const String _prefix = 'erefill_disk_cache_';
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, Future<dynamic>> _inFlight = {};
  SharedPreferences? _prefs;
  _CacheStore? _store;
  Future<void>? _initFuture;

  SharedPreferences? get prefs => _prefs;

  /// Warm up cache on app launch so all screens load synchronously in 0ms.
  /// Safe to call more than once; later calls await the first.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('LocalDataCache prefs init error: $e');
    }
    final prefsStore = _PrefsCacheStore(_prefs);
    _CacheStore store = prefsStore;
    try {
      final sqlite = await _SqliteCacheStore.open();
      await _migrateFromPrefs(prefsStore, sqlite);
      store = sqlite;
    } catch (e) {
      debugPrint('LocalDataCache using SharedPreferences storage: $e');
    }
    _store = store;
    try {
      final rows = await store.loadAll();
      for (final entry in rows.entries) {
        try {
          // Values written before init finished are newer than disk.
          _memoryCache.putIfAbsent(entry.key, () => jsonDecode(entry.value));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('LocalDataCache init error: $e');
    }
  }

  /// Moves entries written by older app versions out of SharedPreferences.
  Future<void> _migrateFromPrefs(
    _PrefsCacheStore from,
    _SqliteCacheStore to,
  ) async {
    final legacy = await from.loadAll();
    if (legacy.isEmpty) return;
    await to.putAll(legacy);
    await from.clear();
  }

  Future<_CacheStore> _ready() async {
    await init();
    return _store ?? _PrefsCacheStore(_prefs);
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
        return val.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            as T;
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

  /// Read data from memory, or from disk if [init] has not finished yet.
  Future<T?> get<T>(String key) async {
    final mem = getMemory<T>(key);
    if (mem != null) return mem;

    try {
      final store = await _ready();
      // init may have loaded it into memory meanwhile.
      final loaded = getMemory<T>(key);
      if (loaded != null) return loaded;
      final raw = await store.read(key);
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
      final store = await _ready();
      if (value == null) {
        await store.remove(key);
      } else {
        await store.write(key, _encode(value));
      }
    } catch (e) {
      debugPrint('LocalDataCache set error for $key: $e');
    }
  }

  /// Encodes cache values defensively. Feature-level models may use a Set for
  /// in-memory de-duplication, but JSON supports lists only. This converter
  /// applies recursively through [jsonEncode].
  String _encode(dynamic value) {
    return jsonEncode(
      value,
      toEncodable: (nonEncodable) {
        if (nonEncodable is Set) {
          return nonEncodable.toList(growable: false);
        }
        if (nonEncodable is DateTime) {
          return nonEncodable.toIso8601String();
        }
        return (nonEncodable as dynamic).toJson();
      },
    );
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
        debugPrint(
          'LocalDataCache: returned cached fallback for $key due to: $e',
        );
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
      await (await _ready()).remove(key);
    } catch (_) {}
  }

  /// Invalidate all cache entries matching a prefix pattern
  Future<void> invalidatePattern(String prefix) async {
    _memoryCache.removeWhere((k, _) => k.startsWith(prefix));
    try {
      await (await _ready()).removePrefix(prefix);
    } catch (_) {}
  }

  /// Clear all cached data
  Future<void> clear() async {
    _memoryCache.clear();
    try {
      await (await _ready()).clear();
    } catch (_) {}
  }
}

abstract class _CacheStore {
  Future<Map<String, String>> loadAll();
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  Future<void> removePrefix(String prefix);
  Future<void> clear();
}

class _SqliteCacheStore implements _CacheStore {
  _SqliteCacheStore(this._db);
  final Database _db;

  static const _table = 'cache_entries';

  static Future<_SqliteCacheStore> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'erefill_cache.db'),
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE $_table ('
        'key TEXT PRIMARY KEY, '
        'value TEXT NOT NULL, '
        'updated_at INTEGER NOT NULL)',
      ),
    );
    return _SqliteCacheStore(db);
  }

  @override
  Future<Map<String, String>> loadAll() async {
    final rows = await _db.query(_table, columns: ['key', 'value']);
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  @override
  Future<String?> read(String key) async {
    final rows = await _db.query(
      _table,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> write(String key, String value) => _db.insert(_table, {
    'key': key,
    'value': value,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> putAll(Map<String, String> entries) async {
    final batch = _db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    entries.forEach((key, value) {
      batch.insert(_table, {
        'key': key,
        'value': value,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  @override
  Future<void> remove(String key) =>
      _db.delete(_table, where: 'key = ?', whereArgs: [key]);

  @override
  Future<void> removePrefix(String prefix) => _db.delete(
    _table,
    // substr avoids LIKE treating '_' in cache keys as a wildcard.
    where: 'substr(key, 1, ?) = ?',
    whereArgs: [prefix.length, prefix],
  );

  @override
  Future<void> clear() => _db.delete(_table);
}

class _PrefsCacheStore implements _CacheStore {
  _PrefsCacheStore(this._prefs);
  SharedPreferences? _prefs;

  static const _prefix = LocalDataCache._prefix;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<Map<String, String>> loadAll() async {
    final prefs = await _p;
    final out = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = prefs.getString(key);
      if (raw != null) out[key.substring(_prefix.length)] = raw;
    }
    return out;
  }

  @override
  Future<String?> read(String key) async => (await _p).getString('$_prefix$key');

  @override
  Future<void> write(String key, String value) async {
    await (await _p).setString('$_prefix$key', value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _p).remove('$_prefix$key');
  }

  @override
  Future<void> removePrefix(String prefix) async {
    final prefs = await _p;
    final full = '$_prefix$prefix';
    for (final k in prefs.getKeys().where((k) => k.startsWith(full)).toList()) {
      await prefs.remove(k);
    }
  }

  @override
  Future<void> clear() => removePrefix('');
}
