import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/models/user_model.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/utils/profile_query_helpers.dart';

class UserProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  UserModel? _user;
  bool _isLoading = true;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSub;
  String? _profileUserId;
  int _profileLoadGeneration = 0;
  bool _disposed = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _supabase.auth.currentSession != null;

  UserProvider() {
    _init();
  }

  void _init() {
    _authSub = _supabase.auth.onAuthStateChange.listen(
      (data) {
        final session = data.session;
        if (session == null) {
          _profileLoadGeneration++;
          _profileUserId = null;
          _user = null;
          _isLoading = false;
          _profileSub?.cancel();
          _profileSub = null;
          notifyListeners();
        } else if (_profileUserId != session.user.id) {
          _fetchAndListenToProfile(session.user.id);
        }
      },
      onError: (error) {
        debugPrint('Auth state change error: $error');
        _profileLoadGeneration++;
        _profileUserId = null;
        _user = null;
        _isLoading = false;
        _profileSub?.cancel();
        _profileSub = null;
        notifyListeners();
      },
    );
  }

  Future<void> _fetchAndListenToProfile(String userId) async {
    final isNewUser = _profileUserId != userId;
    final generation = ++_profileLoadGeneration;
    if (isNewUser) {
      _profileUserId = userId;
      _user = null;
      _isLoading = true;
      _profileSub?.cancel();
      _profileSub = null;
      notifyListeners();
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      if (_disposed ||
          generation != _profileLoadGeneration ||
          _profileUserId != userId) {
        return;
      }
      _user = UserModel.fromJson(data);

      _profileSub ??= SafeSupabase.listen(
        _supabase
            .from('profiles')
            .stream(primaryKey: ['id'])
            .eq('id', userId),
        (data) {
            if (data.isNotEmpty && _profileUserId == userId && !_disposed) {
              _user = UserModel.fromJson(data.first);
              notifyListeners();
            }
          },
          onError: (error, stackTrace) {
            debugPrint('User profile stream error: $error');
            debugPrint('User profile stream stack: $stackTrace');
          },
        );
    } catch (e) {
      if (_disposed || generation != _profileLoadGeneration) return;
      debugPrint("Error loading user profile: $e");
      // Handle explicit auth error / 401
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        _user = null;
      }
    } finally {
      if (!_disposed && generation == _profileLoadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _fetchAndListenToProfile(userId);
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception("User not authenticated");
    try {
      // 1. Update backend safely
      await ProfileQueryHelpers.updateProfile(_supabase, updates, userId: userId);

      // 2. Proactive Sync: Don't wait for stream, fetch now
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      if (_disposed || _supabase.auth.currentUser?.id != userId) return;
      final newUser = UserModel.fromJson(data);

      _user = newUser;
      notifyListeners();
    } catch (e) {
      debugPrint("Error updating profile in provider: $e");
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
