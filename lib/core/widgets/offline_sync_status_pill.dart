import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';
import '../constants.dart';
import '../services/offline_queue_service.dart';
import '../../features/dashboard/rider/services/offline_delivery_queue_service.dart';

/// Floating indicator displaying realtime sync status and pending offline operations.
class OfflineSyncStatusPill extends StatefulWidget {
  final VoidCallback? onSyncTap;
  final bool showAlways;

  const OfflineSyncStatusPill({
    super.key,
    this.onSyncTap,
    this.showAlways = false,
  });

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
      final riderCount = await OfflineDeliveryQueueService.instance.getPendingCount();
      final generalCount = await OfflineQueueService.getPendingCount();
      if (mounted) {
        setState(() => _pendingCount = riderCount + generalCount);
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
      try {
        await OfflineQueueService.processQueue(Supabase.instance.client);
      } catch (err) {
        debugPrint('General offline queue process error: $err');
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
    if (!widget.showAlways && _isOnline && _pendingCount == 0 && !_isSyncing) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // WCAG AA compliant palette:
    // Green (All synced): 0xFF065F46 text on 0xFFECFDF5 bg (> 7:1)
    // Amber (Offline or waiting): 0xFF92400E text on 0xFFFEF3C7 bg (> 8:1)
    final isSynced = _isOnline && _pendingCount == 0 && !_isSyncing;

    final bgColor = isSynced
        ? (isDark ? const Color(0xFF064E3B) : AppUi.successBg)
        : (isDark ? const Color(0xFF451A03) : AppUi.warningBg);

    final borderColor = isSynced
        ? AppColors.uiSuccess.withValues(alpha: 0.6)
        : AppColors.uiWarning.withValues(alpha: 0.6);

    final fgColor = isSynced
        ? (isDark ? AppUi.successBorder : AppUi.successFg)
        : (isDark ? AppUi.warningBorder : AppUi.warningFg);

    final iconColor = isSynced ? AppColors.uiSuccess : AppColors.uiWarning;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
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
              isSynced
                  ? Icons.check_circle_rounded
                  : (!_isOnline ? Icons.cloud_off_rounded : Icons.cloud_upload_outlined),
              size: 16,
              color: iconColor,
            ),
          const SizedBox(width: 8),
          Text(
            isSynced
                ? 'All synced'
                : (!_isOnline
                    ? (_pendingCount > 0
                        ? 'Offline • $_pendingCount queued'
                        : 'Offline Mode')
                    : (_isSyncing
                        ? 'Syncing with cloud...'
                        : '$_pendingCount waiting to sync')),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fgColor,
            ),
          ),
          if (_pendingCount > 0 && !_isSyncing && _isOnline) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _triggerSync,
              child: Container(
                constraints: const BoxConstraints(minHeight: AppUi.kMinTouchTarget),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary,
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
                child: const Text(
                  'Sync Now',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

