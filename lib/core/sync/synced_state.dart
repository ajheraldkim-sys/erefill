import 'dart:async';
import 'package:flutter/widgets.dart';
import 'realtime_hub.dart';
import 'sync_store.dart';

/// Connects a screen to the central sync layer.
///
/// * [useSynced] gives the screen a shared, cache-first [SyncedResource] and
///   rebuilds it whenever the data changes.
/// * [watchTable] listens to realtime changes through the shared
///   [RealtimeHub] for screens that react to individual events.
/// * [onResync] runs when the app returns to the foreground or connectivity
///   comes back, for screens that keep data outside a resource.
///
/// Everything is released automatically in [dispose].
mixin SyncedState<W extends StatefulWidget> on State<W> {
  final List<SyncedResource<dynamic>> _syncedResources = [];
  final List<StreamSubscription<RealtimeEvent>> _tableWatches = [];
  VoidCallback? _removeResyncListener;

  @override
  void initState() {
    super.initState();
    _removeResyncListener = SyncStore.instance.addResyncListener(() async {
      if (mounted) await onResync();
    });
  }

  /// Acquires the resource for [spec]; the screen rebuilds on every change
  /// unless [rebuild] is false (then add your own listener).
  SyncedResource<T> useSynced<T>(SyncSpec<T> spec, {bool rebuild = true}) {
    final resource = SyncStore.instance.acquire(spec);
    if (rebuild) resource.addListener(_onSyncedChanged);
    _syncedResources.add(resource);
    return resource;
  }

  /// Releases a resource early, e.g. when the screen switches to another
  /// record.
  void releaseSynced(SyncedResource<dynamic> resource) {
    if (!_syncedResources.remove(resource)) return;
    resource.removeListener(_onSyncedChanged);
    SyncStore.instance.release(resource);
  }

  /// Calls [onEvent] for each realtime change on [watch], including resync
  /// signals after a reconnect (see [RealtimeEvent.isResync]).
  StreamSubscription<RealtimeEvent> watchTable(
    TableWatch watch,
    void Function(RealtimeEvent event) onEvent,
  ) {
    final sub = RealtimeHub.instance.listen(watch, (event) {
      if (mounted) onEvent(event);
    });
    _tableWatches.add(sub);
    return sub;
  }

  /// Stops one [watchTable] subscription early.
  void unwatchTable(StreamSubscription<RealtimeEvent> sub) {
    if (_tableWatches.remove(sub)) unawaited(sub.cancel());
  }

  /// Override to refresh data held outside [useSynced] resources.
  Future<void> onResync() async {}

  void _onSyncedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _removeResyncListener?.call();
    for (final sub in _tableWatches) {
      unawaited(sub.cancel());
    }
    _tableWatches.clear();
    for (final resource in _syncedResources) {
      resource.removeListener(_onSyncedChanged);
      SyncStore.instance.release(resource);
    }
    _syncedResources.clear();
    super.dispose();
  }
}
