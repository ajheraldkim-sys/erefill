import 'package:supabase_flutter/supabase_flutter.dart';

enum GmailVerificationType { signup, emailChange }

class GmailBindingService {
  GmailBindingService._();
  static final GmailBindingService instance = GmailBindingService._();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } on AssertionError {
      return null;
    }
  }

  User? get currentUser => _client?.auth.currentUser;

  String? get currentEmail => currentUser?.email;

  bool get hasGmailAddress =>
      currentEmail?.toLowerCase().trim().endsWith('@gmail.com') ?? false;

  bool get isEmailVerified => currentUser?.emailConfirmedAt != null;

  bool get isGmailVerified => hasGmailAddress && isEmailVerified;

  Future<bool> checkGmailVerificationStatus() async => isGmailVerified;

  Future<GmailVerificationType> sendVerificationCode(
    String gmailAddress,
  ) async {
    final cleanEmail = gmailAddress.trim().toLowerCase();
    if (!_isGmailAddress(cleanEmail)) {
      throw const FormatException('Enter a valid Gmail address.');
    }

    final client = _client;
    if (client == null) {
      throw StateError('Account verification is unavailable. Try again later.');
    }

    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in again before changing your email address.');
    }

    if (user.email?.toLowerCase().trim() == cleanEmail) {
      if (user.emailConfirmedAt != null) {
        throw StateError('This Gmail address is already verified.');
      }
      await client.auth.resend(type: OtpType.signup, email: cleanEmail);
      return GmailVerificationType.signup;
    }

    await client.auth.updateUser(UserAttributes(email: cleanEmail));
    return GmailVerificationType.emailChange;
  }

  Future<bool> verifyOtpCode({
    required String gmailAddress,
    required String emailToVerify,
    required String otpCode,
    required GmailVerificationType type,
  }) async {
    final cleanEmail = gmailAddress.trim().toLowerCase();
    final cleanVerificationEmail = emailToVerify.trim().toLowerCase();
    final cleanCode = otpCode.trim();

    if (!_isGmailAddress(cleanEmail)) {
      throw const FormatException('Enter a valid Gmail address.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(cleanCode)) {
      throw const FormatException('Enter the complete 6-digit code.');
    }
    if (cleanVerificationEmail.isEmpty) {
      throw StateError('The email address for this code is unavailable.');
    }

    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Sign in again before verifying your email address.');
    }

    final response = await client.auth.verifyOTP(
      email: cleanVerificationEmail,
      token: cleanCode,
      type: switch (type) {
        GmailVerificationType.signup => OtpType.signup,
        GmailVerificationType.emailChange => OtpType.emailChange,
      },
    );
    final verifiedUser = response.user;
    if (verifiedUser == null && type == GmailVerificationType.emailChange) {
      return false;
    }
    if (verifiedUser == null ||
        verifiedUser.email?.toLowerCase().trim() != cleanEmail ||
        verifiedUser.emailConfirmedAt == null) {
      throw StateError(
        'Email verification could not be confirmed. Request a new code and try again.',
      );
    }
    return true;
  }

  bool _isGmailAddress(String email) =>
      RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$').hasMatch(email);
}
