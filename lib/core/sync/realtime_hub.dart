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

  /// Re-opens every channel. Called when connectivity returns or the app
  /// comes back to the foreground, since sockets are often dropped silently
  /// while the device is offline or the app is suspended.
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
  int _attempt = 0;
  bool _hasSubscribedOnce = false;
  bool _closed = false;

  Stream<RealtimeEvent> get events => _controller.stream;

  SupabaseClient get _client => Supabase.instance.client;

  void _open() {
    if (_closed) return;
    _retryTimer?.cancel();
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
        if (!_controller.isClosed) {
          _controller.add(RealtimeEvent(watch, payload));
        }
      },
    );
    _channel = channel;
    channel.subscribe((status, [error]) {
      if (_closed || !identical(channel, _channel)) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          final isReconnect = _hasSubscribedOnce;
          _hasSubscribedOnce = true;
          _attempt = 0;
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

  void _scheduleRetry(Object? error) {
    if (_closed || (_retryTimer?.isActive ?? false)) return;
    _attempt++;
    final seconds = math.min(30, 2 << math.min(_attempt, 4));
    if (kDebugMode) {
      debugPrint(
        'RealtimeHub ${watch.key} dropped (${error ?? 'no error'}); '
        'retrying in ${seconds}s',
      );
    }
    _retryTimer = Timer(Duration(seconds: seconds), _open);
  }

  void reconnect() {
    if (_closed) return;
    _attempt = 0;
    _open();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_client.removeChannel(channel));
    unawaited(_controller.close());
  }
}
