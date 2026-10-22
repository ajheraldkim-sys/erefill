import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/connectivity_provider.dart';
import '../services/local_data_cache.dart';
import 'realtime_hub.dart';

/// Describes one piece of server data the app keeps synchronized offline.
///
/// Specs live in `SyncResources` so every screen that needs, say, the owner's
/// orders shares one query, one cache entry and one realtime channel.
class SyncSpec<T> {
  const SyncSpec({
    required this.key,
    required this.fetch,
    required this.decode,
    this.encode,
    this.watches = const [],
    this.tags = const {},
    this.pollInterval,
    this.debounce = const Duration(milliseconds: 350),
    this.timeout = const Duration(seconds: 20),
  });

  /// Unique cache key. Include the user or record id.
  final String key;

  /// Loads the latest value from the server.
  final Future<T> Function() fetch;

  /// Rebuilds a value from its cached JSON form.
  final T Function(Object? json) decode;

  /// Converts a value to JSON for the cache. Defaults to the value itself,
  /// which suits the plain maps and lists Supabase returns.
  final Object? Function(T value)? encode;

  /// Realtime changes on these rows trigger a refetch.
  final List<TableWatch> watches;

  /// Groups resources for [SyncStore.refreshTagged], e.g. `orders`.
  final Set<String> tags;

  /// Safety-net refetch while the app is in the foreground and online, for
  /// changes realtime cannot see (joined tables, RLS-filtered events).
  final Duration? pollInterval;

  /// Bursts of realtime events within this window cause a single refetch.
  final Duration debounce;

  final Duration timeout;
}

/// Dependencies of the sync layer, swappable in tests.
class SyncEnvironment {
  const SyncEnvironment({
    required this.isOnline,
    required this.listen,
    required this.cache,
  });

  final bool Function() isOnline;
  final StreamSubscription<RealtimeEvent> Function(
    TableWatch watch,
    void Function(RealtimeEvent event) onEvent,
  )
  listen;
  final LocalDataCache cache;

  static SyncEnvironment live() => SyncEnvironment(
    isOnline: () => ConnectivityProvider().isOnline,
    listen: RealtimeHub.instance.listen,
    cache: LocalDataCache.instance,
  );
}

/// Server data with a persistent local copy: cache first, then network.
///
/// On creation it shows the last saved value immediately, then refreshes in
/// the background. It refreshes again whenever a watched table changes, the
/// app returns to the foreground, or connectivity comes back, and saves each
/// successful result. Listeners are notified on every change, so widgets
/// rebuild without any manual refresh.
class SyncedResource<T> extends ChangeNotifier {
  SyncedResource._(this.spec, this._env) {
    _hydrateSync();
  }

  final SyncSpec<T> spec;
  final SyncEnvironment _env;

  T? _data;
  DateTime? _lastSyncedAt;
  Object? _error;
  bool _isRefreshing = false;
  bool _settled = false;
  bool _lastAttemptFailed = false;
  bool _rerun = false;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _inFlight;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  final List<StreamSubscription<RealtimeEvent>> _watchSubs = [];
  final StreamController<RealtimeEvent> _changes =
      StreamController<RealtimeEvent>.broadcast();

  String get _cacheKey => 'sync_v1:${spec.key}';

  /// Latest known value: from the server if a refresh succeeded, otherwise
  /// from the local cache. Null only when nothing was ever loaded.
  T? get data => _data;

  /// When the value was last fetched from the server, possibly in an
  /// earlier session.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// The last refresh failure, cleared by the next success.
  Object? get error => _error;

  bool get isRefreshing => _isRefreshing;
  bool get hasData => _data != null;

  /// True until either cached or server data exists or a refresh finished.
  bool get isLoading => _data == null && !_settled;

  /// True when the shown value is saved data because the latest refresh was
  /// skipped (offline) or failed. Offline data is only as current as
  /// [lastSyncedAt].
  bool get isStale => _data != null && _lastAttemptFailed;

  /// Whether the latest refresh was skipped (offline) or failed, with or
  /// without saved data to fall back on.
  bool get lastRefreshFailed => _lastAttemptFailed;

  /// Raw realtime events for watched tables, for side effects such as new
  /// order alerts. [data] is refreshed separately.
  Stream<RealtimeEvent> get changes => _changes.stream;

  void _hydrateSync() {
    final cached = _env.cache.getMemory<Map<String, dynamic>>(_cacheKey);
    if (cached != null) _applyCached(cached);
  }

