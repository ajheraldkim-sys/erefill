import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/scripts/harden_order_status_transitions.sql',
  );
  final catchup = File('supabase/scripts/remote_catchup.sql');
  final transitionFix = File(
    'supabase/scripts/fix_order_transitions_and_realtime.sql',
  );
  final proofOfDelivery = File(
    'supabase/scripts/automated_proof_of_delivery.sql',
  );
  final recreateRunner = File('supabase/scripts/recreate/run_recreate.ps1');

  test('owner completion is restricted to the audited pickup RPC', () {
    final sql = migration.readAsStringSync();
    final transition = _functionDefinition(
      sql,
      'transition_order_status_safely',
    );
    final pickup = _functionDefinition(sql, 'complete_pickup_order_safely');

    expect(transition, isNotEmpty);
    expect(transition, contains('v_order.status::text = p_new_status'));
    expect(transition, contains("IF p_new_status = 'delivered' THEN"));
    expect(
      transition,
      contains('Orders must be completed through verified delivery'),
    );
    expect(pickup, contains("v_order.delivery_type <> 'pickup'"));
    expect(pickup, contains("v_order.status <> 'ready_for_pickup'"));
    expect(
      pickup,
      contains('actual_completion_at = coalesce(actual_completion_at, now())'),
    );
    expect(pickup, isNot(contains('delivered_at')));
    expect(pickup, contains('INSERT INTO public.audit_logs'));
  });

  test('legacy scripts cannot replace hardened order lifecycle RPCs', () {
    final sql = catchup.readAsStringSync();
    final transitionFixSql = transitionFix.readAsStringSync();

    expect(
      sql,
      isNot(
        contains('CREATE OR REPLACE FUNCTION public.confirm_delivery_safely'),
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          'CREATE OR REPLACE FUNCTION public.transition_order_status_safely',
        ),
      ),
    );
    expect(
      transitionFixSql,
      isNot(
        contains(
          'CREATE OR REPLACE FUNCTION public.transition_order_status_safely',
        ),
      ),
    );
  });

  test('recreation applies hardened transitions after proof-of-delivery', () {
    final runner = recreateRunner.readAsStringSync();

    expect(
      runner.indexOf('automated_proof_of_delivery.sql'),
      lessThan(runner.indexOf('harden_order_status_transitions.sql')),
    );
    expect(runner, contains('harden_order_status_transitions.sql'));
  });

  test('proof migration removes the obsolete five-argument overload', () {
    final sql = proofOfDelivery.readAsStringSync();

    expect(
      sql,
      contains('DROP FUNCTION IF EXISTS public.confirm_delivery_safely('),
    );
    expect(
      sql,
      contains('uuid, double precision, double precision, text, text'),
    );
  });
}

String _functionDefinition(String sql, String name) {
  final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.$name(');
  if (start == -1) return '';
  final end = sql.indexOf(
    '\n'
    r'$$;',
    start,
  );
  if (end == -1) return '';
  return sql.substring(start, end + 4);
}
