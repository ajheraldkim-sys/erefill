import 'package:flutter_test/flutter_test.dart';

import '../tool/schema_drift.dart';

void main() {
  group('Dart usage', () {
    test('finds rpc names, including ones on the next line', () {
      const source = '''
        await supabase.rpc('get_user_notification_counts');
        final result = await _client.rpc(
          'admin_list_stations',
          params: {'p_limit': 10},
        );
        SafeSupabase.rpc("acknowledge_order", params: {});
        _client.rpc(functionName); // not a literal, skipped
      ''';
      expect(extractRpcNames(source), {
        'get_user_notification_counts',
        'admin_list_stations',
        'acknowledge_order',
      });
    });

    test('finds tables but skips storage buckets and non-literals', () {
      const source = '''
        supabase.from('orders').select();
        _db
            .from('profiles')
            .select('id');
        supabase.storage.from('avatars').getPublicUrl(name);
        supabase.storage
            .from('delivery_proofs')
            .createSignedUrl(path, 60);
        final storage = supabase.storage.from('chat_attachments');
        Map<String, dynamic>.from(row);
        supabase.from(DbTables.waterOptions).select();
        RealtimeHub.instance.listen(TableWatch('owner_settings'), (_) {});
        RealtimeHub.instance.listen(
          TableWatch(
            'reviews',
            column: 'customer_id',
          ),
          (_) {},
        );
      ''';
      expect(
        extractTableNames(source, const {'waterOptions': 'products'}),
        {'orders', 'profiles', 'products', 'owner_settings', 'reviews'},
      );
    });

    test('reads DbTables constants', () {
      const source = '''
        abstract final class DbTables {
          static const waterOptions = 'products';
          static const String riderLogs = "rider_locations";
        }
      ''';
      expect(parseDbTableConstants(source), {
        'waterOptions': 'products',
        'riderLogs': 'rider_locations',
      });
    });
  });

  group('SQL definitions', () {
    test('finds functions however they are declared', () {
      const sql = '''
        CREATE OR REPLACE FUNCTION public.get_delivery_fee_config()
        create function acknowledge_order(p_order uuid)
        CREATE FUNCTION "public"."admin_list_orders" (p_limit int)
        -- DROP FUNCTION public.old_thing();
        GRANT EXECUTE ON FUNCTION public.not_a_definition() TO anon;
      ''';
      expect(sqlDefinedFunctions(sql), {
        'get_delivery_fee_config',
        'acknowledge_order',
        'admin_list_orders',
      });
    });

    test('finds tables and views', () {
      const sql = '''
        CREATE TABLE IF NOT EXISTS public.water_types (id uuid);
        create table orders (id uuid);
        CREATE TABLE "public"."audit_logs" (id bigint);
        CREATE OR REPLACE VIEW public.water_options AS SELECT 1;
        CREATE MATERIALIZED VIEW station_stats AS SELECT 1;
      ''';
      expect(sqlDefinedTables(sql), {
        'water_types',
        'orders',
        'audit_logs',
        'water_options',
        'station_stats',
      });
    });
  });

  test('missing() lists used names absent from the defined set, sorted', () {
    final usage = {
      'b_fn': {'lib/a.dart'},
      'a_fn': {'lib/b.dart', 'lib/a.dart'},
      'known': {'lib/a.dart'},
    };
    expect(missing(usage, {'known'}).keys.toList(), ['a_fn', 'b_fn']);
  });

  test('parses a live schema snapshot', () {
    final snapshot = SchemaSnapshot.fromJson({
      'functions': ['acknowledge_order', 'is_admin'],
      'tables': ['orders', 'profiles'],
    });
    expect(snapshot.functions, {'acknowledge_order', 'is_admin'});
    expect(snapshot.tables, {'orders', 'profiles'});
  });
}
