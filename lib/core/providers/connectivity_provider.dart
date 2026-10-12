import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_order_sync_service.dart';
import '../services/offline_queue_service.dart';
import '../../features/dashboard/rider/services/offline_delivery_queue_service.dart';

/// App-wide provider tracking internet connectivity and background synchronization queues.
class ConnectivityProvider extends ChangeNotifier {
  static final ConnectivityProvider _instance = ConnectivityProvider._internal();
  factory ConnectivityProvider() => _instance;
  ConnectivityProvider._internal() {
    _init();
  }

  bool _isOffline = false;
  bool _isSyncing = false;
  int _pendingSyncCount = 0;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<int>? _orderCountSub;

  bool get isOffline => _isOffline;
  bool get isOnline => !_isOffline;
  bool get isSyncing => _isSyncing;
  int get pendingSyncCount => _pendingSyncCount;

  void _init() {
    // Initial connectivity check
    Connectivity().checkConnectivity().then(_handleConnectivityChange).catchError((e) {
      debugPrint('Initial connectivity check error: $e');
    });

    _connSub = Connectivity().onConnectivityChanged.listen(_handleConnectivityChange);

    // Listen to changes in offline orders queue
    _orderCountSub = OfflineOrderSyncService().onPendingCountChanged.listen((_) {
      refreshPendingCount();
    });

    refreshPendingCount();
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    final transitionedToOnline = _isOffline && !offline;

    _isOffline = offline;
    notifyListeners();

    if (transitionedToOnline) {
      debugPrint('Connectivity restored! Triggering global offline queues synchronization...');
      syncAll();
    } else {
      refreshPendingCount();
    }
  }

  /// Calculates total pending sync items across customer orders, rider deliveries, and owner/system actions
  Future<int> refreshPendingCount() async {
    try {
      final orderCount = await OfflineOrderSyncService().getPendingSyncCount();
      final deliveryList = await OfflineDeliveryQueueService().getPendingDeliveries();
      final queueCount = await OfflineQueueService.getPendingCount();

      _pendingSyncCount = orderCount + deliveryList.length + queueCount;
      notifyListeners();
      return _pendingSyncCount;
    } catch (e) {
      debugPrint('Error refreshing pending sync count: $e');
      return _pendingSyncCount;
    }
  }

  /// Manually or automatically trigger background sync for all queues
  Future<void> syncAll() async {
    if (_isOffline || _isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final client = Supabase.instance.client;
      await Future.wait([
        OfflineOrderSyncService().syncPendingOrders(),
        OfflineQueueService.processQueue(client),
        OfflineDeliveryQueueService().syncPendingDeliveries(),
      ]);
    } catch (e) {
      debugPrint('Error in global syncAll: $e');
    } finally {
      _isSyncing = false;
      await refreshPendingCount();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _orderCountSub?.cancel();
    super.dispose();
  }
}

