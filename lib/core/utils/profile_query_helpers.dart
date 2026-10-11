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
  static Future<Map<String, dynamic>> fetchProfile(
    SupabaseClient client,
    String userId,
  ) async {
    return Map<String, dynamic>.from(
      await client.from('profiles').select().eq('id', userId).single(),
    );
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
        if (updated == null) {
          throw StateError(
            'Cannot update profile: no profile row is available for this user.',
          );
        }
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
