import 'dart:async';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/services/local_data_cache.dart';
import 'package:erefill/core/sync/sync_store.dart';
import 'package:erefill/core/water_types.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'providers/admin_auth_provider.dart';
import 'services/admin_api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Load the offline cache before the first frame so the console shows saved
  // data immediately, even offline. Bounded so a slow disk never blocks
  // startup; resources fall back to an async cache read.
  await LocalDataCache.instance.init().timeout(
    const Duration(milliseconds: 800),
    onTimeout: () => debugPrint('startup.cache_init_timed_out'),
  );

  final api = AdminApiService(Supabase.instance.client);
  unawaited(WaterTypes.load());
  final auth = AdminAuthProvider(api)..init();

  runApp(
    MultiProvider(
      providers: [
        Provider<AdminApiService>.value(value: api),
        ChangeNotifierProvider<AdminAuthProvider>.value(value: auth),
      ],
      child: const AdminApp(),
    ),
  );
  SyncStore.instance.start();
}
