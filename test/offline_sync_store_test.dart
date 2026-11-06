import 'dart:async';

import 'package:erefill/core/services/local_data_cache.dart';
import 'package:erefill/core/sync/realtime_hub.dart';
import 'package:erefill/core/sync/sync_resources.dart';
import 'package:erefill/core/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Connectivity and realtime stand-ins driven by the test.
class _FakeEnv {
  bool online = true;
  final Map<String, void Function(RealtimeEvent)> listeners = {};

  SyncEnvironment get env => SyncEnvironment(
    isOnline: () => online,
    listen: (watch, onEvent) {
      listeners[watch.key] = onEvent;
      return const Stream<RealtimeEvent>.empty().listen(null);
    },
    cache: LocalDataCache.instance,
  );

  void emit(TableWatch watch) =>
      listeners[watch.key]!(RealtimeEvent.resync(watch));
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEnv fake;
  late SyncStore store;
  var keySeq = 0;
  late String key;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDataCache.instance.clear();
    fake = _FakeEnv();
    store = SyncStore.test(fake.env);
    key = 'test_${keySeq++}';
  });

  tearDown(() => store.dispose());

  SyncSpec<List<String>> spec(
    Future<List<String>> Function() fetch, {
    List<TableWatch> watches = const [],
    Set<String> tags = const {},
    String? overrideKey,
  }) => SyncSpec(
    key: overrideKey ?? key,
    fetch: fetch,
    decode: (json) => List<String>.from(json as List),
    watches: watches,
    tags: tags,
    debounce: const Duration(milliseconds: 5),
  );

  test('shows saved data on the first frame, before any fetch', () async {
    LocalDataCache.instance.setMemory('sync_v1:$key', {
      'data': ['saved'],
      'synced_at': '2026-10-01T08:00:00.000',
    });
    final fetch = Completer<List<String>>();

    final resource = store.acquire(spec(() => fetch.future));

    expect(resource.data, ['saved']);
    expect(resource.isLoading, isFalse);
    expect(resource.lastSyncedAt, DateTime(2026, 10, 1, 8));
    expect(resource.isRefreshing, isTrue);

    fetch.complete(['fresh']);
    await _settle();
    expect(resource.data, ['fresh']);
    expect(resource.isStale, isFalse);
  });

  test('saves fetched data so the next session starts from it', () async {
    final resource = store.acquire(spec(() async => ['a', 'b']));
    await _settle();
    store.release(resource);

    final saved = await LocalDataCache.instance.get<Map<String, dynamic>>(
      'sync_v1:$key',
    );
    expect(saved!['data'], ['a', 'b']);
    expect(DateTime.tryParse(saved['synced_at'] as String), isNotNull);

    final reopened = SyncStore.test(fake.env).acquire(
      spec(() => Completer<List<String>>().future),
    );
    expect(reopened.data, ['a', 'b']);
  });

  test('persist: false neither reads nor writes the local cache', () async {
    LocalDataCache.instance.setMemory('sync_v1:$key', {
      'data': ['saved'],
    });
    final resource = store.acquire(
      SyncSpec<List<String>>(
        key: key,
        fetch: () async => ['live'],
        decode: (json) => List<String>.from(json as List),
        persist: false,
      ),
    );
    expect(resource.data, isNull);

    await _settle();
    expect(resource.data, ['live']);
    final saved = await LocalDataCache.instance.get<Map<String, dynamic>>(
      'sync_v1:$key',
    );
    expect(saved!['data'], ['saved']);
  });

  test('offline: keeps saved data, skips the network, marks stale', () async {
    LocalDataCache.instance.setMemory('sync_v1:$key', {
      'data': ['saved'],
    });
    fake.online = false;
    var calls = 0;

    final resource = store.acquire(
      spec(() async {
        calls++;
        return ['never'];
      }),
    );
    await _settle();

    expect(calls, 0);
    expect(resource.data, ['saved']);
    expect(resource.isStale, isTrue);
    expect(resource.isLoading, isFalse);
  });

  test('a failed refresh keeps the last good data', () async {
    var fail = false;
    final resource = store.acquire(
      spec(() async {
        if (fail) throw Exception('timeout');
        return ['good'];
      }),
    );
    await _settle();

    fail = true;
    await resource.refresh();

    expect(resource.data, ['good']);
    expect(resource.error, isA<Exception>());
    expect(resource.isStale, isTrue);
  });

  test('refreshes during a fetch coalesce into one follow-up fetch', () async {
    var calls = 0;
    final gate = Completer<void>();
    final resource = store.acquire(
      spec(() async {
        calls++;
        if (calls == 1) await gate.future;
        return ['v$calls'];
      }),
    );

    unawaited(resource.refresh());
    unawaited(resource.refresh());
    unawaited(resource.refresh());
    gate.complete();
    await _settle();

    expect(calls, 2, reason: 'one initial fetch plus one coalesced rerun');
    expect(resource.data, ['v2']);
  });

  test('a realtime change refetches and notifies listeners', () async {
    const watch = TableWatch('orders', column: 'owner_id', value: 'o1');
    var version = 0;
    final resource = store.acquire(
      spec(() async => ['v${++version}'], watches: const [watch]),
    );
    await _settle();
    var notified = 0;
    resource.addListener(() => notified++);

    fake.emit(watch);
    await _settle();

    expect(resource.data, ['v2']);
    expect(notified, greaterThan(0));
  });

  test('screens share one resource per key until the last release', () async {
    var calls = 0;
    Future<List<String>> fetch() async {
      calls++;
      return ['x'];
    }

    final a = store.acquire(spec(fetch));
    final b = store.acquire(spec(fetch));
    await _settle();

    expect(identical(a, b), isTrue);
    expect(calls, 1);
    store.release(a);
    expect(store.liveResourceCount, 1);
    store.release(b);
    expect(store.liveResourceCount, 0);
  });

  test('reusing a key with another data type is rejected', () {
    store.acquire(spec(() async => ['x']));
    expect(
      () => store.acquire(
        SyncSpec<int>(key: key, fetch: () async => 1, decode: (j) => j as int),
      ),
      throwsStateError,
    );
  });

  test('refreshTagged only refetches resources with that tag', () async {
    var orders = 0;
    var other = 0;
    store.acquire(
      spec(() async => ['o${++orders}'], tags: const {'orders'}),
    );
    store.acquire(
      spec(() async => ['x${++other}'], overrideKey: '${key}_other'),
    );
    await _settle();

    await store.refreshTagged('orders');

    expect(orders, 2);
    expect(other, 1);
  });

  test('sign-out wipes data and ignores a fetch that was running', () async {
    final slow = Completer<List<String>>();
    var first = true;
    final resource = store.acquire(
      spec(() {
        if (first) {
          first = false;
          return Future.value(['mine']);
        }
        return slow.future;
      }),
    );
    await _settle();
    unawaited(resource.refresh());

    await store.debugClearForSignOut();
    slow.complete(['previous account']);
    await _settle();

    expect(resource.data, isNull);
    expect(
      await LocalDataCache.instance.get<Map<String, dynamic>>('sync_v1:$key'),
      isNull,
    );
  });

  test('a corrupt saved value is ignored, not thrown', () {
    LocalDataCache.instance.setMemory('sync_v1:$key', {'data': 42});
    final resource = store.acquire(
      spec(() => Completer<List<String>>().future),
    );
    expect(resource.data, isNull);
    expect(resource.isLoading, isTrue);
  });

  test('RealtimeEvent.resync carries no payload', () {
    const watch = TableWatch('orders');
    expect(const RealtimeEvent.resync(watch).isResync, isTrue);
    expect(watch.key, 'orders');
    expect(
      const TableWatch('orders', column: 'id', value: 7).key,
      'orders:id=7',
    );
    // PostgresChangeEvent is re-exported for screens that inspect payloads.
    expect(PostgresChangeEvent.values, isNotEmpty);
  });

  test('SyncResources.riderDashboard watches both assigned_rider_id and rider_id', () {
    final spec = SyncResources.riderDashboard('rider_xyz');
    final keys = spec.watches.map((w) => w.key).toSet();

    expect(keys, contains('orders:assigned_rider_id=rider_xyz'));
    expect(keys, contains('orders:rider_id=rider_xyz'));
    expect(keys, contains('profiles:id=rider_xyz'));
  });
}