  Future<void> _hydrateAsync() async {
    if (_data != null) return;
    final generation = _generation;
    final cached = await _env.cache.get<Map<String, dynamic>>(_cacheKey);
    if (cached == null || _disposed || generation != _generation) return;
    // A network result may have landed while the disk read was pending.
    if (_data != null) return;
    if (_applyCached(cached)) _notify();
  }

  bool _applyCached(Map<String, dynamic> envelope) {
    try {
      _data = spec.decode(envelope['data']);
      _lastSyncedAt = DateTime.tryParse(
        envelope['synced_at']?.toString() ?? '',
      );
      return true;
    } catch (e) {
      debugPrint('SyncedResource ${spec.key}: discarding cached value: $e');
      return false;
    }
  }

  void _start({required bool foreground}) {
    unawaited(_hydrateAsync());
    for (final watch in spec.watches) {
      _watchSubs.add(_env.listen(watch, _onRealtime));
    }
    if (foreground) _resumePolling();
    unawaited(refresh());
  }

  void _onRealtime(RealtimeEvent event) {
    if (_disposed) return;
    if (!_changes.isClosed) _changes.add(event);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(spec.debounce, () => unawaited(refresh()));
  }

  void _resumePolling() {
    final interval = spec.pollInterval;
    if (interval == null || _disposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) {
      if (_env.isOnline()) unawaited(refresh());
    });
  }

  void _pausePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Fetches the latest value. Calls made while a fetch is running are
  /// coalesced into one follow-up fetch, so no change is missed and the
  /// server is never hit in parallel for the same data.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    final running = _inFlight;
    if (running != null) {
      _rerun = true;
      return running;
    }
    final future = _run().whenComplete(() {
      _inFlight = null;
      if (_rerun && !_disposed) {
        _rerun = false;
        unawaited(refresh());
      }
    });
    _inFlight = future;
    return future;
  }

  Future<void> _run() async {
    final generation = _generation;
    if (!_env.isOnline()) {
      _settled = true;
      _lastAttemptFailed = true;
      _notify();
      return;
    }
    _isRefreshing = true;
    _notify();
    try {
      final value = await spec.fetch().timeout(spec.timeout);
      if (_disposed || generation != _generation) return;
      _data = value;
      _lastSyncedAt = DateTime.now();
      _error = null;
      _lastAttemptFailed = false;
      unawaited(_persist(value));
    } catch (e) {
      if (_disposed || generation != _generation) return;
      debugPrint('SyncedResource ${spec.key}: refresh failed: $e');
      _error = e;
      _lastAttemptFailed = true;
    } finally {
      if (!_disposed && generation == _generation) {
        _isRefreshing = false;
        _settled = true;
        _notify();
      }
    }
  }

  Future<void> _persist(T value) {
    final encode = spec.encode;
    return _env.cache.set(_cacheKey, {
      'data': encode == null ? value : encode(value),
      'synced_at': _lastSyncedAt?.toIso8601String(),
    });
  }

  /// Applies an optimistic local change (e.g. right after the user acts) and
  /// saves it, without waiting for the server. The next refresh replaces it
  /// with the server's version.
  void mutateLocally(T Function(T? current) update) {
    if (_disposed) return;
    final value = update(_data);
    _data = value;
    unawaited(_persist(value));
    _notify();
  }

  /// Drops all state after sign-out so nothing from the previous account is
  /// shown or re-saved by a fetch that was already running.
  void _reset() {
    _generation++;
    _debounceTimer?.cancel();
    _pausePolling();
    for (final sub in _watchSubs) {
      unawaited(sub.cancel());
    }
    _watchSubs.clear();
    _data = null;
    _lastSyncedAt = null;
    _error = null;
    _isRefreshing = false;
    _settled = true;
    _lastAttemptFailed = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _pausePolling();
    for (final sub in _watchSubs) {
      unawaited(sub.cancel());
    }
    _watchSubs.clear();
    unawaited(_changes.close());
    super.dispose();
  }
}

class _Held {
  _Held(this.resource);
  final SyncedResource<dynamic> resource;
  int refs = 0;
}

