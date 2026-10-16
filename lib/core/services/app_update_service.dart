import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/models/app_version_models.dart';
import 'package:erefill/core/services/local_data_cache.dart';

class AppUpdateService extends ChangeNotifier with WidgetsBindingObserver {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  String _installedVersion = '1.0.0';
  int _installedBuild = 1;
  String _platform = 'android';
  String _channel = 'official_apk';

  AppUpdatePolicy? _currentPolicy;
  bool _isChecking = false;
  DateTime? _lastCheckedAt;
  RealtimeChannel? _realtimeChannel;
  bool _initialized = false;

  String get installedVersion => _installedVersion;
  int get installedBuild => _installedBuild;
  String get platform => _platform;
  String get channel => _channel;

  AppUpdatePolicy? get currentPolicy => _currentPolicy;
  AppUpdatePolicy? get policy => _currentPolicy;
  AppVersionStatus get status => _currentPolicy?.status ?? AppVersionStatus.supported;
  bool get isChecking => _isChecking;

  bool get isMandatoryUpdateRequired {
    if (_currentPolicy == null) return false;
    return _currentPolicy!.status == AppVersionStatus.updateRequired ||
        (_currentPolicy!.status == AppVersionStatus.updateAvailable &&
            _currentPolicy!.isMandatory);
  }

  bool get isOptionalUpdateAvailable {
    if (_currentPolicy == null) return false;
    return _currentPolicy!.status == AppVersionStatus.updateAvailable &&
        !_currentPolicy!.isMandatory;
  }

  /// Initialize version metadata, disk cache, lifecycle observers, and realtime invalidation
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    // 1. Resolve runtime platform & channel
    if (kIsWeb) {
      _platform = 'web';
      _channel = 'web_deployment';
    } else if (Platform.isAndroid) {
      _platform = 'android';
      _channel = 'official_apk';
    } else if (Platform.isIOS) {
      _platform = 'ios';
      _channel = 'app_store';
    }

    // 2. Read installed package version & build number
    try {
      final info = await PackageInfo.fromPlatform();
      _installedVersion = info.version.isNotEmpty ? info.version : '1.0.0';
      _installedBuild = int.tryParse(info.buildNumber) ?? 1;
    } catch (e) {
      debugPrint('Could not read package metadata: $e (using fallback)');
    }

    // 3. Instant load from local cache
    try {
      final cachedJson =
          await LocalDataCache.instance.get<Map<String, dynamic>>('app_version_policy');
      if (cachedJson != null) {
        _currentPolicy = AppUpdatePolicy.fromJson(
          cachedJson,
          fallbackInstalledVersion: _installedVersion,
          fallbackInstalledBuild: _installedBuild,
        );
        notifyListeners();
      }
    } catch (_) {}

    // 4. Setup realtime listener for instant administrator updates
    _setupRealtimeSubscription();

    // 5. Initial startup version check
    unawaited(checkForUpdates());
  }

  void _setupRealtimeSubscription() {
    try {
      _realtimeChannel = _supabase
          .channel('app_release_updates')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'app_releases',
            callback: (payload) {
              debugPrint('Received app_releases realtime update, checking policy...');
              checkForUpdates(force: true);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Error subscribing to app_releases realtime: $e');
    }
  }

  /// Query the backend for the authoritative version policy.
  Future<AppUpdatePolicy> checkForUpdates({bool force = false}) async {
    if (_isChecking) {
      return _currentPolicy ??
          AppUpdatePolicy.initial(
            currentVersion: _installedVersion,
            currentBuild: _installedBuild,
          );
    }

    // Rate-limiting: Skip if checked within last 5 minutes unless forced
    final now = DateTime.now();
    if (!force &&
        _lastCheckedAt != null &&
        now.difference(_lastCheckedAt!).inMinutes < 5 &&
        _currentPolicy != null) {
      return _currentPolicy!;
    }

    _isChecking = true;
    notifyListeners();

    try {
      final dynamic response = await _supabase.rpc(
        'check_app_version_compatibility',
        params: {
          'p_client_version': _installedVersion,
          'p_client_build': _installedBuild,
          'p_platform': _platform,
          'p_channel': _channel,
        },
      ).timeout(const Duration(seconds: 12));

      _lastCheckedAt = DateTime.now();

      if (response is Map) {
        final policy = AppUpdatePolicy.fromJson(
          Map<String, dynamic>.from(response),
          fallbackInstalledVersion: _installedVersion,
          fallbackInstalledBuild: _installedBuild,
        );

        _currentPolicy = policy;
        unawaited(
          LocalDataCache.instance.set('app_version_policy', policy.toJson()),
        );
        notifyListeners();
        return policy;
      }
    } catch (e) {
      debugPrint('App update check error: $e');
    } finally {
      _isChecking = false;
      notifyListeners();
    }

    return _currentPolicy ??
        AppUpdatePolicy.initial(
          currentVersion: _installedVersion,
          currentBuild: _installedBuild,
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-verify update policy when app is brought to foreground
      final now = DateTime.now();
      if (_lastCheckedAt == null ||
          now.difference(_lastCheckedAt!).inMinutes >= 10) {
        checkForUpdates();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_realtimeChannel != null) {
      _supabase.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }
}
