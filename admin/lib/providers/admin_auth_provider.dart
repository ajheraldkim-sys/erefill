import 'dart:async';

import 'package:erefill/core/services/local_data_cache.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/features/auth/services/login_email_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_api_service.dart';

/// User-facing admin sign-in failure. [message] is safe to show as-is.
class AdminAuthException implements Exception {
  const AdminAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminAuthProvider extends ChangeNotifier {
  AdminAuthProvider(this._api);

  final AdminApiService _api;
  final SupabaseClient _client = Supabase.instance.client;

  // `initializing` gates the app on first launch only. `signingIn` is local to
  // the login form. Keeping them separate stops the root gate from swapping the
  // login form (or the whole AdminShell, on token refresh) for a spinner.
  bool _initializing = true;
  bool _signingIn = false;
  bool _isAdmin = false;
  Map<String, dynamic>? _profile;
  StreamSubscription<AuthState>? _authSub;
  Future<void>? _ongoingRefresh;
  String? _ongoingRefreshUserId;

  bool get initializing => _initializing;
  bool get signingIn => _signingIn;
  bool get isAuthenticated => _client.auth.currentSession != null;
  bool get isAdmin => _isAdmin;
  Map<String, dynamic>? get profile => _profile;
  String get displayName =>
      (_profile?['full_name']?.toString()) ??
      (_profile?['email']?.toString()) ??
      'Admin';

  /// Last verified admin, so a relaunch without network opens the console on
  /// saved data instead of the login screen. Cleared with the rest of the
  /// cache on sign-out.
  static const _verifiedKey = 'admin_auth_verified_v1';

  void init() {
    _restoreVerified();
    _authSub = _client.auth.onAuthStateChange.listen(
      (_) {
        _refresh();
      },
      onError: (error) {
        // Usually a token refresh that failed while offline; the session is
        // still there, so keep a verified admin on saved data.
        debugPrint('Admin auth state change error: $error');
        final userId = _client.auth.currentSession?.user.id;
        if (userId == null || !_hasVerified(userId)) {
          _profile = null;
          _isAdmin = false;
        }
        _initializing = false;
        notifyListeners();
      },
    );
    _refresh();
  }

  /// Re-reads the admin role for the *current* session. An in-flight refresh
  /// is only reused when it was started for the same user; otherwise a stale
  /// pre-sign-in refresh could report `isAdmin == false` for a real admin.
  Future<void> _refresh() async {
    final userId = _client.auth.currentSession?.user.id;
    final ongoing = _ongoingRefresh;
    if (ongoing != null && _ongoingRefreshUserId == userId) {
      await ongoing;
      return;
    }
    final future = _doRefresh(userId);
    _ongoingRefresh = future;
    _ongoingRefreshUserId = userId;
    try {
      await future;
    } finally {
      if (identical(_ongoingRefresh, future)) {
        _ongoingRefresh = null;
        _ongoingRefreshUserId = null;
      }
    }
  }

  void _restoreVerified() {
    final userId = _client.auth.currentSession?.user.id;
    if (userId == null) return;
    final saved = LocalDataCache.instance.getMemory<Map<String, dynamic>>(
      _verifiedKey,
    );
    if (saved == null || saved['user_id'] != userId) return;
    final profile = saved['profile'];
    _profile = profile is Map ? Map<String, dynamic>.from(profile) : null;
    _isAdmin = true;
    _initializing = false;
  }

  void _saveVerified(String userId) {
    unawaited(
      LocalDataCache.instance.set(_verifiedKey, {
        'user_id': userId,
        'profile': _profile,
      }),
    );
  }

  bool _hasVerified(String userId) =>
      LocalDataCache.instance.getMemory<Map<String, dynamic>>(
        _verifiedKey,
      )?['user_id'] ==
      userId;

  bool _isStale(String? userId) =>
      _client.auth.currentSession?.user.id != userId;

  Future<void> _doRefresh(String? userId) async {
    try {
      if (userId == null) {
        _profile = null;
        _isAdmin = false;
        return;
      }

      final profile = await _client
          .from('profiles')
          .select('id, email, full_name, role')
          .eq('id', userId)
          .maybeSingle();

      if (_isStale(userId)) return;
      final loadedProfile =
          profile == null ? null : Map<String, dynamic>.from(profile);
      final profileRole =
          loadedProfile?['role']?.toString().toLowerCase() ?? '';
      final hasAdminRole = profileRole == 'admin' ||
          profileRole == 'super_admin' ||
          profileRole == 'administrator';

      if (!hasAdminRole) {
        _profile = loadedProfile;
        _isAdmin = false;
        return;
      }

      // Verify RPC if available, but do not falsely lock out verified admins if RPC is not present
      final rpcCheck = await _api.isAdmin();
      if (_isStale(userId)) return;
      _profile = loadedProfile;
      _isAdmin = rpcCheck || hasAdminRole;
      if (_isAdmin) _saveVerified(userId);
    } catch (e) {
      if (_isStale(userId)) return;
      debugPrint('Admin auth refresh failed: $e');
      // A failed check (offline, timeout) is not a "no": keep a previously
      // verified admin signed in on saved data. Only a definite answer from
      // the server above revokes access.
      if (userId != null && _hasVerified(userId)) return;
      _profile = null;
      _isAdmin = false;
    } finally {
      // Always leave the first-launch state, even if the session changed
      // mid-refresh; otherwise the app can sit on the spinner forever.
      _initializing = false;
      notifyListeners();
    }
  }

  Future<String> _resolveEmail(String identifier) async {
    final input = identifier.trim();
    if (input.contains('@')) return input;

    final profileEmail = await resolveLoginEmail(_client, input);
    if (profileEmail != null) return profileEmail;
    throw const AdminAuthException(
      'No account matches that username. Try your email instead.',
    );
  }

  Future<void> signIn(String identifier, String password) async {
    if (_signingIn) return;
    _signingIn = true;
    notifyListeners();

    try {
      final email = await _resolveEmail(identifier);
      await _client.auth.signInWithPassword(email: email, password: password);
      await _refresh();
      if (!_isAdmin) {
        await _client.auth.signOut();
        throw const AdminAuthException(
          'This account is not authorized for admin access.',
        );
      }
    } on AdminAuthException {
      rethrow;
    } catch (e) {
      debugPrint('Admin sign-in failed: $e');
      throw AdminAuthException(
        FriendlyErrors.message(
          e,
          fallback: 'Sign-in failed. Please try again.',
        ),
      );
    } finally {
      _signingIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _profile = null;
    _isAdmin = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
