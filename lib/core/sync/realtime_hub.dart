import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Rows of one table, optionally narrowed to `column = value`.
///
/// Two watches with the same table, column and value share one Supabase
/// channel no matter how many screens listen to them.
@immutable
class TableWatch {
  const TableWatch(this.table, {this.column, this.value});

  final String table;
  final String? column;
  final Object? value;

  String get key => column == null ? table : '$table:$column=$value';

  @override
  bool operator ==(Object other) => other is TableWatch && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'TableWatch($key)';
}

/// A change delivered by [RealtimeHub].
///
/// [payload] is null for a resync signal: the channel was down for a while
/// (network loss, app in background, channel error) so changes may have been
/// missed and listeners should refetch rather than patch.
class RealtimeEvent {
  const RealtimeEvent(this.watch, this.payload);
  const RealtimeEvent.resync(this.watch) : payload = null;

  final TableWatch watch;
  final PostgresChangePayload? payload;

  bool get isResync => payload == null;
}

/// Shared Supabase Realtime subscriptions for the whole app.
///
/// Screens used to open their own channels and each re-implemented retry;
/// several opened two or three subscriptions on the same rows. The hub opens
/// one channel per [TableWatch], closes it when the last listener leaves,
/// retries with exponential backoff, and emits [RealtimeEvent.resync] after
/// any reconnect so listeners catch up on what they missed.
class RealtimeHub {
  RealtimeHub._();
  static final RealtimeHub instance = RealtimeHub._();

  final Map<String, _HubChannel> _channels = {};

  /// Subscribes to changes on [watch]. Cancel the returned subscription to
  /// stop listening; the channel closes once nobody listens.
  StreamSubscription<RealtimeEvent> listen(
    TableWatch watch,
    void Function(RealtimeEvent event) onEvent,
  ) {
    final channel = _channels.putIfAbsent(
      watch.key,
      () => _HubChannel(watch, onEmpty: () => _channels.remove(watch.key)),
    );
    return channel.events.listen(onEvent);
  }

  /// Re-opens channels that are down. Called when connectivity returns or
  /// the app comes back to the foreground, since sockets are often dropped
  /// silently while the device is offline or the app is suspended.
  ///
  /// Healthy channels are left alone: every re-open is a new subscription
  /// for Realtime to create in the database, and re-opening all of them on
  /// each resume exhausted Realtime's database pool (Oct 22 outage).
  void reconnectAll() {
    for (final channel in _channels.values.toList()) {
      channel.reconnect();
    }
  }

  /// Closes every channel, e.g. on sign-out.
  void closeAll() {
    for (final channel in _channels.values.toList()) {
      channel.close();
    }
    _channels.clear();
  }

  @visibleForTesting
  int get openChannelCount => _channels.length;
}

class _HubChannel {
  _HubChannel(this.watch, {required this.onEmpty}) {
    _controller = StreamController<RealtimeEvent>.broadcast(
      onListen: _open,
      onCancel: () {
        close();
        onEmpty();
      },
    );
  }

  final TableWatch watch;
  final VoidCallback onEmpty;
  late final StreamController<RealtimeEvent> _controller;
  RealtimeChannel? _channel;
  Timer? _retryTimer;
  Timer? _stableTimer;
  int _attempt = 0;
  bool _hasSubscribedOnce = false;
  bool _closed = false;

  /// True while the current channel's join is confirmed.
  bool _subscribed = false;

  /// The last drop was the database itself timing out, so the backoff
  /// should hold even when the app resumes or the network flaps.
  bool _backingOffFromDb = false;

  Stream<RealtimeEvent> get events => _controller.stream;

  SupabaseClient get _client => Supabase.instance.client;

  void _open() {
    if (_closed) return;
    _retryTimer?.cancel();
    _subscribed = false;
    final previous = _channel;
    _channel = null;
    if (previous != null) unawaited(_client.removeChannel(previous));

    final column = watch.column;
    final value = watch.value;
    // Topic is unique per open attempt so a lingering channel that is still
    // leaving cannot swallow the new join.
    final topic = 'hub:${watch.key}:${DateTime.now().microsecondsSinceEpoch}';
    final channel = _client.channel(topic).onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: watch.table,
      filter: column == null || value == null
          ? null
          : PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: column,
              value: value,
            ),
      callback: (payload) {
        if (kDebugMode) {
          debugPrint(
            '[RealtimeHub] Event on ${watch.key}: ${payload.eventType} '
            'table=${payload.table}',
          );
        }
        if (!_controller.isClosed) {
          _controller.add(RealtimeEvent(watch, payload));
        }
      },
    );
    _channel = channel;
    channel.subscribe((status, [error]) {
      if (kDebugMode) {
        debugPrint(
          '[RealtimeHub] Channel ${watch.key} status: $status'
          '${error != null ? " error=$error" : ""}',
        );
      }
      if (_closed || !identical(channel, _channel)) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          final isReconnect = _hasSubscribedOnce;
          _hasSubscribedOnce = true;
          _subscribed = true;
          _backingOffFromDb = false;
          // Realtime can accept a join and fail it moments later when the
          // database is overloaded; only a channel that stays up earns a
          // backoff reset, otherwise retries never slow down.
          _stableTimer?.cancel();
          _stableTimer = Timer(_stableAfter, () => _attempt = 0);
          if (isReconnect && !_controller.isClosed) {
            _controller.add(RealtimeEvent.resync(watch));
          }
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          _scheduleRetry(error);
      }
    });
  }

  static const _stableAfter = Duration(seconds: 30);

  void _scheduleRetry(Object? error) {
    _stableTimer?.cancel();
    _subscribed = false;
    if (_closed || (_retryTimer?.isActive ?? false)) return;
    _attempt++;
    final errorStr = error?.toString() ?? '';
    final isDbTimeout = errorStr.contains('Too many database timeouts') ||
        errorStr.contains('504') ||
        errorStr.contains('Gateway Timeout');
    _backingOffFromDb = isDbTimeout;
    final baseSeconds = isDbTimeout ? 6 : 2;
    final seconds = math.min(60, baseSeconds << math.min(_attempt, 4));
    if (kDebugMode) {
      debugPrint(
        'RealtimeHub ${watch.key} dropped (${error ?? 'no error'}); '
        'retrying in ${seconds}s',
      );
    }
    _retryTimer = Timer(Duration(seconds: seconds), _open);
  }

  void reconnect() {
    if (_closed || _subscribed) return;
    // A database-side failure is not fixed by the app resuming; keep the
    // scheduled backoff instead of piling on fresh subscription requests.
    if (_backingOffFromDb && (_retryTimer?.isActive ?? false)) return;
    _attempt = 0;
    _open();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    _stableTimer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_client.removeChannel(channel));
    unawaited(_controller.close());
  }
}
