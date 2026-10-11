import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Service responsible for offline-first order persistence and
/// automatic background synchronization when internet connectivity returns.
class OfflineOrderSyncService {
  static const String _dbName = 'erefill_offline_orders.db';
  static const int _dbVersion = 1;
  static const String tableOfflineOrders = 'offline_orders';

  static final OfflineOrderSyncService _instance =
      OfflineOrderSyncService._internal();
  factory OfflineOrderSyncService() => _instance;
  OfflineOrderSyncService._internal();

  Database? _db;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;
  final _uuid = const Uuid();

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableOfflineOrders (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            station_id TEXT NOT NULL,
            station_name TEXT,
            items_json TEXT NOT NULL,
            total_amount REAL NOT NULL,
            subtotal REAL NOT NULL,
            delivery_fee REAL DEFAULT 0,
            platform_fee REAL DEFAULT 0,
            delivery_address TEXT,
            payment_method TEXT NOT NULL,
            notes TEXT,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            error_message TEXT
          )
        ''');
      },
    );
  }

  /// Starts listening to global network changes to automatically trigger sync.
  void initializeConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final hasConnection = results.contains(ConnectivityResult.mobile) ||
            results.contains(ConnectivityResult.wifi) ||
            results.contains(ConnectivityResult.ethernet);

        if (hasConnection && !_isSyncing) {
          debugPrint(
            '🌐 Network connection active: Triggering offline order synchronization...',
          );
          syncPendingOrders();
        }
      },
    );
  }

  /// Queues an order locally in SQLite with a unique client-side UUID.
  ///
  /// Guarantees that even if the customer has no cell signal, the order is safely
  /// persisted with zero lag.
  Future<String> queueOfflineOrder({
    required String customerId,
    required String stationId,
    required String stationName,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double subtotal,
    required double deliveryFee,
    required double platformFee,
    required String deliveryAddress,
    required String paymentMethod,
    String? notes,
  }) async {
    final localDatabase = await db;
    final orderId = _uuid.v4();
    final nowIso = DateTime.now().toIso8601String();
    final itemsJson = jsonEncode(items);

    await localDatabase.insert(
      tableOfflineOrders,
      {
        'id': orderId,
        'customer_id': customerId,
        'station_id': stationId,
        'station_name': stationName,
        'items_json': itemsJson,
        'total_amount': totalAmount,
        'subtotal': subtotal,
        'delivery_fee': deliveryFee,
        'platform_fee': platformFee,
        'delivery_address': deliveryAddress,
        'payment_method': paymentMethod,
        'notes': notes,
        'status': 'pending_sync',
        'created_at': nowIso,
        'error_message': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('📦 Offline order queued locally in SQLite: $orderId');

    // Attempt an immediate background sync if network is currently available
    unawaited(syncPendingOrders());

    return orderId;
  }

  /// Synchronizes all pending orders to Supabase cloud.
  Future<void> syncPendingOrders() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final supabase = Supabase.instance.client;
      final localDatabase = await db;

      final pendingRows = await localDatabase.query(
        tableOfflineOrders,
        where: 'status = ?',
        whereArgs: ['pending_sync'],
        orderBy: 'created_at ASC',
      );

      if (pendingRows.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint('🔄 Synchronizing ${pendingRows.length} offline orders to Supabase...');

      for (final row in pendingRows) {
        final orderId = row['id'] as String;
        final customerId = row['customer_id'] as String;
        final stationId = row['station_id'] as String;
        final stationName = row['station_name'] as String?;
        final items = jsonDecode(row['items_json'] as String) as List<dynamic>;
        final totalAmount = (row['total_amount'] as num).toDouble();
        final subtotal = (row['subtotal'] as num).toDouble();
        final deliveryFee = (row['delivery_fee'] as num).toDouble();
        final platformFee = (row['platform_fee'] as num).toDouble();
        final deliveryAddress = row['delivery_address'] as String?;
        final paymentMethod = row['payment_method'] as String;
        final notes = row['notes'] as String?;

        try {
          // Attempt atomic RPC if available, otherwise direct insert
          try {
            await supabase.rpc(
              'create_order_atomic',
              params: {
                'p_id': orderId,
                'p_customer_id': customerId,
                'p_owner_id': stationId,
                'p_total_amount': totalAmount,
                'p_payment_method': paymentMethod,
                'p_delivery_address': deliveryAddress,
                'p_notes': notes,
                'p_items': items,
              },
            );
          } catch (_) {
            // Direct insertion fallback
            await supabase.from('orders').insert({
              'id': orderId,
              'customer_id': customerId,
              'station_id': stationId,
              'station_name': stationName,
              'items': items,
              'subtotal': subtotal,
              'delivery_fee': deliveryFee,
              'platform_fee': platformFee,
              'total_amount': totalAmount,
              'delivery_address': deliveryAddress,
              'payment_method': paymentMethod,
              'notes': notes,
              'status': 'pending',
              'created_at': row['created_at'],
            });
          }

          // Mark as successfully synchronized
          await localDatabase.update(
            tableOfflineOrders,
            {'status': 'synced', 'error_message': null},
            where: 'id = ?',
            whereArgs: [orderId],
          );
          debugPrint('✅ Offline order successfully synced to cloud: $orderId');
        } on PostgrestException catch (pe) {
          if (pe.code == '23505') {
            // Already created on cloud, mark synced
            await localDatabase.update(
              tableOfflineOrders,
              {'status': 'synced'},
              where: 'id = ?',
              whereArgs: [orderId],
            );
          } else {
            debugPrint('⚠️ Sync rejected for order $orderId: ${pe.message}');
            await localDatabase.update(
              tableOfflineOrders,
              {'status': 'failed', 'error_message': pe.message},
              where: 'id = ?',
              whereArgs: [orderId],
            );
          }
        } catch (e) {
          debugPrint('📡 Transient network failure during sync: $e');
          break; // Stop loop and await next connectivity event
        }
      }
    } catch (e) {
      debugPrint('Offline order sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Retrieves cached offline orders for display in customer history.
  Future<List<Map<String, dynamic>>> getOfflineOrders() async {
    final localDatabase = await db;
    return await localDatabase.query(
      tableOfflineOrders,
      orderBy: 'created_at DESC',
    );
  }

  /// Count of pending un-synchronized orders.
  Future<int> getPendingSyncCount() async {
    final localDatabase = await db;
    final res = await localDatabase.rawQuery(
      'SELECT COUNT(*) as count FROM $tableOfflineOrders WHERE status = ?',
      ['pending_sync'],
    );
    if (res.isNotEmpty) {
      return (res.first['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}

