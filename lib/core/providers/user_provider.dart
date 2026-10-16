import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/models/user_model.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/utils/profile_query_helpers.dart';
import 'package:erefill/core/services/local_data_cache.dart';

class UserProvider extends ChangeNotifier {
  static const _profileColumns =
      'id,email,username,full_name,first_name,last_name,mi,suffix,phone,'
      'town,barangay,purok,zip_code,avatar_url,station_photo_url,station_name,'
      'vehicle_type,license_number,role,average_rating,landmark,complete_address,'
      'latitude,longitude,lat,lng,preferred_water_type,owner_id,is_suspended,'
      'suspended_reason,updated_at';

  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalDataCache _cache = LocalDataCache.instance;
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
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId != null) {
      _profileUserId = currentUserId;
      final mem = _cache.getMemory<Map<String, dynamic>>(
        'user_profile_$currentUserId',
      );
      if (mem != null) {
        _user = UserModel.fromJson(mem);
        _isLoading = false;
      }
      _cache.get<Map<String, dynamic>>('user_profile_$currentUserId').then((
        cached,
      ) {
        if (cached != null && _user == null && !_disposed) {
          _user = UserModel.fromJson(cached);
          _isLoading = false;
          notifyListeners();
        }
      });
    }
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
        } else if (_profileUserId != session.user.id || _user == null) {
          _fetchAndListenToProfile(session.user.id);
        } else if (data.event == AuthChangeEvent.userUpdated) {
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
      _profileSub?.cancel();
      _profileSub = null;

      // 1. Immediately check synchronous in-memory cache (0ms)
      final mem = _cache.getMemory<Map<String, dynamic>>(
        'user_profile_$userId',
      );
      if (mem != null && !_disposed && generation == _profileLoadGeneration) {
        _user = UserModel.fromJson(mem);
        _isLoading = false;
        notifyListeners();
      }

      // 2. Fallback to disk cache if memory didn't have it
      final cached = await _cache.get<Map<String, dynamic>>(
        'user_profile_$userId',
      );
      if (cached != null &&
          !_disposed &&
          generation == _profileLoadGeneration) {
        _user = UserModel.fromJson(cached);
        _isLoading = false;
        notifyListeners();
      } else if (_user == null) {
        _user = null;
        _isLoading = true;
        notifyListeners();
      }
    } else if (_user == null) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      Map<String, dynamic>? data;
      // Progressive retry loop up to 4 attempts to tolerate database trigger delay on signup
      final profileLoadTimer = Stopwatch()..start();
      for (int attempt = 1; attempt <= 4; attempt++) {
        try {
          data = await _supabase
              .from('profiles')
              .select(_profileColumns)
              .eq('id', userId)
              .maybeSingle();
          if (data != null) break;
        } catch (fetchErr) {
          debugPrint('Profile query attempt $attempt error: $fetchErr');
        }
        if (attempt < 4) {
          await Future.delayed(Duration(milliseconds: 250 * attempt));
          if (_disposed || generation != _profileLoadGeneration) return;
        }
      }

      if (_disposed ||
          generation != _profileLoadGeneration ||
          _profileUserId != userId) {
        return;
      }

      if (data != null) {
        _user = UserModel.fromJson(data);
        await _cache.set('user_profile_$userId', data);
      } else {
        // Fallback 1: Local cache
        final cached = await _cache.get<Map<String, dynamic>>(
          'user_profile_$userId',
        );
        if (cached != null) {
          _user = UserModel.fromJson(cached);
        } else {
          // Fallback 2: Synthesize from authenticated currentUser metadata for zero-lag signup
          final currentUser = _supabase.auth.currentUser;
          if (currentUser != null && currentUser.id == userId) {
            final meta = currentUser.userMetadata ?? {};
            final synthetic = <String, dynamic>{
              'id': userId,
              'email': currentUser.email ?? '',
              'role': meta['role'] ?? 'customer',
              'username':
                  meta['username'] ??
                  'user_${userId.length >= 8 ? userId.substring(0, 8) : userId}',
              'full_name': meta['full_name'] ?? meta['name'] ?? 'New User',
              'avatar_url': meta['avatar_url'] ?? meta['picture'],
              'first_name': meta['first_name'],
              'last_name': meta['last_name'],
              'mi': meta['mi'],
              'suffix': meta['suffix'],
              'phone': meta['phone'],
              'town': meta['town'],
              'barangay': meta['barangay'],
              'complete_address': meta['complete_address'],
              'landmark': meta['landmark'],
              'station_name': meta['station_name'],
              'latitude': meta['latitude'],
              'longitude': meta['longitude'],
              'preferred_water_type': meta['preferred_water_type'],
              'updated_at': DateTime.now().toIso8601String(),
            };
            _user = UserModel.fromJson(synthetic);
            await _cache.set('user_profile_$userId', synthetic);

            // Self-heal: Ensure row is asynchronously persisted to public.profiles
            unawaited(
              ProfileQueryHelpers.ensureProfileExists(
                _supabase,
                userId: userId,
              ).then((_) {}).catchError((e) {
                debugPrint('Self-healing profile upsert safeguard: $e');
              }),
            );
          }
        }
      }

      if (kDebugMode) {
        debugPrint(
          'auth.profile_load_ms=${profileLoadTimer.elapsedMilliseconds} result=${data == null ? 'fallback' : 'loaded'}',
        );
      }
      _attachProfileStream(userId);
    } catch (e) {
      if (_disposed || generation != _profileLoadGeneration) return;
      debugPrint("Error loading user profile: $e");

      // Network or offline failure: preserve or load cached profile
      if (_user == null) {
        final cached = await _cache.get<Map<String, dynamic>>(
          'user_profile_$userId',
        );
        if (cached != null) {
          _user = UserModel.fromJson(cached);
        }
      }

      // Handle explicit auth error / 401
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        _user = null;
        await _cache.set('user_profile_$userId', null);
      }
    } finally {
      if (!_disposed && generation == _profileLoadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _attachProfileStream(String userId) {
    _profileSub ??= SafeSupabase.listen(
      _supabase.from('profiles').stream(primaryKey: ['id']).eq('id', userId),
      (data) {
        if (data.isNotEmpty && _profileUserId == userId && !_disposed) {
          _user = UserModel.fromJson(data.first);
          _cache.set('user_profile_$userId', data.first);
          notifyListeners();
        }
      },
      onError: (error, stackTrace) {
        debugPrint('User profile stream error: $error');
        debugPrint('User profile stream stack: $stackTrace');
      },
    );
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
      await ProfileQueryHelpers.updateProfile(
        _supabase,
        updates,
        userId: userId,
      );

      // 2. Proactive Sync: Don't wait for stream, fetch now
      final data = await _supabase
          .from('profiles')
          .select(_profileColumns)
          .eq('id', userId)
          .single();
      if (_disposed || _supabase.auth.currentUser?.id != userId) return;
      final newUser = UserModel.fromJson(data);

      _user = newUser;
      await _cache.set('user_profile_$userId', data);
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
