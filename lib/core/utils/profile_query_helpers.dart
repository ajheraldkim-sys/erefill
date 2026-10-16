import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_helpers.dart';

/// Profile reads/writes that tolerate optional columns not yet migrated remotely.
abstract final class ProfileQueryHelpers {
  static const optionalFields = [
    'purok',
    'zip_code',
    'preferred_water_type',
    'updated_at',
  ];

  /// Loads the full profile row without naming optional columns in the select.
  /// PostgREST only returns columns that exist — avoids 42703 on missing fields.
  /// Returns null when the authenticated user does not have a profile row yet.
  static Future<Map<String, dynamic>?> fetchProfile(
    SupabaseClient client,
    String userId,
  ) async {
    final profile = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return profile == null ? null : Map<String, dynamic>.from(profile);
  }

  /// Ensures that a row for [userId] exists in public.profiles.
  /// First checks if it already exists, then attempts ensure_user_profile RPC,
  /// and falls back to a clean upsert based on auth.currentUser metadata.
  static Future<Map<String, dynamic>?> ensureProfileExists(
    SupabaseClient client, {
    String? userId,
  }) async {
    final targetId = userId ?? client.auth.currentUser?.id;
    if (targetId == null) return null;

    // 1. If row already exists, return it immediately
    try {
      final existing = await fetchProfile(client, targetId);
      if (existing != null) return existing;
    } catch (_) {}

    // 2. Try the security definer RPC ensure_user_profile
    try {
      final res = await client.rpc('ensure_user_profile');
      if (res is Map && res['success'] == true) {
        final prof = await fetchProfile(client, targetId);
        if (prof != null) return prof;
      }
    } catch (_) {}

    // 3. Fallback: synthesize minimal valid profile row from authenticated user
    final authUser = client.auth.currentUser;
    if (authUser != null && authUser.id == targetId) {
      final meta = authUser.userMetadata ?? {};
      final rawTown = meta['town']?.toString();
      final town = (rawTown == 'Cantilan' || rawTown == 'Madrid')
          ? rawTown
          : null;
      final rawRole = meta['role']?.toString();
      final role =
          rawRole != null &&
              const {'customer', 'owner', 'rider'}.contains(rawRole)
          ? rawRole
          : 'customer';

      final minimal = <String, dynamic>{
        'id': targetId,
        'email': authUser.email ?? '',
        'username':
            meta['username'] ??
            'user_${targetId.length >= 8 ? targetId.substring(0, 8) : targetId}',
        'full_name': meta['full_name'] ?? 'User',
        'role': role,
      };
      if (meta['phone'] != null) minimal['phone'] = meta['phone'];
      if (town != null) minimal['town'] = town;
      if (meta['barangay'] != null) minimal['barangay'] = meta['barangay'];
      if (meta['complete_address'] != null) {
        minimal['complete_address'] = meta['complete_address'];
      }

      try {
        await client.from('profiles').upsert(minimal, onConflict: 'id');
        return await fetchProfile(client, targetId);
      } catch (_) {}
    }

    return null;
  }

  static Future<void> updateProfile(
    SupabaseClient client,
    Map<String, dynamic> payload, {
    String? userId,
  }) async {
    var data = Map<String, dynamic>.from(payload);
    final targetId = userId ?? client.auth.currentUser?.id;
    if (targetId == null) {
      throw StateError('Cannot update profile: user is not authenticated.');
    }
    data.remove('id');
    data.remove('email');
    data.remove('role');
    // profiles table does not have an updated_at column in schema cache
    data.remove('updated_at');

    while (true) {
      try {
        final updated = await client
            .from('profiles')
            .update(data)
            .eq('id', targetId)
            .select('id')
            .maybeSingle();
        if (updated != null) {
          return;
        }

        await client.from('profiles').upsert({
          ...data,
          'id': targetId,
        }, onConflict: 'id');
        return;
      } catch (e) {
        final missing = _missingOptionalField(e, data.keys.toList());
        if (missing == null) rethrow;
        data.remove(missing);
      }
    }
  }

  static String? _missingOptionalField(Object error, List<String> candidates) {
    for (final field in optionalFields) {
      if (candidates.contains(field) &&
          SupabaseHelpers.isMissingColumnError(error, field)) {
        return field;
      }
    }
    return null;
  }
}
