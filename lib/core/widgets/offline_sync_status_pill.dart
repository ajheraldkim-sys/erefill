import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';
import '../../features/dashboard/rider/services/offline_delivery_queue_service.dart';

/// Floating indicator displaying realtime sync status and pending offline operations.
class OfflineSyncStatusPill extends StatefulWidget {
  final VoidCallback? onSyncTap;

  const OfflineSyncStatusPill({super.key, this.onSyncTap});

  @override
  State<OfflineSyncStatusPill> createState() => _OfflineSyncStatusPillState();
}

class _OfflineSyncStatusPillState extends State<OfflineSyncStatusPill> {
  bool _isOnline = true;
  int _pendingCount = 0;
  bool _isSyncing = false;
  StreamSubscription? _connectivitySub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isNowOnline = !results.contains(ConnectivityResult.none);
      if (mounted) {
        setState(() => _isOnline = isNowOnline);
        if (isNowOnline && _pendingCount > 0) {
          _triggerSync();
        }
      }
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _checkPendingQueue());
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() => _isOnline = !results.contains(ConnectivityResult.none));
      _checkPendingQueue();
    }
  }

  Future<void> _checkPendingQueue() async {
    try {
      final count = await OfflineDeliveryQueueService.instance.getPendingCount();
      if (mounted) {
        setState(() => _pendingCount = count);
      }
    } catch (_) {}
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    AppHaptics.medium();

    try {
      final syncer = OfflineDeliveryQueueService.instance.onSyncTriggered;
      if (syncer != null) {
        await syncer();
      }
      widget.onSyncTap?.call();
      await _checkPendingQueue();
      AppHaptics.success();
    } catch (_) {
      AppHaptics.error();
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show pill if user is offline OR has pending operations queued
    if (_isOnline && _pendingCount == 0 && !_isSyncing) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: !_isOnline
            ? (isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB))
            : (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: !_isOnline
              ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
              : const Color(0xFF10B981).withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isSyncing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandPrimary,
              ),
            )
          else
            Icon(
              !_isOnline ? Icons.cloud_off_rounded : Icons.cloud_sync_rounded,
              size: 16,
              color: !_isOnline ? const Color(0xFFD97706) : const Color(0xFF059669),
            ),
          const SizedBox(width: 8),
          Text(
            !_isOnline
                ? (_pendingCount > 0
                    ? 'Offline Mode • $_pendingCount items queued'
                    : 'Offline Mode')
                : (_isSyncing
                    ? 'Syncing with cloud...'
                    : 'Online • Sync completed'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: !_isOnline
                  ? (isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E))
                  : (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46)),
            ),
          ),
          if (_pendingCount > 0 && !_isSyncing && _isOnline) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _triggerSync,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Sync Now',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

