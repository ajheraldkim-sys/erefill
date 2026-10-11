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
import 'models/cart_model.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure native Android edge-to-edge system navigation and transparent status bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.baseOverlayStyle(false));

  try {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: AppConstants.supabaseAnonKey,
    );

    // Initialize unified push & in-app notifications
    await NotificationService.instance.initialize();

    runApp(const ERefillApp());
  } catch (e, stackTrace) {
    debugPrint('Error initializing app: $e');
    debugPrint('Stack trace: $stackTrace');

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
                    'Error: $e',
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
        ChangeNotifierProvider(create: (_) => UserSettingsService()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        Provider<SyncService>.value(value: _syncSvc),
        ChangeNotifierProvider(create: (_) => DeliveryProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => RiderMgmtProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => CreditProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => InventoryProvider(_deliverySvc)),
        ChangeNotifierProvider(create: (_) => ReportProvider(_deliverySvc)),
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
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.themeMode,
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
                  themeMode: switch (themeProvider.themeMode) {
                    ThemeMode.dark => shadcn.ThemeMode.dark,
                    ThemeMode.system => shadcn.ThemeMode.system,
                    _ => shadcn.ThemeMode.light,
                  },
                  child: child,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Prevents elastic / stretching overscroll across all platforms and screens.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
