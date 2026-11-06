import 'package:erefill/core/constants.dart';
import 'package:erefill/core/providers/connectivity_provider.dart';
import 'package:erefill/core/sync/sync_store.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/admin_ui.dart';

/// The resource behind a screen whose query changes (filters, search, paging).
///
/// Rebind it with `query.resource = rebindSynced(query.resource, spec)`.
/// [data] keeps returning the previous result until the new query's first
/// result arrives, so changing a filter never blanks the screen (which used to
/// unmount the search field and drop its focus mid-typing).
class AdminLiveQuery<T> {
  SyncedResource<T>? resource;
  T? _last;

  T? get data {
    final current = resource?.data;
    if (current != null) _last = current;
    return current ?? _last;
  }

  /// True while showing the previous query's result for a new query.
  bool get isSwitching => resource?.data == null && _last != null;

  /// Spinner or error to show while nothing at all is available yet.
  Widget? get placeholder {
    final r = resource;
    if (r == null) return const AdminLoadingState();
    if (data != null) return null;
    return adminSyncPlaceholder([r]);
  }
}

/// What to show instead of a screen while its first data is not available:
/// a spinner while loading, otherwise an error with Retry. Returns null once
/// any data (saved or fresh) exists, so cached screens render immediately.
Widget? adminSyncPlaceholder(Iterable<SyncedResource<dynamic>> resources) {
  for (final r in resources) {
    if (r.hasData) continue;
    if (r.isLoading || r.isRefreshing) return const AdminLoadingState();
    final error = r.error;
    return AdminErrorState(
      message: error == null
          ? 'You are offline and this page has not been saved yet. '
                'It will load when you reconnect.'
          : FriendlyErrors.message(error),
      onRetry: () async {
        await ConnectivityProvider().probe();
        await r.refresh();
      },
    );
  }
  return null;
}

/// Puts a slim notice above [child] when any of [resources] is showing saved
/// data because the latest refresh was skipped (offline) or failed.
class AdminSyncedFrame extends StatelessWidget {
  const AdminSyncedFrame({
    super.key,
    required this.resources,
    required this.child,
  });

  final List<SyncedResource<dynamic>> resources;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final stale = resources.where((r) => r.isStale).toList();
    if (stale.isEmpty) return child;

    DateTime? oldest;
    for (final r in stale) {
      final at = r.lastSyncedAt;
      if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
    }
    final offline = ConnectivityProvider().isOffline;
    final retrying = stale.any((r) => r.isRefreshing);

    return Column(
      children: [
        _StaleNotice(
          offline: offline,
          syncedAt: oldest,
          retrying: retrying,
          onRetry: () async {
            await ConnectivityProvider().probe();
            for (final r in stale) {
              r.refresh();
            }
          },
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({
    required this.offline,
    required this.syncedAt,
    required this.retrying,
    required this.onRetry,
  });

  final bool offline;
  final DateTime? syncedAt;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final dark = AppUi.isDark(context);
    final fg = dark ? AppUi.warningFgDark : AppUi.warningFg;
    final when = syncedAt == null ? null : _formatSyncedAt(syncedAt!);
    final message = [
      offline ? 'You are offline.' : 'Could not refresh.',
      when == null ? 'Showing saved data.' : 'Showing data from $when.',
    ].join(' ');

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: dark ? fg.withValues(alpha: 0.10) : AppUi.warningBg,
          borderRadius: BorderRadius.circular(AppUi.radiusControl),
          border: Border.all(color: fg.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(
              offline ? LucideIcons.wifiOff : LucideIcons.cloudAlert,
              size: 16,
              color: fg,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!offline)
              TextButton(
                onPressed: retrying ? null : onRetry,
                style: TextButton.styleFrom(foregroundColor: fg),
                child: Text(retrying ? 'Retrying…' : 'Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatSyncedAt(DateTime at) {
  final now = DateTime.now();
  final local = at.toLocal();
  final sameDay =
      local.year == now.year && local.month == now.month && local.day == now.day;
  return sameDay
      ? DateFormat('h:mm a').format(local)
      : DateFormat('MMM d, h:mm a').format(local);
}

/// Top-bar connection status: live while online, a warning while offline.
class AdminSyncStatusPill extends StatelessWidget {
  const AdminSyncStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final connectivity = ConnectivityProvider();
    return ListenableBuilder(
      listenable: connectivity,
      builder: (context, _) {
        final offline = connectivity.isOffline;
        final dark = AppUi.isDark(context);
        final color = offline
            ? (dark ? AppUi.warningFgDark : AppUi.warningFg)
            : AppUi.accentGreen;
        return Tooltip(
          message: offline
              ? 'Offline. Click to retry connection.'
              : 'Connected. Screens update automatically.',
          child: InkWell(
            onTap: () async {
              await connectivity.probe();
              await SyncStore.instance.refreshAll();
            },
            borderRadius: BorderRadius.circular(AppUi.radiusSheet),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (offline)
                    Icon(LucideIcons.wifiOff, size: 12, color: color)
                  else
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    offline ? 'Offline' : 'Live',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
