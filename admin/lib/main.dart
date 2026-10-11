import 'package:erefill/core/constants.dart';
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

  final api = AdminApiService(Supabase.instance.client);
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
}
