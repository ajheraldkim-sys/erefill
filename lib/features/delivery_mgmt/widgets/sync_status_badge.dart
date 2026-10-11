import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import '../services/sync_service.dart';

class SyncStatusBadge extends StatelessWidget {
  final Stream<SyncStatus> statusStream;

  const SyncStatusBadge({super.key, required this.statusStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: statusStream,
      initialData: SyncStatus.idle,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;
        return _badge(status);
      },
    );
  }

  Widget _badge(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return const _StatusChip(
          key: ValueKey('syncing'),
          label: 'Syncing...',
          color: AppUi.bluePrimary,
          icon: Icons.sync_rounded,
        );
      case SyncStatus.synced:
        return const _StatusChip(
          key: ValueKey('synced'),
          label: 'Synced',
          color: Color(0xFF10B981),
          icon: Icons.cloud_done_rounded,
        );
      case SyncStatus.error:
        return const _StatusChip(
          key: ValueKey('error'),
          label: 'Needs Sync',
          color: Color(0xFFF59E0B),
          icon: Icons.cloud_off_rounded,
        );
      case SyncStatus.idle:
        return const SizedBox.shrink(key: ValueKey('idle'));
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppUi.radiusLg,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon == Icons.sync_rounded
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