/// Central coordinator for offline-first data.
///
/// Owns every live [SyncedResource] (shared by key and reference counted)
/// and drives synchronization for all of them from one place:
/// * app resumed → reconnect realtime, refresh everything on screen;
/// * connectivity restored → after the offline write queues flush, reconnect
///   realtime and refresh, so screens show server state that includes the
///   user's queued changes;
/// * signed out → drop all cached data so the next account starts clean.
///
/// Screens without a [SyncedResource] can still join in through
/// [addResyncListener].
class SyncStore with WidgetsBindingObserver {
  SyncStore._(this._env);

  /// Creates an isolated store for tests. Lifecycle hooks are not attached.
  @visibleForTesting
  factory SyncStore.test(SyncEnvironment env) => SyncStore._(env);

  static final SyncStore instance = SyncStore._(SyncEnvironment.live());

  final SyncEnvironment _env;
  final Map<String, _Held> _held = {};
  final Set<Future<void> Function()> _resyncListeners = {};
  StreamSubscription<void>? _reconnectSub;
  StreamSubscription<AuthState>? _authSub;
  bool _started = false;
  bool _foreground = true;

  /// Attaches lifecycle, connectivity and auth hooks. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _reconnectSub = ConnectivityProvider().onReconnected.listen(
      (_) => _resyncAll(reason: 'reconnected'),
    );
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        unawaited(_clearForSignOut());
      }
    }, onError: (Object e) => debugPrint('SyncStore auth listener: $e'));
  }

  /// Returns the shared resource for [spec.key], creating and starting it if
  /// nobody holds it yet. Pair every call with [release].
  ///
  /// The first acquirer's spec wins for a key, which is why specs should come
  /// from `SyncResources` rather than be built ad hoc.
  SyncedResource<T> acquire<T>(SyncSpec<T> spec) {
    final existing = _held[spec.key];
    if (existing != null) {
      final resource = existing.resource;
      if (resource is! SyncedResource<T>) {
        throw StateError(
          'Sync key "${spec.key}" is already used with a different type '
          '(${resource.runtimeType}).',
        );
      }
      existing.refs++;
      return resource;
    }
    final resource = SyncedResource<T>._(spec, _env);
    _held[spec.key] = _Held(resource)..refs = 1;
    resource._start(foreground: _foreground);
    return resource;
  }

  void release(SyncedResource<dynamic> resource) {
    final held = _held[resource.spec.key];
    if (held == null || !identical(held.resource, resource)) return;
    held.refs--;
    if (held.refs <= 0) {
      _held.remove(resource.spec.key);
      resource.dispose();
    }
  }

  /// Registers a callback run on resume and on reconnect, for screens that
  /// manage their own data. Returns a function that unregisters it.
  VoidCallback addResyncListener(Future<void> Function() onResync) {
    _resyncListeners.add(onResync);
    return () => _resyncListeners.remove(onResync);
  }

  /// Refreshes every live resource.
  Future<void> refreshAll() => Future.wait([
    for (final held in _held.values.toList()) held.resource.refresh(),
  ]);

  /// Refreshes live resources tagged [tag], e.g. right after the user changes
  /// an order so every screen showing orders updates without waiting for the
  /// realtime round trip.
  Future<void> refreshTagged(String tag) => Future.wait([
    for (final held in _held.values.toList())
      if (held.resource.spec.tags.contains(tag)) held.resource.refresh(),
  ]);

  @visibleForTesting
  int get liveResourceCount => _held.length;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    for (final held in _held.values) {
      if (foreground) {
        held.resource._resumePolling();
      } else {
        held.resource._pausePolling();
      }
    }
    if (foreground) unawaited(_resyncAll(reason: 'resumed'));
  }

  Future<void> _resyncAll({required String reason}) async {
    if (!_env.isOnline()) return;
    if (kDebugMode) debugPrint('SyncStore: resync ($reason)');
    RealtimeHub.instance.reconnectAll();
    await Future.wait([
      refreshAll(),
      for (final listener in _resyncListeners.toList())
        listener().catchError(
          (Object e) => debugPrint('SyncStore resync listener failed: $e'),
        ),
    ]);
  }

  Future<void> _clearForSignOut() async {
    for (final held in _held.values) {
      held.resource._reset();
    }
    RealtimeHub.instance.closeAll();
    await _env.cache.clear();
  }

  @visibleForTesting
  Future<void> debugClearForSignOut() => _clearForSignOut();

  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    unawaited(_reconnectSub?.cancel());
    unawaited(_authSub?.cancel());
    for (final held in _held.values) {
      held.resource.dispose();
    }
    _held.clear();
  }
}
