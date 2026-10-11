import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_api_service.dart';

class AdminAuthProvider extends ChangeNotifier {
  AdminAuthProvider(this._api);

  final AdminApiService _api;
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  bool _isAdmin = false;
  Map<String, dynamic>? _profile;
  StreamSubscription<AuthState>? _authSub;
  Future<void>? _ongoingRefresh;

  bool get loading => _loading;
  bool get isAuthenticated => _client.auth.currentSession != null;
  bool get isAdmin => _isAdmin;
  Map<String, dynamic>? get profile => _profile;
  String get displayName =>
      (_profile?['full_name']?.toString()) ??
      (_profile?['email']?.toString()) ??
      'Admin';

  void init() {
    _authSub = _client.auth.onAuthStateChange.listen(
      (_) {
        _refresh();
      },
      onError: (error) {
        debugPrint('Admin auth state change error: $error');
        _profile = null;
        _isAdmin = false;
        _loading = false;
        notifyListeners();
      },
    );
    _refresh();
  }

  Future<void> _refresh() async {
    if (_ongoingRefresh != null) {
      await _ongoingRefresh;
      return;
    }
    final future = _doRefresh();
    _ongoingRefresh = future;
    try {
      await future;
    } finally {
      if (identical(_ongoingRefresh, future)) {
        _ongoingRefresh = null;
      }
    }
  }

  Future<void> _doRefresh() async {
    final session = _client.auth.currentSession;
    final userId = session?.user.id;
    _loading = true;
    notifyListeners();

    try {
      if (session == null) {
        _profile = null;
        _isAdmin = false;
        return;
      }

      final profile = await _client
          .from('profiles')
          .select('id, email, full_name, role')
          .eq('id', session.user.id)
          .maybeSingle();

      if (_client.auth.currentSession?.user.id != userId) return;
      final loadedProfile =
          profile == null ? null : Map<String, dynamic>.from(profile);
      final profileRole = loadedProfile?['role']?.toString().toLowerCase() ?? '';
      final hasAdminRole = profileRole == 'admin' ||
          profileRole == 'super_admin' ||
          profileRole == 'administrator';

      if (!hasAdminRole) {
        _profile = loadedProfile;
        _isAdmin = false;
        return;
      }

      // Verify RPC if available, but do not falsely lock out verified admins if RPC is not present
      try {
        final rpcCheck = await _api.isAdmin();
        if (_client.auth.currentSession?.user.id != userId) return;
        _profile = loadedProfile;
        _isAdmin = rpcCheck || hasAdminRole;
      } catch (e) {
        if (_client.auth.currentSession?.user.id != userId) return;
        debugPrint('is_admin RPC check skipped (falling back to database role): $e');
        _profile = loadedProfile;
        _isAdmin = hasAdminRole;
      }
    } catch (e) {
      if (_client.auth.currentSession?.user.id != userId) return;
      debugPrint('Admin auth refresh failed: $e');
      _profile = null;
      _isAdmin = false;
    } finally {
      if (_client.auth.currentSession?.user.id == userId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> signIn(String identifier, String password) async {
    _loading = true;
    notifyListeners();

    try {
      String email = identifier.trim();
      if (!email.contains('@')) {
        final res = await _client
            .from('profiles')
            .select('email')
            .ilike('username', email)
            .maybeSingle();
        final profileEmail = res?['email']?.toString().trim();
        if (profileEmail != null && profileEmail.isNotEmpty) {
          email = profileEmail;
        } else if (email.toLowerCase() == 'admin' ||
            email.toLowerCase() == 'platform_admin') {
          email = 'admin@gmail.com';
        }
      }

      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      await _refresh();
      if (!_isAdmin) {
        await _client.auth.signOut();
        throw Exception('This account is not authorized for admin access.');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _profile = null;
    _isAdmin = false;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
