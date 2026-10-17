import 'dart:async';
import 'package:erefill/core/services/local_data_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerSettingsService {
  final SupabaseClient _client = Supabase.instance.client;
  final LocalDataCache _cache = LocalDataCache.instance;

  Future<Map<String, dynamic>?> getSettings(String ownerId) async {
    final cached = _cache.getMemory<Map<String, dynamic>>('owner_settings_$ownerId');
    if (cached != null) {
      unawaited(_fetchAndCache(ownerId));
      return cached;
    }

    final disk = await _cache.get<Map<String, dynamic>>('owner_settings_$ownerId');
    if (disk != null) {
      unawaited(_fetchAndCache(ownerId));
      return disk;
    }

    return _fetchAndCache(ownerId);
  }

  Future<Map<String, dynamic>?> _fetchAndCache(String ownerId) async {
    try {
      final res = await _client
          .from('owner_settings')
          .select()
          .eq('owner_id', ownerId)
          .maybeSingle();
      if (res != null) {
        await _cache.set('owner_settings_$ownerId', res);
      }
      return res;
    } catch (_) {
      return _cache.getMemory<Map<String, dynamic>>('owner_settings_$ownerId');
    }
  }

  Future<void> updateSettings(
    String ownerId,
    Map<String, dynamic> updates,
  ) async {
    updates['updated_at'] = DateTime.now().toIso8601String();
    updates['owner_id'] = ownerId;

    await _cache.set('owner_settings_$ownerId', updates);

    try {
      await _client.from('owner_settings').upsert(
        updates,
        onConflict: 'owner_id',
      );
    } catch (e) {
      if (updates.containsKey('delivery_ack') && e.toString().contains('delivery_ack')) {
        final fallbackUpdates = Map<String, dynamic>.from(updates)..remove('delivery_ack');
        await _client.from('owner_settings').upsert(
          fallbackUpdates,
          onConflict: 'owner_id',
        );
        return;
      }
      rethrow;
    }
  }
}
