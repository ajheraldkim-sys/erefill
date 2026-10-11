import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  // --- GOOGLE SIGN IN ---
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            '998147956925-t1iuu6ncqirbg342u9ob7n6bi0bdi518.apps.googleusercontent.com', // Your NEW Web Client ID
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        throw 'Google sign in cancelled';
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw 'No ID Token found from Google';
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
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
    final cleanIdentifier = identifier.trim();
    final cleanPassword = password.trim();

    if (cleanIdentifier.isEmpty || cleanPassword.isEmpty) {
      throw 'Please enter both username/email and password.';
    }

    String email = cleanIdentifier;

    if (!cleanIdentifier.contains('@')) {
      final res = await _supabase
          .from('profiles')
          .select('email')
          .eq('username', cleanIdentifier)
          .maybeSingle();

      if (res == null) {
        throw 'Username not found.';
      }

      final profileEmail = (res['email'] as String?)?.trim();
      if (profileEmail == null || profileEmail.isEmpty) {
        throw 'This username is not linked to an email yet. Please login using your email or contact support.';
      }

      email = profileEmail;
    }

    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: cleanPassword,
      );
    } on AuthException catch (e) {
      throw e.message;
    } catch (_) {
      throw 'Unable to login right now. Please try again.';
    }
  }

  // 3. LOGOUT
  Future<void> signOut() => _supabase.auth.signOut();

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
