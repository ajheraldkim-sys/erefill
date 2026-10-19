import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:erefill/features/settings/customer/user_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/notification_provider.dart';
import 'core/routing/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:erefill/core/models/cart_model.dart';
import 'core/services/observability_service.dart';
import 'package:erefill/features/delivery_mgmt/services/local_db_service.dart';
import 'package:erefill/features/delivery_mgmt/services/sync_service.dart';
import 'package:erefill/features/delivery_mgmt/services/delivery_service.dart';
import 'package:erefill/features/delivery_mgmt/providers/delivery_provider.dart';
import 'package:erefill/features/delivery_mgmt/providers/rider_mgmt_provider.dart';
import 'package:erefill/features/delivery_mgmt/providers/credit_provider.dart';
import 'package:erefill/features/delivery_mgmt/providers/inventory_provider.dart';
import 'package:erefill/features/delivery_mgmt/providers/report_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'core/services/offline_queue_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/offline_order_sync_service.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/widgets/offline_banner.dart';
import 'core/services/local_data_cache.dart';
import 'core/services/app_update_service.dart';
import 'core/localization/app_strings.dart';
import 'features/update/screens/mandatory_update_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupTimer = Stopwatch()..start();

  // Configure native Android edge-to-edge system navigation and transparent status bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.baseOverlayStyle(false));

  // Unlock high-refresh-rate display mode (120Hz/90Hz) on supported Android screens
  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      debugPrint('DisplayMode 120Hz initialization skipped: $e');
    }
  }

  try {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: AppConstants.supabaseAnonKey,
    );

    runApp(const ERefillApp());
    unawaited(LocalDataCache.instance.init());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NotificationService.instance.initialize());
      unawaited(AppUpdateService.instance.initialize());
    });
    if (kDebugMode) {
      debugPrint(
        'startup.supabase_ready_ms=${startupTimer.elapsedMilliseconds}',
      );
    }
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('Error initializing app: $e');
      debugPrint('Stack trace: $stackTrace');
    }

    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to initialize app',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: main, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ERefillApp extends StatefulWidget {
  const ERefillApp({super.key});

  @override
  State<ERefillApp> createState() => _ERefillAppState();
}

class _ERefillAppState extends State<ERefillApp> {
  late final LocalDbService _localDb;
  late final SyncService _syncSvc;
  late final DeliveryService _deliverySvc;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter.createRouter();
    _localDb = LocalDbService();
    final supabase = Supabase.instance.client;
    _syncSvc = SyncService(
      local: _localDb,
      supabase: supabase,
      failureReporter: (ownerId, error, stackTrace) =>
          ObservabilityService().logEvent(
            type: 'DELIVERY_SYNC_FAILED',
            level: LogLevel.error,
            payload: SyncService.syncFailurePayload(ownerId, error),
          ),
    );
    _deliverySvc = DeliveryService(local: _localDb, sync: _syncSvc);
    OfflineOrderSyncService().initializeConnectivityListener();
    OfflineQueueService.processQueue(supabase).catchError((e) {
      debugPrint('OfflineQueueService processQueue error: $e');
    });
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppLanguageProvider()),
        ChangeNotifierProvider(create: (_) => UserSettingsService()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        Provider<SyncService>.value(value: _syncSvc),
        ChangeNotifierProvider(create: (_) => DeliveryProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => RiderMgmtProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => CreditProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => InventoryProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => ReportProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider.value(value: AppUpdateService.instance),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final isDark = themeProvider.isDarkMode;
          final overlayStyle = AppTheme.baseOverlayStyle(isDark);

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: MaterialApp.router(
              title: 'eRefill',
              debugShowCheckedModeBanner: false,
              theme: themeProvider.isOutdoorMode
                  ? AppTheme.outdoorTheme
                  : AppTheme.lightTheme,
              darkTheme: themeProvider.isOutdoorMode
                  ? AppTheme.outdoorTheme
                  : AppTheme.darkTheme,
              themeMode: themeProvider.isOutdoorMode
                  ? ThemeMode.light
                  : themeProvider.themeMode,
              routerConfig: _router,
              scrollBehavior: const AppScrollBehavior(),
              localizationsDelegates: const [
                shadcn.ShadcnLocalizations.delegate,
              ],
              builder: (context, child) {
                return shadcn.ShadcnLayer(
                  theme: const shadcn.ThemeData(
                    colorScheme: shadcn.ColorSchemes.lightZinc,
                    radius: 0.5,
                  ),
                  darkTheme: const shadcn.ThemeData(
                    colorScheme: shadcn.ColorSchemes.darkZinc,
                    radius: 0.5,
                  ),
                  themeMode: themeProvider.isOutdoorMode
                      ? shadcn.ThemeMode.light
                      : switch (themeProvider.themeMode) {
                          ThemeMode.dark => shadcn.ThemeMode.dark,
                          ThemeMode.system => shadcn.ThemeMode.system,
                          _ => shadcn.ThemeMode.light,
                        },
                  child: Column(
                    children: [
                      const OfflineBanner(),
                      Expanded(
                        child: Consumer<AppUpdateService>(
                          builder: (context, updateSvc, _) {
                            if (updateSvc.isMandatoryUpdateRequired) {
                              return const MandatoryUpdateScreen();
                            }
                            return child ?? const SizedBox.shrink();
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Delivers smooth momentum scrolling with gentle rubber-band elasticity
/// and fluid stretching across Android and iOS platforms.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
