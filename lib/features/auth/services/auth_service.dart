import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  // --- GOOGLE SIGN IN ---
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            '998147956925-8o2qu65h0e2s7e12ksddc4a63a8p3rr8.apps.googleusercontent.com', // Web Client ID
        scopes: ['email', 'profile'],
      );

      // Always clear any cached Google session so the account chooser dialog is presented
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        throw 'Google sign-in was cancelled.';
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw 'No ID Token found from Google. Ensure the Web Client ID is properly configured.';
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } on AuthException catch (e) {
      debugPrint('[AuthService] Supabase Google Auth error: ${e.message} (code: ${e.statusCode})');
      throw 'Google authentication failed: ${e.message}';
    } catch (e) {
      final err = e.toString();
      debugPrint('[AuthService] Google Sign In error: $err');
      if (err.contains('ApiException: 10') || err.contains('10:')) {
        throw 'Google Sign-In configuration error (ApiException 10). Android SHA-1 fingerprint is not registered in Google Cloud Console for package com.erefill.app.';
      }
      if (err.contains('ApiException: 12500') || err.contains('12500:')) {
        throw 'Google Sign-In failed (ApiException 12500). Check Google Play Services or OAuth consent screen test user status.';
      }
      if (err.contains('ApiException: 7') || err.contains('network_error')) {
        throw 'Google Sign-In network error. Please check your internet connection.';
      }
      if (err.contains('cancelled') || err.contains('Google sign-in was cancelled')) {
        throw 'Google sign-in was cancelled.';
      }
      throw 'Google sign in failed: $e';
    }
  }

  // --- FACEBOOK SIGN IN ---
  Future<void> signInWithFacebook() async {
    try {
      // Use Supabase's native OAuth flow for Facebook
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: 'io.supabase.erefill://login-callback/',
      );
    } catch (e) {
      throw 'Facebook sign in failed: $e';
    }
  }

  // 1. STANDARD SIGN UP (Captures full details)
  Future<void> signUp({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
    String? mi,
    String? suffix,
    required String role, // 'owner' or 'customer' or 'rider'
    required String town,
    String? barangay,
    String? stationName,
    String? phone,
    String? address,
    String? landmark,
    double? latitude,
    double? longitude,
  }) async {
    final fullName = "$firstName ${mi ?? ''} $lastName ${suffix ?? ''}"
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'username': username.trim(),
        'full_name': fullName,
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'mi': mi?.trim(),
        'suffix': suffix?.trim(),
        'role': role,
        'town': town,
        'barangay': barangay,
        'station_name': stationName,
        'phone': phone?.trim(),
        'complete_address': address?.trim(),
        'landmark': landmark?.trim(),
        'latitude': latitude,
        'longitude': longitude,
      },
    );
  }

  // 2. LOGIN (Handles Email or Username)
  Future<void> login(String identifier, String password) async {
    final loginTimer = Stopwatch()..start();
    final cleanIdentifier = identifier.trim();

    if (cleanIdentifier.isEmpty || password.isEmpty) {
      throw 'Please enter both username/email and password.';
    }

    String email = cleanIdentifier;

    if (!cleanIdentifier.contains('@')) {
      final usernameLookupTimer = Stopwatch()..start();
      try {
        final res = await _supabase
            .from('profiles')
            .select('email')
            .ilike('username', cleanIdentifier)
            .maybeSingle();

        if (res != null) {
          final profileEmail = (res['email'] as String?)?.trim();
          if (profileEmail == null || profileEmail.isEmpty) {
            throw 'This username is not linked to an email yet. Please login using your email or contact support.';
          }
          email = profileEmail;
        } else if (cleanIdentifier.toLowerCase() == 'admin' ||
            cleanIdentifier.toLowerCase() == 'platform_admin') {
          email = 'admin@gmail.com';
        } else {
          throw 'Username not found.';
        }
      } finally {
        if (kDebugMode) {
          debugPrint(
            'auth.username_lookup_ms=${usernameLookupTimer.elapsedMilliseconds}',
          );
        }
      }
    }

    try {
      final signInTimer = Stopwatch()..start();
      await _supabase.auth.signInWithPassword(email: email, password: password);
      if (kDebugMode) {
        debugPrint(
          'auth.password_sign_in_ms=${signInTimer.elapsedMilliseconds}',
        );
      }
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      throw 'Unable to login right now: $e';
    } finally {
      if (kDebugMode) {
        debugPrint('auth.login_total_ms=${loginTimer.elapsedMilliseconds}');
      }
    }
  }

  // 3. LOGOUT
  Future<void> signOut() async {
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
    } catch (_) {}
    await _supabase.auth.signOut();
  }

  // 4. FORGOT PASSWORD
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'io.supabase.erefill://reset-password/',
      );
    } catch (e) {
      throw 'Failed to send reset email: $e';
    }
  }
}
