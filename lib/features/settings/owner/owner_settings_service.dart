import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerSettingsService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<Map<String, dynamic>?> getSettings(String ownerId) async {
    final res = await _client
        .from('owner_settings')
        .select()
        .eq('owner_id', ownerId)
        .maybeSingle();
    return res;
  }

  Future<void> updateSettings(
    String ownerId,
    Map<String, dynamic> updates,
  ) async {
    updates['updated_at'] = DateTime.now().toIso8601String();
    updates['owner_id'] = ownerId;

    await _client.from('owner_settings').upsert(
      updates,
      onConflict: 'owner_id',
    );
  }
}
