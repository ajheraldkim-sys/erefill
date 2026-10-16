class FriendlyErrors {
  const FriendlyErrors._();

  static String message(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    final raw = error.toString().trim();
    final lower = raw.toLowerCase();

    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials')) {
      return 'That email or password does not look right.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    if (lower.contains('user already registered') ||
        lower.contains('already registered') ||
        lower.contains('already exists') ||
        lower.contains('duplicate key')) {
      return 'An account already exists with these details.';
    }
    if (lower.contains('password') && lower.contains('weak')) {
      return 'Please choose a stronger password.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection')) {
      return 'Please check your internet connection and try again.';
    }
    if (lower.contains('permission') ||
        lower.contains('row-level security') ||
        lower.contains('rls')) {
      return 'You do not have permission to make that change.';
    }
    if (lower.contains('timeout')) {
      return 'The request took too long. Please try again.';
    }
    if (lower.contains('google sign-in was cancelled') ||
        lower.contains('google sign in was cancelled') ||
        lower.contains('google sign in cancelled')) {
      return 'Google sign-in was cancelled.';
    }
    if (lower.contains('apiexception 10') ||
        lower.contains('developer_error') ||
        lower.contains('sha-1')) {
      return 'Google Sign-In configuration error (ApiException 10). The Android SHA-1 fingerprint is not registered in Google Cloud Console for package com.erefill.app.';
    }
    if (lower.contains('apiexception 12500')) {
      return 'Google Sign-In failed (ApiException 12500). Please check OAuth consent screen configuration or Google Play Services.';
    }
    if (lower.contains('google authentication failed:') ||
        lower.contains('google sign-in misconfigured') ||
        lower.contains('google sign-in configuration error')) {
      return raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    }

    final cleaned = raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^AuthException\(.*message:\s*'), '')
        .replaceAll(RegExp(r',\s*statusCode:.*\)$'), '')
        .trim();

    if (cleaned.isNotEmpty &&
        cleaned.length <= 90 &&
        !cleaned.contains('PostgrestException') &&
        !cleaned.contains('AuthException(')) {
      return cleaned;
    }
    return fallback;
  }
}

class AppValidators {
  const AppValidators._();

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _phonePattern = RegExp(r'^(09|\+639)\d{9}$');
  static final _namePattern = RegExp(r"^[A-Za-z][A-Za-z .'-]*$");
  static final _usernamePattern = RegExp(r'^[A-Za-z0-9_]{3,24}$');

  static String? requiredText(String? value, String label) {
    return value == null || value.trim().isEmpty ? '$label is required.' : null;
  }

  static String? name(String? value, String label) {
    final requiredMessage = requiredText(value, label);
    if (requiredMessage != null) return requiredMessage;
    final trimmed = value!.trim();
    if (trimmed.length < 2) return '$label must be at least 2 characters.';
    if (!_namePattern.hasMatch(trimmed)) {
      return '$label can only include letters, spaces, hyphens, and periods.';
    }
    return null;
  }

  static String? optionalInitial(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z]\.?$').hasMatch(trimmed)) {
      return 'Use one letter for M.I.';
    }
    return null;
  }

  static String? phone(String? value) {
    final requiredMessage = requiredText(value, 'Phone number');
    if (requiredMessage != null) return requiredMessage;
    if (!_phonePattern.hasMatch(value!.trim())) {
      return 'Enter a valid PH mobile number, like 09123456789.';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredMessage = requiredText(value, 'Email');
    if (requiredMessage != null) return requiredMessage;
    if (!_emailPattern.hasMatch(value!.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? username(String? value) {
    final requiredMessage = requiredText(value, 'Username');
    if (requiredMessage != null) return requiredMessage;
    if (!_usernamePattern.hasMatch(value!.trim())) {
      return 'Use 3-24 letters, numbers, or underscores.';
    }
    return null;
  }

  static String? password(String? value) {
    final requiredMessage = requiredText(value, 'Password');
    if (requiredMessage != null) return requiredMessage;
    final password = value!.trim();
    if (password.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      return 'Use at least one letter and one number.';
    }
    return null;
  }
}
