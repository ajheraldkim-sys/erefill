import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves a login username to its account email, case-insensitively.
///
/// Uses the `resolve_login_email` RPC so anonymous clients never need read
/// access to `profiles`. Falls back to a direct table lookup only while that
/// function is not yet deployed (PostgREST code PGRST202).
Future<String?> resolveLoginEmail(
  SupabaseClient client,
  String username,
) async {
  final input = username.trim();
  if (input.isEmpty) return null;

  try {
    final result = await client.rpc(
      'resolve_login_email',
      params: {'p_username': input},
    );
    return _clean(result);
  } on PostgrestException catch (e) {
    if (e.code != 'PGRST202') rethrow;
  }

  // Escape ilike wildcards so input like "a%" cannot match several rows.
  final pattern = input.replaceAllMapped(
    RegExp(r'[\\%_]'),
    (m) => '\\${m[0]}',
  );
  final row = await client
      .from('profiles')
      .select('email')
      .ilike('username', pattern)
      .limit(1)
      .maybeSingle();
  return _clean(row?['email']);
}

String? _clean(Object? value) {
  final email = value?.toString().trim();
  return (email == null || email.isEmpty) ? null : email;
}
