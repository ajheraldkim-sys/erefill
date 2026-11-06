-- Shared fixtures for the SQL tests in this folder. Every test runs as
--   BEGIN; <scripts under test, BEGIN/COMMIT stripped>; _fixtures.sql; <test>; ROLLBACK;
-- through the Supabase MCP execute_sql tool, so nothing persists.
--
-- Fixture rows are inserted with triggers off (replica role) to skip station
-- setup checks; triggers are back on before the test body runs.
--
-- ids: owner ...a1, second owner ...a2, customer ...c1, rider ...d1,
--      admin ...e1, product ...b1 (₱19.60, owner a1).

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_owner2@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_cust@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_rider@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't_admin@example.test', '{}', '{}', now(), now());

INSERT INTO public.profiles (id, role, full_name, station_name, station_availability, latitude, longitude)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'owner', 'T Owner', 'T Station', 'open', 14.60, 121.00),
  ('00000000-0000-4000-8000-0000000000a2', 'owner', 'T Owner 2', 'T Station 2', 'open', 14.61, 121.01),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', 'T Cust', NULL, 'open', 14.62, 121.02),
  ('00000000-0000-4000-8000-0000000000d1', 'rider', 'T Rider', NULL, 'open', NULL, NULL),
  ('00000000-0000-4000-8000-0000000000e1', 'admin', 'T Admin', NULL, 'open', NULL, NULL);

INSERT INTO public.owner_settings (owner_id, base_delivery_fee)
VALUES
  ('00000000-0000-4000-8000-0000000000a1', 5.4),
  ('00000000-0000-4000-8000-0000000000a2', 0);

INSERT INTO public.products (id, owner_id, name, price, is_available)
VALUES ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'T Water', 19.6, true);

-- Fee config used by every test unless a test overrides it.
UPDATE public.system_config SET value = '{"enabled": true, "percent": 1, "fixed": 0}'::jsonb
WHERE key = 'platform_fee';

SET LOCAL session_replication_role = origin;

-- Helpers (temporary: dropped with the transaction).
CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.place_order(p_method text, p_qty integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.act_as('00000000-0000-4000-8000-0000000000c1');
  RETURN public.create_order_atomic(
    jsonb_build_object(
      'owner_id', '00000000-0000-4000-8000-0000000000a1',
      'payment_method', p_method,
      'customer_name', 'T Cust',
      'customer_address', 'Test address',
      'customer_latitude', '14.6',
      'customer_longitude', '121.0'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '00000000-0000-4000-8000-0000000000b1',
      'quantity', p_qty,
      'product_name', 'T Water'
    ))
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(p_label text, p_actual anyelement, p_expected anyelement)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION '% — expected %, got %', p_label, p_expected, p_actual;
  END IF;
END;
$$;

-- Runs p_sql and fails unless it raises an error containing p_message.
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label text, p_sql text, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_message IN SQLERRM) = 0 THEN
      RAISE EXCEPTION '% — expected error "%", got "%"', p_label, p_message, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '% — expected error "%", but it succeeded', p_label, p_message;
END;
$$;
