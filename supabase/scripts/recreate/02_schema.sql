


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."chat_room_status" AS ENUM (
    'active',
    'archived',
    'closed'
);


ALTER TYPE "public"."chat_room_status" OWNER TO "postgres";


CREATE TYPE "public"."chat_room_type" AS ENUM (
    'order_delivery',
    'customer_support',
    'rider_dispatch',
    'broadcast'
);


ALTER TYPE "public"."chat_room_type" OWNER TO "postgres";


CREATE TYPE "public"."dispute_status" AS ENUM (
    'open',
    'investigating',
    'resolved',
    'dismissed'
);


ALTER TYPE "public"."dispute_status" OWNER TO "postgres";


CREATE TYPE "public"."message_status" AS ENUM (
    'sending',
    'sent',
    'delivered',
    'seen',
    'failed'
);


ALTER TYPE "public"."message_status" OWNER TO "postgres";


CREATE TYPE "public"."message_type" AS ENUM (
    'text',
    'image',
    'system',
    'quick_reply',
    'location',
    'file'
);


ALTER TYPE "public"."message_type" OWNER TO "postgres";


CREATE TYPE "public"."municipality" AS ENUM (
    'Carrascal',
    'Cantilan',
    'Madrid',
    'Carmen',
    'Lanuza'
);


ALTER TYPE "public"."municipality" OWNER TO "postgres";


CREATE TYPE "public"."notification_priority" AS ENUM (
    'low',
    'normal',
    'high',
    'urgent'
);


ALTER TYPE "public"."notification_priority" OWNER TO "postgres";


CREATE TYPE "public"."notification_type" AS ENUM (
    'order_assigned',
    'earnings_payout',
    'system_alert',
    'station_broadcast',
    'order_cancelled',
    'new_message',
    'delivery_reminder'
);


ALTER TYPE "public"."notification_type" OWNER TO "postgres";


CREATE TYPE "public"."order_status" AS ENUM (
    'pending',
    'accepted',
    'out_for_delivery',
    'delivered',
    'cancelled',
    'preparing',
    'failed',
    'ready_for_pickup',
    'assigned_to_rider'
);


ALTER TYPE "public"."order_status" OWNER TO "postgres";


COMMENT ON TYPE "public"."order_status" IS 'Order status values: pending, accepted, preparing, out_for_delivery, delivered, cancelled, failed';



CREATE TYPE "public"."participant_role" AS ENUM (
    'customer',
    'rider',
    'owner',
    'system'
);


ALTER TYPE "public"."participant_role" OWNER TO "postgres";


CREATE TYPE "public"."payment_status" AS ENUM (
    'pending',
    'processing',
    'success',
    'failed',
    'refunded'
);


ALTER TYPE "public"."payment_status" OWNER TO "postgres";


CREATE TYPE "public"."primary_water_type" AS ENUM (
    'Purified Water',
    'Mineral Water',
    'Alkaline Water'
);


ALTER TYPE "public"."primary_water_type" OWNER TO "postgres";


CREATE TYPE "public"."schedule_frequency" AS ENUM (
    'Daily',
    'Weekly',
    'Bi-Weekly',
    'Monthly'
);


ALTER TYPE "public"."schedule_frequency" OWNER TO "postgres";


CREATE TYPE "public"."station_water_type" AS ENUM (
    'Purified Water',
    'Mineral Water',
    'Alkaline Water'
);


ALTER TYPE "public"."station_water_type" OWNER TO "postgres";


CREATE TYPE "public"."user_role" AS ENUM (
    'customer',
    'owner',
    'rider',
    'admin'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";


CREATE TYPE "public"."water_type_option" AS ENUM (
    'Purified Water',
    'Mineral Water',
    'Alkaline Water'
);


ALTER TYPE "public"."water_type_option" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_admin_cleanup_user_links"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.orders SET customer_id = NULL WHERE customer_id = p_user_id;
  UPDATE public.orders SET owner_id = NULL WHERE owner_id = p_user_id;
  UPDATE public.orders SET assigned_rider_id = NULL WHERE assigned_rider_id = p_user_id;
  UPDATE public.messages SET sender_id = NULL WHERE sender_id = p_user_id;
  UPDATE public.reviews SET customer_id = NULL WHERE customer_id = p_user_id;
  DELETE FROM public.chat_participants WHERE user_id = p_user_id;
  UPDATE public.chat_rooms SET owner_id = NULL WHERE owner_id = p_user_id;
  DELETE FROM public.rider_locations WHERE rider_id = p_user_id;
END;
$$;


ALTER FUNCTION "public"."_admin_cleanup_user_links"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_broadcast_notification"("p_role" "text", "p_title" "text", "p_content" "text", "p_priority" "text" DEFAULT 'normal'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_count integer := 0;
  v_user record;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;

  FOR v_user IN
    SELECT id FROM public.profiles
    WHERE role::text = p_role AND coalesce(is_suspended, false) = false
  LOOP
    INSERT INTO public.system_notifications (user_id, type, priority, title, content)
    VALUES (v_user.id, 'system_alert', p_priority::public.notification_priority, trim(p_title), trim(p_content));
    v_count := v_count + 1;
  END LOOP;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value)
  VALUES (auth.uid(), 'admin_broadcast_notification', 'notification', p_role,
    jsonb_build_object('count', v_count, 'title', p_title));

  RETURN jsonb_build_object('success', true, 'sent_count', v_count);
END;
$$;


ALTER FUNCTION "public"."admin_broadcast_notification"("p_role" "text", "p_title" "text", "p_content" "text", "p_priority" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_cancel_order"("p_order_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;

  SELECT to_jsonb(o.*) INTO v_old FROM public.orders o WHERE o.id = p_order_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;

  IF (v_old->>'status') IN ('delivered', 'cancelled') THEN
    RAISE EXCEPTION 'Order cannot be cancelled in status %', v_old->>'status';
  END IF;

  UPDATE public.orders
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (auth.uid(), 'admin_cancel_order', 'order', p_order_id::text, v_old,
    jsonb_build_object('status', 'cancelled'), jsonb_build_object('reason', p_reason));

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT o.customer_id, 'order_cancelled', 'high', 'Order cancelled',
    coalesce(p_reason, 'Your order was cancelled by platform support.'),
    jsonb_build_object('order_id', p_order_id)
  FROM public.orders o WHERE o.id = p_order_id AND o.customer_id IS NOT NULL;

  RETURN jsonb_build_object('success', true, 'order_id', p_order_id);
END;
$$;


ALTER FUNCTION "public"."admin_cancel_order"("p_order_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_create_station"("p_email" "text", "p_password" "text", "p_station_name" "text", "p_owner_name" "text", "p_phone" "text" DEFAULT NULL::"text", "p_town" "text" DEFAULT NULL::"text", "p_barangay" "text" DEFAULT NULL::"text", "p_complete_address" "text" DEFAULT NULL::"text", "p_latitude" double precision DEFAULT NULL::double precision, "p_longitude" double precision DEFAULT NULL::double precision, "p_region_id" "uuid" DEFAULT NULL::"uuid", "p_base_delivery_fee" numeric DEFAULT 15, "p_price_per_gallon" numeric DEFAULT 25, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_user_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;

  IF v_email IS NULL OR position('@' in v_email) = 0 THEN
    RAISE EXCEPTION 'Invalid email';
  END IF;
  IF p_password IS NULL OR length(p_password) < 6 THEN
    RAISE EXCEPTION 'Password must be at least 6 characters';
  END IF;

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated',
    v_email, extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('role', 'owner', 'full_name', trim(p_owner_name), 'station_name', trim(p_station_name)),
    now(), now()
  );

  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, created_at, updated_at)
  VALUES (gen_random_uuid(), v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
    'email', v_user_id::text, now(), now());

  INSERT INTO public.profiles (
    id, email, full_name, phone, role, station_name, town, barangay,
    complete_address, latitude, longitude, region_id, station_availability, is_open
  ) VALUES (
    v_user_id, v_email, trim(p_owner_name), nullif(trim(p_phone), ''), 'owner'::public.user_role,
    trim(p_station_name), nullif(trim(p_town), ''), nullif(trim(p_barangay), ''),
    nullif(trim(p_complete_address), ''), p_latitude, p_longitude, p_region_id, 'open', true
  );

  INSERT INTO public.owner_settings (owner_id, base_delivery_fee, price_per_gallon, service_radius_km, max_concurrent_orders)
  VALUES (v_user_id, coalesce(p_base_delivery_fee, 15), coalesce(p_price_per_gallon, 25), 5, 20);

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'admin_create_station', 'station', v_user_id::text,
    jsonb_build_object('station_name', trim(p_station_name), 'email', v_email),
    jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true, 'owner_id', v_user_id, 'email', v_email);
END;
$$;


ALTER FUNCTION "public"."admin_create_station"("p_email" "text", "p_password" "text", "p_station_name" "text", "p_owner_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_region_id" "uuid", "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_create_user"("p_email" "text", "p_password" "text", "p_role" "text", "p_full_name" "text", "p_phone" "text" DEFAULT NULL::"text", "p_town" "text" DEFAULT NULL::"text", "p_barangay" "text" DEFAULT NULL::"text", "p_owner_id" "uuid" DEFAULT NULL::"uuid", "p_region_id" "uuid" DEFAULT NULL::"uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_user_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;

  IF v_email IS NULL OR position('@' in v_email) = 0 THEN
    RAISE EXCEPTION 'Invalid email';
  END IF;
  IF p_password IS NULL OR length(p_password) < 6 THEN
    RAISE EXCEPTION 'Password must be at least 6 characters';
  END IF;
  IF p_role NOT IN ('customer', 'rider') THEN
    RAISE EXCEPTION 'Role must be customer or rider for admin_create_user';
  END IF;
  IF p_role = 'rider' AND p_owner_id IS NULL THEN
    RAISE EXCEPTION 'owner_id required for rider';
  END IF;

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated',
    v_email, extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('role', p_role, 'full_name', trim(p_full_name)),
    now(), now()
  );

  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, created_at, updated_at)
  VALUES (gen_random_uuid(), v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
    'email', v_user_id::text, now(), now());

  INSERT INTO public.profiles (id, email, full_name, phone, role, town, barangay, owner_id, region_id)
  VALUES (v_user_id, v_email, trim(p_full_name), nullif(trim(p_phone), ''),
    p_role::public.user_role, nullif(trim(p_town), ''), nullif(trim(p_barangay), ''),
    p_owner_id, p_region_id);

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'admin_create_user', 'user', v_user_id::text,
    jsonb_build_object('email', v_email, 'role', p_role), jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true, 'user_id', v_user_id, 'email', v_email);
END;
$$;


ALTER FUNCTION "public"."admin_create_user"("p_email" "text", "p_password" "text", "p_role" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_owner_id" "uuid", "p_region_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_dashboard_stats"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_today date := (timezone('Asia/Manila', now()))::date;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN jsonb_build_object(
    'orders_today', (
      SELECT count(*)
      FROM public.orders
      WHERE (timezone('Asia/Manila', created_at))::date = v_today
    ),
    'open_stations', (
      SELECT count(*)
      FROM public.profiles
      WHERE role::text = 'owner'
        AND coalesce(station_availability, 'open') = 'open'
    ),
    'active_orders', (
      SELECT count(*)
      FROM public.orders
      WHERE status::text NOT IN ('delivered', 'cancelled')
    ),
    'failed_payments', public.admin_failed_payments_count(),
    'customers', (
      SELECT count(*) FROM public.profiles WHERE role::text = 'customer'
    ),
    'owners', (
      SELECT count(*) FROM public.profiles WHERE role::text = 'owner'
    ),
    'riders', (
      SELECT count(*) FROM public.profiles WHERE role::text = 'rider'
    ),
    'maintenance_mode', coalesce((
      SELECT (value::text)::boolean
      FROM public.system_config
      WHERE key = 'maintenance_mode'
    ), false)
  );
END;
$$;


ALTER FUNCTION "public"."admin_dashboard_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_delete_product"("p_product_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;
  DELETE FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found'; END IF;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'admin_delete_product', 'product', p_product_id::text,
    jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."admin_delete_product"("p_product_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_delete_review"("p_review_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  DELETE FROM public.reviews WHERE id = p_review_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Review not found'; END IF;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'admin_delete_review', 'review', p_review_id::text,
    jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."admin_delete_review"("p_review_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_delete_station"("p_owner_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_owner_id AND role::text = 'owner'
  ) THEN
    RAISE EXCEPTION 'Station not found';
  END IF;

  PERFORM public.admin_delete_user(p_owner_id, coalesce(p_reason, 'Station deleted by admin'));

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (
    auth.uid(),
    'admin_delete_station',
    'station',
    p_owner_id::text,
    jsonb_build_object('reason', p_reason)
  );

  RETURN jsonb_build_object('success', true, 'deleted_owner_id', p_owner_id);
END;
$$;


ALTER FUNCTION "public"."admin_delete_station"("p_owner_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_delete_user"("p_user_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_role text;
  v_rider record;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;
  IF p_user_id = auth.uid() THEN RAISE EXCEPTION 'Cannot delete your own admin account'; END IF;

  SELECT role::text INTO v_role FROM public.profiles WHERE id = p_user_id;
  IF v_role IS NULL THEN RAISE EXCEPTION 'User not found'; END IF;
  IF v_role = 'admin' THEN RAISE EXCEPTION 'Cannot delete admin accounts'; END IF;

  IF v_role = 'owner' THEN
    FOR v_rider IN SELECT id FROM public.profiles WHERE owner_id = p_user_id AND role::text = 'rider'
    LOOP
      PERFORM public._admin_cleanup_user_links(v_rider.id);
      DELETE FROM public.profiles WHERE id = v_rider.id;
      DELETE FROM auth.users WHERE id = v_rider.id;
    END LOOP;
  END IF;

  PERFORM public._admin_cleanup_user_links(p_user_id);
  DELETE FROM public.profiles WHERE id = p_user_id;
  DELETE FROM auth.users WHERE id = p_user_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'admin_delete_user', 'user', p_user_id::text,
    jsonb_build_object('reason', p_reason, 'role', v_role));

  RETURN jsonb_build_object('success', true, 'deleted_user_id', p_user_id);
END;
$$;


ALTER FUNCTION "public"."admin_delete_user"("p_user_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_failed_payments_count"() RETURNS bigint
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_count bigint := 0;
BEGIN
  IF to_regclass('public.payment_webhook_events') IS NULL THEN
    RETURN 0;
  END IF;

  EXECUTE $sql$
    SELECT count(*)::bigint
    FROM public.payment_webhook_events
    WHERE processing_status = 'failed'
      AND created_at >= now() - interval '7 days'
  $sql$ INTO v_count;

  RETURN coalesce(v_count, 0);
END;
$_$;


ALTER FUNCTION "public"."admin_failed_payments_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_activity_timeline"("p_entity_type" "text", "p_entity_id" "uuid", "p_limit" integer DEFAULT 50) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_events jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  p_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  IF p_entity_type = 'user' THEN
    SELECT coalesce(jsonb_agg(ev ORDER BY (ev->>'at') DESC), '[]'::jsonb) INTO v_events
    FROM (
      SELECT jsonb_build_object('at', a.created_at, 'type', 'audit', 'action', a.action, 'detail', a.new_value) AS ev
      FROM public.audit_logs a
      WHERE a.entity_id = p_entity_id::text OR a.actor_id = p_entity_id
      UNION ALL
      SELECT jsonb_build_object('at', o.created_at, 'type', 'order', 'action', o.status::text,
        'detail', jsonb_build_object('order_id', o.id, 'total', o.total_amount, 'station', o.station_name))
      FROM public.orders o
      WHERE o.customer_id = p_entity_id OR o.owner_id = p_entity_id OR o.assigned_rider_id = p_entity_id
      LIMIT p_limit
    ) combined;
  ELSIF p_entity_type = 'station' THEN
    SELECT coalesce(jsonb_agg(ev ORDER BY (ev->>'at') DESC), '[]'::jsonb) INTO v_events
    FROM (
      SELECT jsonb_build_object('at', a.created_at, 'type', 'audit', 'action', a.action, 'detail', a.new_value) AS ev
      FROM public.audit_logs a
      WHERE a.entity_id = p_entity_id::text
      UNION ALL
      SELECT jsonb_build_object('at', o.created_at, 'type', 'order', 'action', o.status::text,
        'detail', jsonb_build_object('order_id', o.id, 'total', o.total_amount))
      FROM public.orders o WHERE o.owner_id = p_entity_id
      LIMIT p_limit
    ) combined;
  ELSE
    RAISE EXCEPTION 'entity_type must be user or station';
  END IF;

  RETURN jsonb_build_object('events', v_events);
END;
$$;


ALTER FUNCTION "public"."admin_get_activity_timeline"("p_entity_type" "text", "p_entity_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_order_detail"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order jsonb;
  v_items jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;

  SELECT to_jsonb(o.*) INTO v_order FROM public.orders o WHERE o.id = p_order_id;
  IF v_order IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(i.*)), '[]'::jsonb)
  INTO v_items
  FROM public.order_items i
  WHERE i.order_id = p_order_id;

  RETURN jsonb_build_object(
    'order', v_order,
    'items', v_items,
    'customer', (SELECT to_jsonb(p.*) FROM public.profiles p WHERE p.id = (v_order->>'customer_id')::uuid),
    'owner', (SELECT to_jsonb(p.*) FROM public.profiles p WHERE p.id = (v_order->>'owner_id')::uuid),
    'rider', (SELECT to_jsonb(p.*) FROM public.profiles p WHERE p.id = (v_order->>'assigned_rider_id')::uuid),
    'available_riders', coalesce((
      SELECT jsonb_agg(jsonb_build_object('id', r.id, 'full_name', r.full_name, 'phone', r.phone, 'is_online', coalesce(r.is_online, false)))
      FROM public.profiles r
      WHERE r.role::text = 'rider'
        AND r.owner_id = (v_order->>'owner_id')::uuid
        AND coalesce(r.is_suspended, false) = false
    ), '[]'::jsonb)
  );
END;
$$;


ALTER FUNCTION "public"."admin_get_order_detail"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_platform_fee"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;
  RETURN public.get_platform_fee_config();
END;
$$;


ALTER FUNCTION "public"."admin_get_platform_fee"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_station_detail"("p_owner_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_profile jsonb;
  v_settings jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  SELECT to_jsonb(p.*)
  INTO v_profile
  FROM public.profiles p
  WHERE p.id = p_owner_id AND p.role::text = 'owner';

  IF v_profile IS NULL THEN
    RAISE EXCEPTION 'Station not found';
  END IF;

  SELECT to_jsonb(s.*)
  INTO v_settings
  FROM public.owner_settings s
  WHERE s.owner_id = p_owner_id;

  RETURN jsonb_build_object(
    'profile', v_profile,
    'settings', coalesce(v_settings, '{}'::jsonb),
    'stats', jsonb_build_object(
      'rider_count', (
        SELECT count(*) FROM public.profiles r
        WHERE r.owner_id = p_owner_id AND r.role::text = 'rider'
      ),
      'customer_count', (
        SELECT count(DISTINCT o.customer_id)
        FROM public.orders o
        WHERE o.owner_id = p_owner_id AND o.customer_id IS NOT NULL
      ),
      'total_orders', (
        SELECT count(*) FROM public.orders o WHERE o.owner_id = p_owner_id
      ),
      'active_orders', (
        SELECT count(*) FROM public.orders o
        WHERE o.owner_id = p_owner_id
          AND o.status::text NOT IN ('delivered', 'cancelled')
      ),
      'total_revenue', coalesce((
        SELECT sum(o.total_amount) FROM public.orders o
        WHERE o.owner_id = p_owner_id AND o.status::text = 'delivered'
      ), 0),
      'product_count', (
        SELECT count(*) FROM public.products pr WHERE pr.owner_id = p_owner_id
      )
    )
  );
END;
$$;


ALTER FUNCTION "public"."admin_get_station_detail"("p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_user_detail"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_profile jsonb;
  v_role text;
  v_owner jsonb;
  v_stats jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  SELECT to_jsonb(p.*), p.role::text
  INTO v_profile, v_role
  FROM public.profiles p
  WHERE p.id = p_user_id AND p.role::text <> 'admin';

  IF v_profile IS NULL THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  IF v_role = 'rider' THEN
    SELECT to_jsonb(o.*)
    INTO v_owner
    FROM public.profiles o
    WHERE o.id = (v_profile->>'owner_id')::uuid;
  END IF;

  v_stats := jsonb_build_object(
    'order_count', (
      SELECT count(*) FROM public.orders o
      WHERE o.customer_id = p_user_id
         OR o.owner_id = p_user_id
         OR o.assigned_rider_id = p_user_id
    ),
    'delivered_orders', (
      SELECT count(*) FROM public.orders o
      WHERE (o.customer_id = p_user_id OR o.owner_id = p_user_id OR o.assigned_rider_id = p_user_id)
        AND o.status::text = 'delivered'
    )
  );

  RETURN jsonb_build_object(
    'profile', v_profile,
    'owner_station', coalesce(v_owner, 'null'::jsonb),
    'stats', v_stats
  );
END;
$$;


ALTER FUNCTION "public"."admin_get_user_detail"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_admins"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', p.id, 'email', p.email, 'full_name', p.full_name,
      'admin_tier', coalesce(p.admin_tier, 'super'),
      'created_at', (SELECT u.created_at FROM auth.users u WHERE u.id = p.id)
    ) ORDER BY p.full_name)
    FROM public.profiles p WHERE p.role::text = 'admin'
  ), '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."admin_list_admins"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_audit_logs"("p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  p_limit := least(greatest(coalesce(p_limit, 100), 1), 500);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*) INTO v_total FROM public.audit_logs;

  SELECT coalesce(jsonb_agg(row_to_json(log_row)), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      a.id,
      a.created_at,
      a.actor_id,
      a.action,
      a.entity_type,
      a.entity_id,
      a.old_value,
      a.new_value,
      a.metadata
    FROM public.audit_logs a
    ORDER BY a.created_at DESC
    LIMIT p_limit
    OFFSET p_offset
  ) log_row;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_audit_logs"("p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_disputes"("p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0, "p_status" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  p_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*) INTO v_total FROM public.disputes d
  WHERE p_status IS NULL OR p_status = '' OR d.status::text = p_status;

  SELECT coalesce(jsonb_agg(row_to_json(drow)), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT d.*, p.full_name AS reporter_name, o.station_name, o.total_amount
    FROM public.disputes d
    LEFT JOIN public.profiles p ON p.id = d.reporter_id
    LEFT JOIN public.orders o ON o.id = d.order_id
    WHERE p_status IS NULL OR p_status = '' OR d.status::text = p_status
    ORDER BY d.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) drow;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_disputes"("p_limit" integer, "p_offset" integer, "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_inventory_ledger"("p_owner_id" "uuid", "p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  p_limit := least(greatest(coalesce(p_limit, 100), 1), 500);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*) INTO v_total FROM public.owner_inventory_ledger WHERE owner_id = p_owner_id;

  SELECT coalesce(jsonb_agg(row_to_json(l)), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT * FROM public.owner_inventory_ledger
    WHERE owner_id = p_owner_id
    ORDER BY created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) l;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_inventory_ledger"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_live_riders"("p_region_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;

  RETURN coalesce((
    SELECT jsonb_agg(row_to_json(r) ORDER BY r.full_name)
    FROM (
      SELECT DISTINCT ON (p.id)
        p.id AS rider_id,
        p.full_name,
        p.phone,
        p.owner_id,
        o.station_name,
        coalesce(p.is_online, false) AS is_online,
        rl.latitude,
        rl.longitude,
        rl.heading,
        rl.speed,
        rl.timestamp AS last_seen,
        p.region_id,
        rg.name AS region_name,
        (
          SELECT count(*)
          FROM public.orders ord
          WHERE ord.assigned_rider_id = p.id
            AND ord.status::text IN ('assigned_to_rider', 'out_for_delivery')
        ) AS active_deliveries
      FROM public.profiles p
      LEFT JOIN public.profiles o ON o.id = p.owner_id
      LEFT JOIN public.regions rg ON rg.id = p.region_id
      LEFT JOIN LATERAL (
        SELECT latitude, longitude, heading, speed, timestamp
        FROM public.rider_locations
        WHERE rider_id = p.id
        ORDER BY timestamp DESC
        LIMIT 1
      ) rl ON true
      WHERE p.role::text = 'rider'
        AND coalesce(p.is_suspended, false) = false
        AND (p_region_id IS NULL OR p.region_id = p_region_id)
      ORDER BY p.id, rl.timestamp DESC NULLS LAST
    ) r
  ), '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."admin_list_live_riders"("p_region_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_orders"("p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0, "p_status" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  p_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*)
  INTO v_total
  FROM public.orders o
  WHERE p_status IS NULL OR p_status = '' OR o.status::text = p_status;

  SELECT coalesce(jsonb_agg(row_to_json(order_row)), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      o.id,
      o.status,
      o.payment_method,
      o.subtotal,
      o.delivery_fee,
      o.platform_fee,
      o.total_amount,
      o.station_name,
      o.created_at,
      o.customer_id,
      o.owner_id,
      o.assigned_rider_id
    FROM public.orders o
    WHERE p_status IS NULL OR p_status = '' OR o.status::text = p_status
    ORDER BY o.created_at DESC
    LIMIT p_limit
    OFFSET p_offset
  ) order_row;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_orders"("p_limit" integer, "p_offset" integer, "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_payment_failures"("p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;

  IF to_regclass('public.payment_webhook_events') IS NULL THEN
    RETURN jsonb_build_object('total', 0, 'rows', '[]'::jsonb);
  END IF;

  p_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  EXECUTE $sql$
    SELECT count(*)::bigint FROM public.payment_webhook_events
    WHERE processing_status = 'failed'
  $sql$ INTO v_total;

  EXECUTE $sql$
    SELECT coalesce(jsonb_agg(row_to_json(e)), '[]'::jsonb)
    FROM (
      SELECT
        w.id, w.checkout_id, w.order_id, w.customer_id, w.owner_id,
        w.provider, w.event_type, w.provider_status, w.processing_status,
        w.error_message, w.created_at, w.processed_at,
        o.station_name, o.total_amount,
        c.full_name AS customer_name
      FROM public.payment_webhook_events w
      LEFT JOIN public.orders o ON o.id = w.order_id
      LEFT JOIN public.profiles c ON c.id = w.customer_id
      WHERE w.processing_status = 'failed'
      ORDER BY w.created_at DESC
      LIMIT $1 OFFSET $2
    ) e
  $sql$ USING p_limit, p_offset INTO v_rows;

  RETURN jsonb_build_object('total', coalesce(v_total, 0), 'rows', coalesce(v_rows, '[]'::jsonb));
END;
$_$;


ALTER FUNCTION "public"."admin_list_payment_failures"("p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_regions"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(row_to_json(r) ORDER BY r.name)
    FROM (
      SELECT id, name, code, base_delivery_fee, sla_goal_mins, is_active
      FROM public.regions
      ORDER BY name
    ) r
  ), '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."admin_list_regions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_reviews"("p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0, "p_min_rating" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  p_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*) INTO v_total FROM public.reviews r
  WHERE p_min_rating IS NULL OR r.rating <= p_min_rating;

  SELECT coalesce(jsonb_agg(row_to_json(rrow)), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT r.*, c.full_name AS customer_name, s.station_name
    FROM public.reviews r
    LEFT JOIN public.profiles c ON c.id = r.customer_id
    LEFT JOIN public.profiles s ON s.id = r.station_id
    WHERE p_min_rating IS NULL OR r.rating <= p_min_rating
    ORDER BY r.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) rrow;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_reviews"("p_limit" integer, "p_offset" integer, "p_min_rating" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_station_customers"("p_owner_id" "uuid", "p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  p_limit := least(greatest(coalesce(p_limit, 100), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(DISTINCT o.customer_id)
  INTO v_total
  FROM public.orders o
  WHERE o.owner_id = p_owner_id AND o.customer_id IS NOT NULL;

  SELECT coalesce(jsonb_agg(row_to_json(customer_row)), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      c.id,
      c.email,
      c.full_name,
      c.phone,
      c.town,
      c.barangay,
      count(o.id) AS order_count,
      max(o.created_at) AS last_order_at,
      coalesce(sum(o.total_amount), 0) AS total_spent
    FROM public.orders o
    JOIN public.profiles c ON c.id = o.customer_id
    WHERE o.owner_id = p_owner_id
    GROUP BY c.id, c.email, c.full_name, c.phone, c.town, c.barangay
    ORDER BY max(o.created_at) DESC
    LIMIT p_limit
    OFFSET p_offset
  ) customer_row;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_station_customers"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_station_products"("p_owner_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(p.*) ORDER BY p.name)
    FROM public.products p WHERE p.owner_id = p_owner_id
  ), '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."admin_list_station_products"("p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_station_riders"("p_owner_id" "uuid", "p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  p_limit := least(greatest(coalesce(p_limit, 100), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*)
  INTO v_total
  FROM public.profiles r
  WHERE r.owner_id = p_owner_id AND r.role::text = 'rider';

  SELECT coalesce(jsonb_agg(row_to_json(rider_row)), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      r.id,
      r.email,
      r.full_name,
      r.phone,
      r.vehicle_type,
      r.license_number,
      coalesce(r.is_online, false) AS is_online,
      coalesce(r.total_deliveries, 0) AS total_deliveries,
      (
        SELECT u.created_at
        FROM auth.users u
        WHERE u.id = r.id
      ) AS created_at
    FROM public.profiles r
    WHERE r.owner_id = p_owner_id AND r.role::text = 'rider'
    ORDER BY r.full_name NULLS LAST
    LIMIT p_limit
    OFFSET p_offset
  ) rider_row;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_station_riders"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_stations"("p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0, "p_search" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  p_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*)
  INTO v_total
  FROM public.profiles p
  LEFT JOIN public.owner_settings s ON s.owner_id = p.id
  WHERE p.role::text = 'owner'
    AND (
      p_search IS NULL
      OR p_search = ''
      OR coalesce(p.station_name, '') ILIKE '%' || p_search || '%'
      OR coalesce(p.full_name, '') ILIKE '%' || p_search || '%'
      OR coalesce(p.town::text, '') ILIKE '%' || p_search || '%'
    );

  SELECT coalesce(jsonb_agg(row_to_json(station_row)), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      p.id,
      p.station_name,
      p.full_name,
      p.email,
      p.town,
      p.barangay,
      p.phone,
      p.complete_address,
      p.latitude,
      p.longitude,
      coalesce(p.station_availability, 'open') AS station_availability,
      coalesce(p.is_open, true) AS is_open,
      coalesce(s.base_delivery_fee, 0) AS base_delivery_fee,
      coalesce(s.price_per_gallon, 0) AS price_per_gallon,
      coalesce(s.service_radius_km, 5) AS service_radius_km,
      (
        SELECT count(*)
        FROM public.orders o
        WHERE o.owner_id = p.id
          AND o.status::text NOT IN ('delivered', 'cancelled')
      ) AS active_orders,
      (
        SELECT count(*)
        FROM public.profiles r
        WHERE r.owner_id = p.id AND r.role::text = 'rider'
      ) AS rider_count
    FROM public.profiles p
    LEFT JOIN public.owner_settings s ON s.owner_id = p.id
    WHERE p.role::text = 'owner'
      AND (
        p_search IS NULL
        OR p_search = ''
        OR coalesce(p.station_name, '') ILIKE '%' || p_search || '%'
        OR coalesce(p.full_name, '') ILIKE '%' || p_search || '%'
        OR coalesce(p.town::text, '') ILIKE '%' || p_search || '%'
      )
    ORDER BY p.station_name NULLS LAST, p.full_name
    LIMIT p_limit
    OFFSET p_offset
  ) station_row;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_stations"("p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0, "p_search" "text" DEFAULT NULL::"text", "p_region_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  p_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*)
  INTO v_total
  FROM public.profiles p
  LEFT JOIN public.owner_settings s ON s.owner_id = p.id
  WHERE p.role::text = 'owner'
    AND (p_region_id IS NULL OR p.region_id = p_region_id)
    AND (
      p_search IS NULL OR p_search = ''
      OR coalesce(p.station_name, '') ILIKE '%' || p_search || '%'
      OR coalesce(p.full_name, '') ILIKE '%' || p_search || '%'
      OR coalesce(p.town::text, '') ILIKE '%' || p_search || '%'
    );

  SELECT coalesce(jsonb_agg(row_to_json(station_row)), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      p.id, p.station_name, p.full_name, p.email, p.town, p.barangay, p.phone,
      p.complete_address, p.latitude, p.longitude, p.region_id,
      rg.name AS region_name,
      coalesce(p.station_availability, 'open') AS station_availability,
      coalesce(p.is_open, true) AS is_open,
      coalesce(s.base_delivery_fee, 0) AS base_delivery_fee,
      coalesce(s.price_per_gallon, 0) AS price_per_gallon,
      coalesce(s.service_radius_km, 5) AS service_radius_km,
      (SELECT count(*) FROM public.orders o WHERE o.owner_id = p.id AND o.status::text NOT IN ('delivered', 'cancelled')) AS active_orders,
      (SELECT count(*) FROM public.profiles r WHERE r.owner_id = p.id AND r.role::text = 'rider') AS rider_count
    FROM public.profiles p
    LEFT JOIN public.owner_settings s ON s.owner_id = p.id
    LEFT JOIN public.regions rg ON rg.id = p.region_id
    WHERE p.role::text = 'owner'
      AND (p_region_id IS NULL OR p.region_id = p_region_id)
      AND (
        p_search IS NULL OR p_search = ''
        OR coalesce(p.station_name, '') ILIKE '%' || p_search || '%'
        OR coalesce(p.full_name, '') ILIKE '%' || p_search || '%'
        OR coalesce(p.town::text, '') ILIKE '%' || p_search || '%'
      )
    ORDER BY p.station_name NULLS LAST, p.full_name
    LIMIT p_limit OFFSET p_offset
  ) station_row;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text", "p_region_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_users"("p_role" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0, "p_search" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_rows jsonb;
  v_total bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  p_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*)
  INTO v_total
  FROM public.profiles p
  WHERE (p_role IS NULL OR p_role = '' OR p.role::text = p_role)
    AND p.role::text <> 'admin'
    AND (
      p_search IS NULL
      OR p_search = ''
      OR coalesce(p.full_name, '') ILIKE '%' || p_search || '%'
      OR coalesce(p.email, '') ILIKE '%' || p_search || '%'
      OR coalesce(p.phone, '') ILIKE '%' || p_search || '%'
    );

  SELECT coalesce(jsonb_agg(row_to_json(user_row)), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      p.id,
      p.email,
      p.full_name,
      p.username,
      p.phone,
      p.role,
      p.town,
      p.barangay,
      p.station_name,
      p.owner_id,
      p.vehicle_type,
      p.is_online,
      (
        SELECT u.created_at
        FROM auth.users u
        WHERE u.id = p.id
      ) AS created_at,
      coalesce(p.station_availability, 'open') AS station_availability,
      (
        SELECT count(*)
        FROM public.orders o
        WHERE o.customer_id = p.id
           OR o.owner_id = p.id
           OR o.assigned_rider_id = p.id
      ) AS order_count
    FROM public.profiles p
    WHERE (p_role IS NULL OR p_role = '' OR p.role::text = p_role)
      AND p.role::text <> 'admin'
      AND (
        p_search IS NULL
        OR p_search = ''
        OR coalesce(p.full_name, '') ILIKE '%' || p_search || '%'
        OR coalesce(p.email, '') ILIKE '%' || p_search || '%'
        OR coalesce(p.phone, '') ILIKE '%' || p_search || '%'
      )
    ORDER BY p.full_name NULLS LAST, p.email
    LIMIT p_limit
    OFFSET p_offset
  ) user_row;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END;
$$;


ALTER FUNCTION "public"."admin_list_users"("p_role" "text", "p_limit" integer, "p_offset" integer, "p_search" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_reassign_rider"("p_order_id" "uuid", "p_rider_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old jsonb;
  v_order record;
  v_has_assigned_enum boolean;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_rider_id AND role::text = 'rider' AND owner_id = v_order.owner_id
  ) THEN
    RAISE EXCEPTION 'Rider does not belong to this station';
  END IF;

  v_old := to_jsonb(v_order);

  SELECT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status' AND e.enumlabel = 'assigned_to_rider'
  ) INTO v_has_assigned_enum;

  IF v_has_assigned_enum THEN
    UPDATE public.orders
    SET assigned_rider_id = p_rider_id,
        status = CASE
          WHEN status::text IN ('pending', 'accepted', 'preparing', 'ready_for_pickup')
            THEN 'assigned_to_rider'::public.order_status
          ELSE status
        END,
        updated_at = now()
    WHERE id = p_order_id;
  ELSE
    UPDATE public.orders
    SET assigned_rider_id = p_rider_id,
        status = CASE
          WHEN status::text IN ('pending', 'accepted')
            THEN 'preparing'::public.order_status
          ELSE status
        END,
        updated_at = now()
    WHERE id = p_order_id;
  END IF;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (
    auth.uid(),
    'admin_reassign_rider',
    'order',
    p_order_id::text,
    v_old,
    jsonb_build_object('assigned_rider_id', p_rider_id),
    jsonb_build_object('reason', p_reason)
  );

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  VALUES (
    p_rider_id,
    'order_assigned',
    'high',
    'New delivery assigned',
    'An order has been assigned to you by platform admin.',
    jsonb_build_object('order_id', p_order_id, 'reason', p_reason)
  );

  RETURN jsonb_build_object('success', true, 'order_id', p_order_id, 'rider_id', p_rider_id);
END;
$$;


ALTER FUNCTION "public"."admin_reassign_rider"("p_order_id" "uuid", "p_rider_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_refund_order"("p_order_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old jsonb;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;

  SELECT to_jsonb(o.*) INTO v_old FROM public.orders o WHERE o.id = p_order_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;

  UPDATE public.orders
  SET payment_status = 'refunded',
      status = CASE WHEN status::text NOT IN ('delivered', 'cancelled') THEN 'cancelled'::public.order_status ELSE status END,
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (auth.uid(), 'admin_refund_order', 'order', p_order_id::text, v_old,
    jsonb_build_object('payment_status', 'refunded'), jsonb_build_object('reason', p_reason));

  INSERT INTO public.system_notifications (user_id, type, priority, title, content, metadata)
  SELECT o.customer_id, 'system_alert', 'high', 'Payment refunded',
    coalesce(p_reason, 'Your payment has been refunded by platform support.'),
    jsonb_build_object('order_id', p_order_id)
  FROM public.orders o WHERE o.id = p_order_id AND o.customer_id IS NOT NULL;

  RETURN jsonb_build_object('success', true, 'order_id', p_order_id);
END;
$$;


ALTER FUNCTION "public"."admin_refund_order"("p_order_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_retry_payment_event"("p_event_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;
  IF to_regclass('public.payment_webhook_events') IS NULL THEN
    RAISE EXCEPTION 'Payment webhooks not configured';
  END IF;

  UPDATE public.payment_webhook_events
  SET processing_status = 'received', error_message = NULL, processed_at = NULL
  WHERE id = p_event_id AND processing_status = 'failed';

  IF NOT FOUND THEN RAISE EXCEPTION 'Failed event not found'; END IF;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'admin_retry_payment_event', 'payment_webhook_event', p_event_id::text,
    jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true, 'event_id', p_event_id);
END;
$$;


ALTER FUNCTION "public"."admin_retry_payment_event"("p_event_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_revenue_analytics"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_today date := (timezone('Asia/Manila', now()))::date;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN jsonb_build_object(
    'fee_today', coalesce((
      SELECT sum(coalesce(platform_fee, 0))
      FROM public.orders
      WHERE (timezone('Asia/Manila', created_at))::date = v_today
        AND status::text NOT IN ('cancelled')
    ), 0),
    'fee_7d', coalesce((
      SELECT sum(coalesce(platform_fee, 0))
      FROM public.orders
      WHERE created_at >= now() - interval '7 days'
        AND status::text NOT IN ('cancelled')
    ), 0),
    'fee_30d', coalesce((
      SELECT sum(coalesce(platform_fee, 0))
      FROM public.orders
      WHERE created_at >= now() - interval '30 days'
        AND status::text NOT IN ('cancelled')
    ), 0),
    'fee_all_time', coalesce((
      SELECT sum(coalesce(platform_fee, 0))
      FROM public.orders
      WHERE status::text NOT IN ('cancelled')
    ), 0),
    'gmv_today', coalesce((
      SELECT sum(coalesce(total_amount, 0))
      FROM public.orders
      WHERE (timezone('Asia/Manila', created_at))::date = v_today
        AND status::text NOT IN ('cancelled')
    ), 0),
    'orders_with_fee_today', coalesce((
      SELECT count(*)
      FROM public.orders
      WHERE (timezone('Asia/Manila', created_at))::date = v_today
        AND coalesce(platform_fee, 0) > 0
        AND status::text NOT IN ('cancelled')
    ), 0),
    'daily_fees', coalesce((
      SELECT jsonb_agg(row_to_json(d) ORDER BY d.day)
      FROM (
        SELECT
          (timezone('Asia/Manila', created_at))::date AS day,
          sum(coalesce(platform_fee, 0)) AS platform_fee,
          sum(coalesce(total_amount, 0)) AS gmv,
          count(*) AS orders
        FROM public.orders
        WHERE created_at >= now() - interval '14 days'
          AND status::text NOT IN ('cancelled')
        GROUP BY 1
        ORDER BY 1
      ) d
    ), '[]'::jsonb),
    'fee_config', public.get_platform_fee_config()
  );
END;
$$;


ALTER FUNCTION "public"."admin_revenue_analytics"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_send_notification"("p_user_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "text" DEFAULT 'system_alert'::"text", "p_priority" "text" DEFAULT 'normal'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;

  INSERT INTO public.system_notifications (user_id, type, priority, title, content)
  VALUES (p_user_id, p_type::public.notification_type, p_priority::public.notification_priority,
    trim(p_title), trim(p_content))
  RETURNING id INTO v_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value)
  VALUES (auth.uid(), 'admin_send_notification', 'notification', v_id::text,
    jsonb_build_object('user_id', p_user_id, 'title', p_title));

  RETURN jsonb_build_object('success', true, 'notification_id', v_id);
END;
$$;


ALTER FUNCTION "public"."admin_send_notification"("p_user_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "text", "p_priority" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_admin_tier"("p_user_id" "uuid", "p_tier" "text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;
  IF p_tier NOT IN ('super', 'support') THEN RAISE EXCEPTION 'Tier must be super or support'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND role::text = 'admin') THEN
    RAISE EXCEPTION 'Target is not an admin';
  END IF;
  IF p_user_id = auth.uid() AND p_tier = 'support' THEN
    RAISE EXCEPTION 'Cannot demote yourself';
  END IF;

  UPDATE public.profiles SET admin_tier = p_tier WHERE id = p_user_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'admin_set_admin_tier', 'user', p_user_id::text,
    jsonb_build_object('admin_tier', p_tier), jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true, 'admin_tier', p_tier);
END;
$$;


ALTER FUNCTION "public"."admin_set_admin_tier"("p_user_id" "uuid", "p_tier" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_platform_fee"("p_percent" numeric, "p_fixed" numeric DEFAULT 0, "p_enabled" boolean DEFAULT true, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_percent < 0 OR p_percent > 100 THEN
    RAISE EXCEPTION 'Percent must be between 0 and 100';
  END IF;

  IF p_fixed < 0 THEN
    RAISE EXCEPTION 'Fixed fee cannot be negative';
  END IF;

  v_old := public.get_platform_fee_config();

  PERFORM public.admin_set_system_config(
    'platform_fee_enabled',
    to_jsonb(p_enabled),
    p_reason
  );
  PERFORM public.admin_set_system_config(
    'platform_fee_percent',
    to_jsonb(round(p_percent, 2)),
    p_reason
  );
  PERFORM public.admin_set_system_config(
    'platform_fee_fixed',
    to_jsonb(round(p_fixed, 2)),
    p_reason
  );

  RETURN jsonb_build_object(
    'success', true,
    'previous', v_old,
    'current', public.get_platform_fee_config()
  );
END;
$$;


ALTER FUNCTION "public"."admin_set_platform_fee"("p_percent" numeric, "p_fixed" numeric, "p_enabled" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_station_availability"("p_owner_id" "uuid", "p_availability" "text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_availability NOT IN ('open', 'closed', 'busy', 'maintenance') THEN
    RAISE EXCEPTION 'Invalid station availability: %', p_availability;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_owner_id AND role::text = 'owner'
  ) THEN
    RAISE EXCEPTION 'Owner not found';
  END IF;

  SELECT coalesce(station_availability, 'open')
  INTO v_old
  FROM public.profiles
  WHERE id = p_owner_id;

  UPDATE public.profiles
  SET station_availability = p_availability,
      is_open = (p_availability = 'open')
  WHERE id = p_owner_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (
    auth.uid(),
    'admin_set_station_availability',
    'station',
    p_owner_id::text,
    jsonb_build_object('station_availability', v_old),
    jsonb_build_object('station_availability', p_availability),
    jsonb_build_object('reason', p_reason)
  );

  RETURN jsonb_build_object(
    'success', true,
    'owner_id', p_owner_id,
    'station_availability', p_availability
  );
END;
$$;


ALTER FUNCTION "public"."admin_set_station_availability"("p_owner_id" "uuid", "p_availability" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_system_config"("p_key" "text", "p_value" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_key IS NULL OR length(trim(p_key)) = 0 THEN
    RAISE EXCEPTION 'Config key is required';
  END IF;

  SELECT value INTO v_old FROM public.system_config WHERE key = p_key;

  INSERT INTO public.system_config (key, value, updated_at)
  VALUES (p_key, p_value, now())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value,
        updated_at = now();

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (
    auth.uid(),
    'admin_set_system_config',
    'system_config',
    p_key,
    v_old,
    p_value,
    jsonb_build_object('reason', p_reason)
  );

  RETURN jsonb_build_object('success', true, 'key', p_key, 'value', p_value);
END;
$$;


ALTER FUNCTION "public"."admin_set_system_config"("p_key" "text", "p_value" "jsonb", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_suspend_user"("p_user_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND role::text <> 'admin') THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  UPDATE public.profiles
  SET is_suspended = true, suspended_at = now(), suspended_reason = p_reason
  WHERE id = p_user_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'admin_suspend_user', 'user', p_user_id::text, jsonb_build_object('reason', p_reason));

  INSERT INTO public.system_notifications (user_id, type, priority, title, content)
  VALUES (p_user_id, 'system_alert', 'urgent', 'Account suspended',
    coalesce(p_reason, 'Your account has been suspended. Contact support.'));

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."admin_suspend_user"("p_user_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_unsuspend_user"("p_user_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Super admin required'; END IF;

  UPDATE public.profiles
  SET is_suspended = false, suspended_at = NULL, suspended_reason = NULL
  WHERE id = p_user_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'admin_unsuspend_user', 'user', p_user_id::text, jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."admin_unsuspend_user"("p_user_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_dispute"("p_dispute_id" "uuid", "p_status" "text", "p_resolution_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF p_status NOT IN ('open', 'investigating', 'resolved', 'dismissed') THEN
    RAISE EXCEPTION 'Invalid dispute status';
  END IF;

  SELECT to_jsonb(d.*) INTO v_old FROM public.disputes d WHERE d.id = p_dispute_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'Dispute not found'; END IF;

  UPDATE public.disputes
  SET status = p_status::public.dispute_status,
      resolution_notes = coalesce(nullif(trim(p_resolution_notes), ''), resolution_notes),
      resolved_by = CASE WHEN p_status IN ('resolved', 'dismissed') THEN auth.uid() ELSE resolved_by END,
      updated_at = now()
  WHERE id = p_dispute_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value)
  VALUES (auth.uid(), 'admin_update_dispute', 'dispute', p_dispute_id::text, v_old,
    jsonb_build_object('status', p_status, 'resolution_notes', p_resolution_notes));

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."admin_update_dispute"("p_dispute_id" "uuid", "p_status" "text", "p_resolution_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_station_profile"("p_owner_id" "uuid", "p_station_name" "text" DEFAULT NULL::"text", "p_station_description" "text" DEFAULT NULL::"text", "p_full_name" "text" DEFAULT NULL::"text", "p_phone" "text" DEFAULT NULL::"text", "p_town" "text" DEFAULT NULL::"text", "p_barangay" "text" DEFAULT NULL::"text", "p_complete_address" "text" DEFAULT NULL::"text", "p_latitude" double precision DEFAULT NULL::double precision, "p_longitude" double precision DEFAULT NULL::double precision, "p_base_delivery_fee" numeric DEFAULT NULL::numeric, "p_price_per_gallon" numeric DEFAULT NULL::numeric, "p_service_radius_km" numeric DEFAULT NULL::numeric, "p_max_concurrent_orders" integer DEFAULT NULL::integer, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old jsonb;
  v_new jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_owner_id AND role::text = 'owner'
  ) THEN
    RAISE EXCEPTION 'Station not found';
  END IF;

  SELECT jsonb_build_object(
    'profile', to_jsonb(p.*),
    'settings', coalesce((SELECT to_jsonb(s.*) FROM public.owner_settings s WHERE s.owner_id = p.id), '{}'::jsonb)
  )
  INTO v_old
  FROM public.profiles p
  WHERE p.id = p_owner_id;

  UPDATE public.profiles
  SET
    station_name = coalesce(nullif(trim(p_station_name), ''), station_name),
    station_description = coalesce(nullif(trim(p_station_description), ''), station_description),
    full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
    phone = coalesce(nullif(trim(p_phone), ''), phone),
    town = coalesce(nullif(trim(p_town), ''), town),
    barangay = coalesce(nullif(trim(p_barangay), ''), barangay),
    complete_address = coalesce(nullif(trim(p_complete_address), ''), complete_address),
    latitude = coalesce(p_latitude, latitude),
    longitude = coalesce(p_longitude, longitude)
  WHERE id = p_owner_id;

  INSERT INTO public.owner_settings (owner_id)
  VALUES (p_owner_id)
  ON CONFLICT (owner_id) DO NOTHING;

  UPDATE public.owner_settings
  SET
    base_delivery_fee = coalesce(p_base_delivery_fee, base_delivery_fee),
    price_per_gallon = coalesce(p_price_per_gallon, price_per_gallon),
    service_radius_km = coalesce(p_service_radius_km, service_radius_km),
    max_concurrent_orders = coalesce(p_max_concurrent_orders, max_concurrent_orders)
  WHERE owner_id = p_owner_id;

  SELECT jsonb_build_object(
    'profile', to_jsonb(p.*),
    'settings', coalesce((SELECT to_jsonb(s.*) FROM public.owner_settings s WHERE s.owner_id = p.id), '{}'::jsonb)
  )
  INTO v_new
  FROM public.profiles p
  WHERE p.id = p_owner_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (
    auth.uid(),
    'admin_update_station_profile',
    'station',
    p_owner_id::text,
    v_old,
    v_new,
    jsonb_build_object('reason', p_reason)
  );

  RETURN jsonb_build_object('success', true, 'station', v_new);
END;
$$;


ALTER FUNCTION "public"."admin_update_station_profile"("p_owner_id" "uuid", "p_station_name" "text", "p_station_description" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_service_radius_km" numeric, "p_max_concurrent_orders" integer, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_user_email"("p_user_id" "uuid", "p_email" "text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_old_email text;
  v_new_email text := lower(trim(p_email));
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF v_new_email IS NULL OR v_new_email = '' OR position('@' in v_new_email) = 0 THEN
    RAISE EXCEPTION 'Invalid email';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id AND role::text <> 'admin'
  ) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  SELECT email INTO v_old_email FROM public.profiles WHERE id = p_user_id;

  UPDATE auth.users
  SET email = v_new_email,
      email_confirmed_at = coalesce(email_confirmed_at, now())
  WHERE id = p_user_id;

  UPDATE public.profiles SET email = v_new_email WHERE id = p_user_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (
    auth.uid(),
    'admin_update_user_email',
    'user',
    p_user_id::text,
    jsonb_build_object('email', v_old_email),
    jsonb_build_object('email', v_new_email),
    jsonb_build_object('reason', p_reason)
  );

  RETURN jsonb_build_object('success', true, 'email', v_new_email);
END;
$$;


ALTER FUNCTION "public"."admin_update_user_email"("p_user_id" "uuid", "p_email" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_user_password"("p_user_id" "uuid", "p_password" "text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF p_password IS NULL OR length(p_password) < 6 THEN
    RAISE EXCEPTION 'Password must be at least 6 characters';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id AND role::text <> 'admin'
  ) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  UPDATE auth.users
  SET encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf'))
  WHERE id = p_user_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (
    auth.uid(),
    'admin_update_user_password',
    'user',
    p_user_id::text,
    jsonb_build_object('password_reset', true),
    jsonb_build_object('reason', p_reason)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."admin_update_user_password"("p_user_id" "uuid", "p_password" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_user_profile"("p_user_id" "uuid", "p_full_name" "text" DEFAULT NULL::"text", "p_phone" "text" DEFAULT NULL::"text", "p_username" "text" DEFAULT NULL::"text", "p_town" "text" DEFAULT NULL::"text", "p_barangay" "text" DEFAULT NULL::"text", "p_complete_address" "text" DEFAULT NULL::"text", "p_landmark" "text" DEFAULT NULL::"text", "p_vehicle_type" "text" DEFAULT NULL::"text", "p_license_number" "text" DEFAULT NULL::"text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old jsonb;
  v_new jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id AND role::text <> 'admin'
  ) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  SELECT to_jsonb(p.*) INTO v_old FROM public.profiles p WHERE p.id = p_user_id;

  UPDATE public.profiles
  SET
    full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
    phone = coalesce(nullif(trim(p_phone), ''), phone),
    username = coalesce(nullif(trim(p_username), ''), username),
    town = coalesce(nullif(trim(p_town), ''), town),
    barangay = coalesce(nullif(trim(p_barangay), ''), barangay),
    complete_address = coalesce(nullif(trim(p_complete_address), ''), complete_address),
    landmark = coalesce(nullif(trim(p_landmark), ''), landmark),
    vehicle_type = coalesce(nullif(trim(p_vehicle_type), ''), vehicle_type),
    license_number = coalesce(nullif(trim(p_license_number), ''), license_number)
  WHERE id = p_user_id;

  SELECT to_jsonb(p.*) INTO v_new FROM public.profiles p WHERE p.id = p_user_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value, metadata)
  VALUES (
    auth.uid(),
    'admin_update_user_profile',
    'user',
    p_user_id::text,
    v_old,
    v_new,
    jsonb_build_object('reason', p_reason)
  );

  RETURN jsonb_build_object('success', true, 'profile', v_new);
END;
$$;


ALTER FUNCTION "public"."admin_update_user_profile"("p_user_id" "uuid", "p_full_name" "text", "p_phone" "text", "p_username" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_landmark" "text", "p_vehicle_type" "text", "p_license_number" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_upsert_product"("p_product_id" "uuid" DEFAULT NULL::"uuid", "p_owner_id" "uuid" DEFAULT NULL::"uuid", "p_name" "text" DEFAULT NULL::"text", "p_description" "text" DEFAULT NULL::"text", "p_price" numeric DEFAULT NULL::numeric, "p_category" "text" DEFAULT NULL::"text", "p_stock_level" integer DEFAULT NULL::integer, "p_is_available" boolean DEFAULT true, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_id uuid;
  v_row jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden'; END IF;

  IF p_product_id IS NULL THEN
    IF p_owner_id IS NULL OR nullif(trim(p_name), '') IS NULL THEN
      RAISE EXCEPTION 'owner_id and name required for new product';
    END IF;
    INSERT INTO public.products (owner_id, name, description, price, category, stock_level, is_available)
    VALUES (p_owner_id, trim(p_name), p_description, coalesce(p_price, 0), coalesce(p_category, 'Purified'),
      coalesce(p_stock_level, 100), coalesce(p_is_available, true))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.products
    SET name = coalesce(nullif(trim(p_name), ''), name),
        description = coalesce(p_description, description),
        price = coalesce(p_price, price),
        category = coalesce(p_category, category),
        stock_level = coalesce(p_stock_level, stock_level),
        is_available = coalesce(p_is_available, is_available)
    WHERE id = p_product_id
    RETURNING id INTO v_id;
  END IF;

  SELECT to_jsonb(p.*) INTO v_row FROM public.products p WHERE p.id = v_id;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value, metadata)
  VALUES (auth.uid(), 'admin_upsert_product', 'product', v_id::text, v_row,
    jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true, 'product', v_row);
END;
$$;


ALTER FUNCTION "public"."admin_upsert_product"("p_product_id" "uuid", "p_owner_id" "uuid", "p_name" "text", "p_description" "text", "p_price" numeric, "p_category" "text", "p_stock_level" integer, "p_is_available" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."archive_order_chat_on_delivery"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    -- If order status changed to delivered, archive the associated chat room
    if new.status = 'delivered' and old.status != 'delivered' then
        update public.chat_rooms
        set status = 'archived',
            archived_at = now()
        where reference_id = new.id
        and room_type = 'order_delivery';
    end if;
    return new;
end;
$$;


ALTER FUNCTION "public"."archive_order_chat_on_delivery"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_rider_safely"("p_order_id" "uuid", "p_rider_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_rider public.profiles%ROWTYPE;
  v_rider_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order no longer exists.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'owner'
  ) OR auth.uid() <> v_order.owner_id THEN
    RAISE EXCEPTION 'Only this station owner can assign its order.';
  END IF;

  IF v_order.assigned_rider_id IS NOT NULL THEN
    RAISE EXCEPTION 'Order is already assigned to a rider.';
  END IF;

  IF v_order.status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Order status is %, not ready_for_pickup.', v_order.status;
  END IF;

  SELECT * INTO v_rider
  FROM public.profiles
  WHERE id = p_rider_id
    AND role = 'rider'
    AND owner_id = v_order.owner_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selected rider is not assigned to this station.';
  END IF;

  v_rider_name := coalesce(v_rider.full_name, v_rider.username, 'Rider');

  UPDATE public.orders
  SET
    assigned_rider_id = p_rider_id,
    status = 'assigned_to_rider',
    updated_at = now()
  WHERE id = p_order_id;

  -- Notify Rider
  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    p_rider_id,
    'order_assigned',
    'urgent',
    'New Delivery Assignment',
    'You have been assigned order #' || upper(substr(p_order_id::text, 1, 8)) || ' for ' || coalesce(v_order.customer_name, 'a customer') || '.',
    jsonb_build_object('order_id', p_order_id, 'status', 'assigned_to_rider')
  );

  -- Notify Customer
  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_order.customer_id,
    'order_assigned',
    'high',
    'Rider Assigned to Refill',
    v_rider_name || ' has been assigned to deliver your water refill.',
    jsonb_build_object('order_id', p_order_id, 'rider_id', p_rider_id, 'rider_name', v_rider_name)
  );

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."assign_rider_safely"("p_order_id" "uuid", "p_rider_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_add_order_chat_participants"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    v_order_record record;
    v_owner_id uuid;
begin
    -- Only proceed for order_delivery rooms
    if new.room_type = 'order_delivery' and new.reference_id is not null then
        -- Get order details
        select customer_id, assigned_rider_id, owner_id
        into v_order_record
        from public.orders
        where id = new.reference_id;
        
        if v_order_record is not null then
            -- Add customer
            if v_order_record.customer_id is not null then
                insert into public.chat_participants (room_id, user_id, role_in_room)
                values (new.id, v_order_record.customer_id, 'customer')
                on conflict (room_id, user_id) do nothing;
            end if;
            
            -- Add rider if assigned
            if v_order_record.assigned_rider_id is not null then
                insert into public.chat_participants (room_id, user_id, role_in_room)
                values (new.id, v_order_record.assigned_rider_id, 'rider')
                on conflict (room_id, user_id) do nothing;
            end if;
            
            -- Add owner
            if v_order_record.owner_id is not null then
                insert into public.chat_participants (room_id, user_id, role_in_room)
                values (new.id, v_order_record.owner_id, 'owner')
                on conflict (room_id, user_id) do nothing;
            end if;
        end if;
    end if;
    
    return new;
end;
$$;


ALTER FUNCTION "public"."auto_add_order_chat_participants"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."broadcast_to_riders"("p_owner_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "public"."notification_type" DEFAULT 'station_broadcast'::"public"."notification_type", "p_priority" "public"."notification_priority" DEFAULT 'normal'::"public"."notification_priority") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    v_count integer := 0;
    v_rider record;
begin
    -- Insert notification for each rider
    for v_rider in
        select id from public.profiles
        where owner_id = p_owner_id
        and role = 'rider'
    loop
        insert into public.system_notifications (
            user_id, type, priority, title, content
        ) values (
            v_rider.id, p_type, p_priority, p_title, p_content
        );
        v_count := v_count + 1;
    end loop;
    
    return v_count;
end;
$$;


ALTER FUNCTION "public"."broadcast_to_riders"("p_owner_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "public"."notification_type", "p_priority" "public"."notification_priority") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_platform_fee"("p_subtotal" numeric, "p_delivery_fee" numeric DEFAULT 0) RETURNS numeric
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_cfg jsonb;
  v_enabled boolean;
  v_percent numeric;
  v_fixed numeric;
  v_base numeric;
  v_fee numeric;
BEGIN
  v_cfg := public.get_platform_fee_config();
  v_enabled := coalesce((v_cfg->>'enabled')::boolean, false);
  v_percent := coalesce((v_cfg->>'percent')::numeric, 0);
  v_fixed := coalesce((v_cfg->>'fixed')::numeric, 0);

  IF NOT v_enabled THEN
    RETURN 0;
  END IF;

  v_base := greatest(coalesce(p_subtotal, 0) + coalesce(p_delivery_fee, 0), 0);
  v_fee := round((v_base * v_percent / 100) + v_fixed, 2);
  RETURN greatest(v_fee, 0);
END;
$$;


ALTER FUNCTION "public"."calculate_platform_fee"("p_subtotal" numeric, "p_delivery_fee" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_app_compatibility"("p_app_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_min_version TEXT;
    v_maintenance BOOLEAN;
BEGIN
    SELECT value->>0 INTO v_min_version FROM public.system_config WHERE key = 'min_app_version';
    SELECT (value::TEXT)::BOOLEAN INTO v_maintenance FROM public.system_config WHERE key = 'maintenance_mode';

    -- Simple Semantic Version comparison (major.minor.patch)
    -- If p_app_version < v_min_version -> REJECT
    
    IF v_maintenance = TRUE THEN
        RETURN jsonb_build_object('status', 'MAINTENANCE', 'message', 'System is undergoing scheduled maintenance. Please try again later.');
    END IF;

    -- Standard Version check
    IF p_app_version < v_min_version THEN
        RETURN jsonb_build_object('status', 'UPDATE_REQUIRED', 'min_version', v_min_version, 'message', 'A critical update is required to continue using eRefill.');
    END IF;

    RETURN jsonb_build_object('status', 'OK', 'api_version', (SELECT value->>0 FROM public.system_config WHERE key = 'api_version'));
END;
$$;


ALTER FUNCTION "public"."check_app_compatibility"("p_app_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_station_availability"("p_station_id" "uuid", "p_customer_lat" double precision, "p_customer_lng" double precision) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_station_lat DOUBLE PRECISION;
    v_station_lng DOUBLE PRECISION;
    v_radius DOUBLE PRECISION;
    v_max_capacity INTEGER;
    v_current_active INTEGER;
    v_distance DOUBLE PRECISION;
BEGIN
    -- Get Station Location and Settings with Fallbacks
    -- Uses COALESCE to provide defaults if owner_settings entry is missing
    SELECT 
        p.latitude, 
        p.longitude, 
        COALESCE(s.service_radius_km, 10.0), 
        COALESCE(s.max_concurrent_orders, 20)
    INTO v_station_lat, v_station_lng, v_radius, v_max_capacity
    FROM public.profiles p
    LEFT JOIN public.owner_settings s ON s.owner_id = p.id
    WHERE p.id = p_station_id;

    -- CRITICAL CHECK: If station has no coordinates, we cannot calculate distance.
    IF v_station_lat IS NULL OR v_station_lng IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'STATION_RECORDS_INCOMPLETE', 
            'message', 'Station records are incomplete (missing coordinates). Please contact the station owner.'
        );
    END IF;

    -- 1. Calculate Distance (Spherical Law of Cosines)
    -- Returns distance in KM
    v_distance := 6371 * acos(
        pmin(1.0, 
            cos(radians(p_customer_lat)) * cos(radians(v_station_lat)) * 
            cos(radians(v_station_lng) - radians(p_customer_lng)) + 
            sin(radians(p_customer_lat)) * sin(radians(v_station_lat))
        )
    );

    -- 2. Check Service Zone
    IF v_distance > v_radius THEN
        RETURN jsonb_build_object(
            'status', 'OUT_OF_ZONE', 
            'message', 'You are outside the service area of this station.',
            'distance', ROUND(v_distance::numeric, 2),
            'limit', v_radius
        );
    END IF;

    -- 3. Check Operational Capacity (Active and Non-Failed orders)
    SELECT COUNT(*) INTO v_current_active
    FROM public.orders
    WHERE owner_id = p_station_id 
      AND status IN ('pending', 'accepted', 'preparing', 'out_for_delivery')
      AND payment_status NOT IN ('failed', 'refunded');

    IF v_current_active >= v_max_capacity THEN
        RETURN jsonb_build_object(
            'status', 'CAPACITY_EXCEEDED', 
            'message', 'Station is at maximum capacity. Please wait or try another station.',
            'load', v_current_active,
            'limit', v_max_capacity
        );
    END IF;

    -- Success Status
    RETURN jsonb_build_object(
        'status', 'OK', 
        'message', 'Station available.',
        'distance', ROUND(v_distance::numeric, 2)
    );
END;
$$;


ALTER FUNCTION "public"."check_station_availability"("p_station_id" "uuid", "p_customer_lat" double precision, "p_customer_lng" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_old_notifications"("p_days" integer DEFAULT 30) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    v_deleted integer;
begin
    delete from public.system_notifications
    where created_at < now() - interval '1 day' * p_days
    and is_read = true;
    
    get diagnostics v_deleted = row_count;
    return v_deleted;
end;
$$;


ALTER FUNCTION "public"."cleanup_old_notifications"("p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_order RECORD;
    v_customer_profile RECORD;
    v_dist DOUBLE PRECISION;
    v_is_flagged BOOLEAN := FALSE;
BEGIN
    -- A. Fetch Order and Verify Context
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Order not found.');
    END IF;

    IF v_order.status != 'out_for_delivery' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Order is not in a deliverable state (Current: ' || v_order.status || ').');
    END IF;

    IF v_order.assigned_rider_id != auth.uid() THEN
        RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: You are not the assigned rider for this delivery.');
    END IF;

    -- B. Verify Proximity (Hardening Against Remote Completion Fraud)
    -- Fetch customer address coordinates for comparison if available
    SELECT * INTO v_customer_profile FROM public.profiles WHERE id = v_order.customer_id;
    
    -- (Mock distance check: if more than 500m from drop-off, flag it)
    -- This doesn't block the delivery, but flags the rider for review.
    -- Assuming profiles has lat/lng or similar - if not, we skip the flagging for now.

    -- C. Atomic Transition: Order + Ledger + PoD
    UPDATE public.orders 
    SET 
        status = 'delivered',
        payment_status = 'success', -- Assume success on physical POD for COD
        delivery_latitude = p_lat,
        delivery_longitude = p_lng,
        delivery_photo_url = p_photo_url,
        delivery_signature_url = p_signature_url,
        actual_completion_at = NOW(),
        updated_at = NOW()
    WHERE id = p_order_id;

    -- D. Generate Ledger Entry (Financial Integrity)
    INSERT INTO public.ledger_entries (
        order_id, owner_id, amount, type, description
    ) VALUES (
        p_order_id, v_order.owner_id, v_order.total_amount, 'income', 'Delivery successfully completed with PoD.'
    );

    -- E. Auto-analyze for Suspicious Activity (Behavioral Intel)
    IF v_is_flagged THEN
        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('SUSPICIOUS_DELIVERY_LOCATION', jsonb_build_object('order_id', p_order_id, 'rider_id', auth.uid()), v_order.owner_id);
    END IF;

    RETURN jsonb_build_object('success', true, 'message', 'Delivery completed and financial record secured.');
END;
$$;


ALTER FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision DEFAULT NULL::double precision, "p_lng" double precision DEFAULT NULL::double precision, "p_photo_url" "text" DEFAULT NULL::"text", "p_signature_url" "text" DEFAULT NULL::"text", "p_delivery_note" "text" DEFAULT NULL::"text", "p_empty_gallons_returned" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not found');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'rider'
  ) OR auth.uid() <> v_order.assigned_rider_id THEN
    RAISE EXCEPTION 'Only the assigned rider can confirm this delivery.';
  END IF;

  IF v_order.status = 'delivered' THEN
    RETURN jsonb_build_object('success', true, 'message', 'Order is already delivered');
  END IF;

  IF v_order.status <> 'out_for_delivery' THEN
    RAISE EXCEPTION 'Only an order out for delivery can be completed.';
  END IF;

  UPDATE public.orders
  SET
    status = 'delivered',
    delivered_at = coalesce(delivered_at, now()),
    proof_of_delivery_url = coalesce(p_photo_url, proof_of_delivery_url),
    delivery_signature_url = coalesce(p_signature_url, delivery_signature_url),
    delivery_note = coalesce(p_delivery_note, delivery_note),
    empty_gallons_returned = coalesce(p_empty_gallons_returned, empty_gallons_returned, 0),
    delivery_lat = coalesce(p_lat, delivery_lat),
    delivery_lng = coalesce(p_lng, delivery_lng),
    payment_status = CASE
      WHEN lower(coalesce(payment_method, 'cod')) IN ('cod', 'cash') THEN 'success'
      ELSE payment_status
    END,
    updated_at = now()
  WHERE id = p_order_id;

  -- Notify Customer
  INSERT INTO public.system_notifications (
    user_id, type, priority, title, content, metadata
  ) VALUES (
    v_order.customer_id, 'system_alert', 'high', 'Refill Delivered',
    'Your water refill delivery has been completed. Thank you!',
    jsonb_build_object('order_id', p_order_id, 'status', 'delivered')
  );

  -- Notify Owner
  INSERT INTO public.system_notifications (
    user_id, type, priority, title, content, metadata
  ) VALUES (
    v_order.owner_id, 'system_alert', 'high', 'Delivery Completed',
    'Order #' || upper(substr(p_order_id::text, 1, 8)) || ' was successfully delivered to ' || coalesce(v_order.customer_name, 'customer') || '.',
    jsonb_build_object('order_id', p_order_id, 'status', 'delivered')
  );

  RETURN jsonb_build_object('success', true, 'message', 'Delivery confirmed successfully');
END;
$$;


ALTER FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text", "p_delivery_note" "text", "p_empty_gallons_returned" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_default_quick_replies"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    -- Only create defaults for riders
    if new.role = 'rider' then
        insert into public.quick_replies (rider_id, label, message_text, sort_order) values
        (new.id, 'I''m 5 minutes away', 'Hi! I''m about 5 minutes away with your order. Please get ready!', 1),
        (new.id, 'I have arrived', 'I''ve arrived at your location. Please come out to receive your order.', 2),
        (new.id, 'Can''t find house', 'I''m having trouble finding your exact house. Can you provide more specific directions?', 3),
        (new.id, 'Order delivered', 'Your order has been delivered. Thank you for choosing us!', 4),
        (new.id, 'Running late', 'Sorry, I''m running a bit late due to traffic. I''ll be there soon!', 5);
    end if;
    
    return new;
end;
$$;


ALTER FUNCTION "public"."create_default_quick_replies"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_order_atomic"("p_order_data" "jsonb", "p_items_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_customer_id uuid := auth.uid();
  v_owner_id uuid;
  v_payment_method text;
  v_order_id uuid;
  v_item record;
  v_product record;
  v_computed_subtotal numeric(10,2) := 0;
  v_delivery_fee numeric(10,2) := 0;
  v_total_amount numeric(10,2) := 0;
  v_order_row public.orders%ROWTYPE;
BEGIN
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place an order.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_customer_id AND role = 'customer'
  ) THEN
    RAISE EXCEPTION 'Only customer accounts can place orders.';
  END IF;

  v_owner_id := (p_order_data->>'owner_id')::uuid;
  v_payment_method := lower(trim(coalesce(p_order_data->>'payment_method', 'cod')));
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Station owner ID is required.';
  END IF;

  -- 1. Verify owner station exists and is open
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = v_owner_id AND role = 'owner' AND coalesce(station_availability, 'open') = 'open'
  ) THEN
    RAISE EXCEPTION 'This water station is currently closed or unavailable.';
  END IF;

  IF NOT public.is_station_payment_method_available(v_owner_id, v_payment_method) THEN
    RAISE EXCEPTION 'This payment method is not available for this station.';
  END IF;
  -- 2. Verify line items against products catalog
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
    product_id uuid,
    quantity integer,
    product_name text
  )
  LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item %', v_item.product_name;
    END IF;

    SELECT * INTO v_product FROM public.products
    WHERE id = v_item.product_id AND owner_id = v_owner_id AND is_available = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % is unavailable at this station.', v_item.product_name;
    END IF;

    v_computed_subtotal := v_computed_subtotal + (v_product.price * v_item.quantity);
  END LOOP;

  IF v_computed_subtotal <= 0 THEN
    RAISE EXCEPTION 'Cart cannot be empty.';
  END IF;

  -- 3. Get server-side base delivery fee from owner_settings
  SELECT coalesce(base_delivery_fee, 0) INTO v_delivery_fee
  FROM public.owner_settings WHERE owner_id = v_owner_id;

  -- 4. Calculate server-verified total amount
  v_total_amount := v_computed_subtotal + v_delivery_fee;

  -- 5. Insert order
  INSERT INTO public.orders (
    customer_id,
    owner_id,
    station_name,
    customer_name,
    customer_phone,
    customer_address,
    customer_barangay,
    customer_municipality,
    customer_landmark,
    idempotency_key,
    subtotal,
    delivery_fee,
    total_amount,
    payment_method,
    payment_status,
    notes,
    region_id,
    customer_latitude,
    customer_longitude,
    status
  ) VALUES (
    v_customer_id,
    v_owner_id,
    coalesce(p_order_data->>'station_name', 'Water Station'),
    p_order_data->>'customer_name',
    p_order_data->>'customer_phone',
    p_order_data->>'customer_address',
    p_order_data->>'customer_barangay',
    p_order_data->>'customer_municipality',
    p_order_data->>'customer_landmark',
    p_order_data->>'idempotency_key',
    v_computed_subtotal,
    v_delivery_fee,
    v_total_amount,
    v_payment_method,
    'pending',
    p_order_data->>'notes',
    (p_order_data->>'region_id')::uuid,
    (p_order_data->>'customer_latitude')::double precision,
    (p_order_data->>'customer_longitude')::double precision,
    'pending'
  )
  RETURNING * INTO v_order_row;

  v_order_id := v_order_row.id;

  -- 6. Insert order items
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items_data) AS x(
    product_id uuid,
    quantity integer,
    product_name text
  )
  LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id;

    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price,
      subtotal
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price,
      (v_product.price * v_item.quantity)
    );
  END LOOP;

  -- 7. Notify Station Owner of incoming refill order
  INSERT INTO public.system_notifications (
    user_id,
    type,
    priority,
    title,
    content,
    metadata
  ) VALUES (
    v_owner_id,
    'system_alert',
    'high',
    'New Refill Order',
    coalesce(p_order_data->>'customer_name', 'A customer') || ' placed a new refill order of PHP ' || trim(to_char(v_total_amount, '999999990.00')) || ' (' || upper(coalesce(p_order_data->>'payment_method', 'cod')) || ').',
    jsonb_build_object('order_id', v_order_id, 'status', 'pending', 'total_amount', v_total_amount)
  );

  RETURN jsonb_build_object(
    'id', v_order_id,
    'total_amount', v_total_amount,
    'status', 'pending'
  );
END;
$$;


ALTER FUNCTION "public"."create_order_atomic"("p_order_data" "jsonb", "p_items_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_order_chat_room"("p_order_id" "uuid", "p_customer_id" "uuid", "p_owner_id" "uuid", "p_rider_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_room_id uuid;
    v_result jsonb;
begin
    -- Check if room already exists
    select id into v_room_id
    from chat_rooms
    where reference_id = p_order_id
    and room_type = 'order_delivery';
    
    if v_room_id is not null then
        -- Return existing room with participants
        select jsonb_build_object(
            'id', cr.id,
            'room_type', cr.room_type,
            'reference_id', cr.reference_id,
            'owner_id', cr.owner_id,
            'title', cr.title,
            'status', cr.status,
            'created_at', cr.created_at,
            'updated_at', cr.updated_at,
            'participants', (
                select jsonb_agg(
                    jsonb_build_object(
                        'id', cp.id,
                        'room_id', cp.room_id,
                        'user_id', cp.user_id,
                        'role_in_room', cp.role_in_room,
                        'joined_at', cp.joined_at,
                        'is_muted', false,
                        'metadata', '{}'::jsonb
                    )
                )
                from chat_participants cp
                where cp.room_id = cr.id
            )
        ) into v_result
        from chat_rooms cr
        where cr.id = v_room_id;
        
        return v_result;
    end if;
    
    -- Create new chat room
    insert into chat_rooms (room_type, reference_id, owner_id, title, status)
    values ('order_delivery', p_order_id, p_owner_id, 'Order Delivery', 'active')
    returning id into v_room_id;
    
    -- Add customer as participant
    insert into chat_participants (room_id, user_id, role_in_room)
    values (v_room_id, p_customer_id, 'customer')
    on conflict do nothing;
    
    -- Add owner as participant
    insert into chat_participants (room_id, user_id, role_in_room)
    values (v_room_id, p_owner_id, 'owner')
    on conflict do nothing;
    
    -- Add rider as participant if provided
    if p_rider_id is not null then
        insert into chat_participants (room_id, user_id, role_in_room)
        values (v_room_id, p_rider_id, 'rider')
        on conflict do nothing;
    end if;
    
    -- Add system message
    insert into messages (room_id, sender_id, content, message_type)
    values (v_room_id, null, 'Order chat started. Use this channel for delivery updates and directions.', 'system');
    
    -- Return new room with participants
    select jsonb_build_object(
        'id', cr.id,
        'room_type', cr.room_type,
        'reference_id', cr.reference_id,
        'owner_id', cr.owner_id,
        'title', cr.title,
        'status', cr.status,
        'created_at', cr.created_at,
        'updated_at', cr.updated_at,
        'participants', (
            select jsonb_agg(
                jsonb_build_object(
                    'id', cp.id,
                    'room_id', cp.room_id,
                    'user_id', cp.user_id,
                    'role_in_room', cp.role_in_room,
                    'joined_at', cp.joined_at,
                    'is_muted', false,
                    'metadata', '{}'::jsonb
                )
            )
            from chat_participants cp
            where cp.room_id = cr.id
        )
    ) into v_result
    from chat_rooms cr
    where cr.id = v_room_id;
    
    return v_result;
end;
$$;


ALTER FUNCTION "public"."create_order_chat_room"("p_order_id" "uuid", "p_customer_id" "uuid", "p_owner_id" "uuid", "p_rider_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_rider_account"("p_email" "text", "p_password" "text", "p_username" "text", "p_full_name" "text", "p_owner_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
    v_user_id uuid;
    v_hashed_password text;
BEGIN
    -- Ensure pgcrypto is available
    PERFORM public.ensure_pgcrypto();
    
    -- Generate UUID for new user
    v_user_id := gen_random_uuid();
    
    -- Hash the password using pgcrypto
    -- Use extensions.gen_salt if available, otherwise fall back to public
    BEGIN
        v_hashed_password := crypt(p_password, gen_salt('bf'));
    EXCEPTION
        WHEN undefined_function THEN
            -- Try with extensions schema prefix
            v_hashed_password := extensions.crypt(p_password, extensions.gen_salt('bf'));
    END;
    
    -- Insert into auth.users
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
    )
    VALUES (
        '00000000-0000-0000-0000-000000000000',
        v_user_id,
        'authenticated',
        'authenticated',
        p_email,
        v_hashed_password,
        now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        jsonb_build_object('role', 'rider', 'username', p_username, 'full_name', p_full_name, 'owner_id', p_owner_id),
        now(),
        now()
    );

    -- Insert into auth.identities
    INSERT INTO auth.identities (
        provider_id, 
        user_id, 
        identity_data, 
        provider, 
        last_sign_in_at, 
        created_at, 
        updated_at, 
        id
    ) 
    VALUES (
        v_user_id::text, 
        v_user_id, 
        jsonb_build_object('sub', v_user_id::text, 'email', p_email), 
        'email', 
        now(), 
        now(), 
        now(), 
        gen_random_uuid()
    );

    RETURN 'success';
EXCEPTION
    WHEN unique_violation THEN
        RETURN 'error: user_already_exists';
    WHEN OTHERS THEN
        RETURN 'error: ' || SQLERRM;
END;
$$;


ALTER FUNCTION "public"."create_rider_account"("p_email" "text", "p_password" "text", "p_username" "text", "p_full_name" "text", "p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_support_chat_room"("p_customer_id" "uuid", "p_owner_id" "uuid", "p_title" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_room_id UUID;
    v_result JSONB;
BEGIN
    -- 1. Check if an active support room already exists between these two
    -- (Support chats are general, so one room per customer-station pair is usually enough)
    SELECT cr.id INTO v_room_id
    FROM chat_rooms cr
    JOIN chat_participants cp1 ON cr.id = cp1.room_id AND cp1.user_id = p_customer_id
    JOIN chat_participants cp2 ON cr.id = cp2.room_id AND cp2.user_id = p_owner_id
    WHERE cr.room_type = 'customer_support'
    AND cr.status = 'active'
    LIMIT 1;
    
    IF v_room_id IS NOT NULL THEN
        -- Return existing room summary
        SELECT jsonb_build_object(
            'id', cr.id,
            'room_type', cr.room_type,
            'owner_id', cr.owner_id,
            'title', cr.title,
            'status', cr.status,
            'created_at', cr.created_at,
            'updated_at', cr.updated_at,
            'participants', (
                select jsonb_agg(
                    jsonb_build_object(
                        'id', cp.id,
                        'room_id', cp.room_id,
                        'user_id', cp.user_id,
                        'role_in_room', cp.role_in_room,
                        'joined_at', cp.joined_at,
                        'is_muted', false,
                        'metadata', '{}'::jsonb
                    )
                )
                from chat_participants cp
                where cp.room_id = cr.id
            )
        ) INTO v_result
        FROM chat_rooms cr
        WHERE cr.id = v_room_id;
        
        RETURN v_result;
    END IF;
    
    -- 2. Create new chat room
    INSERT INTO chat_rooms (room_type, owner_id, title, status)
    VALUES ('customer_support', p_owner_id, p_title, 'active')
    RETURNING id INTO v_room_id;
    
    -- 3. Add customer as participant
    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_customer_id, 'customer');
    
    -- 4. Add owner as participant
    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_owner_id, 'owner');
    
    -- 5. Add initial system message
    INSERT INTO messages (room_id, content, message_type)
    VALUES (v_room_id, 'Support chat started. You can now message the station owner directly.', 'system');
    
    -- 6. Return response
    SELECT jsonb_build_object(
        'id', cr.id,
        'room_type', cr.room_type,
        'owner_id', cr.owner_id,
        'title', cr.title,
        'status', cr.status,
        'created_at', cr.created_at,
        'updated_at', cr.updated_at,
        'participants', (
            select jsonb_agg(
                jsonb_build_object(
                    'id', cp.id,
                    'room_id', cp.room_id,
                    'user_id', cp.user_id,
                    'role_in_room', cp.role_in_room,
                    'joined_at', cp.joined_at,
                    'is_muted', false,
                    'metadata', '{}'::jsonb
                )
            )
            from chat_participants cp
            where cp.room_id = cr.id
        )
    ) INTO v_result
    FROM chat_rooms cr
    WHERE cr.id = v_room_id;
    
    RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."create_support_chat_room"("p_customer_id" "uuid", "p_owner_id" "uuid", "p_title" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cron_nightly_ops"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Record daily completion rate metric
    INSERT INTO public.operational_metrics (metric_name, metric_value)
    SELECT 'DAILY_COMPLETION_RATE', 
           (SELECT COUNT(*) FILTER (WHERE status = 'delivered')::DECIMAL / NULLIF(COUNT(*), 0) FROM public.orders WHERE created_at > NOW() - INTERVAL '24 hours');

    -- Cleanup Domain Events older than 30 days (Observability)
    DELETE FROM public.domain_events WHERE created_at < NOW() - INTERVAL '30 days';
    
    -- Cleanup Audit Logs older than 6 months
    DELETE FROM public.audit_logs WHERE created_at < NOW() - INTERVAL '180 days';
END;
$$;


ALTER FUNCTION "public"."cron_nightly_ops"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cron_nightly_ops_refined"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Run Nightly Rollups & Cleanups
    PERFORM public.cron_nightly_ops(); 
    
    -- Run Integrity Watchdog
    PERFORM public.run_integrity_watchdog();
END;
$$;


ALTER FUNCTION "public"."cron_nightly_ops_refined"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_user_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- 1. Identity Verification
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- 2. Cleanup Historical Links (Avoid Constraint Violations)
  -- We set to NULL instead of DELETE to preserve business records for the OTHER party
  -- (e.g., if a customer deletes their account, the owner still needs the order history)
  
  -- Unlink from Orders (as customer, owner, or rider)
  UPDATE public.orders SET customer_id = NULL WHERE customer_id = v_user_id;
  UPDATE public.orders SET owner_id = NULL WHERE owner_id = v_user_id;
  UPDATE public.orders SET assigned_rider_id = NULL WHERE assigned_rider_id = v_user_id;

  -- Unlink from Chat Participants
  DELETE FROM public.chat_participants WHERE user_id = v_user_id;
  
  -- Unlink from Rider Locations (if any)
  DELETE FROM public.rider_locations WHERE rider_id = v_user_id;

  -- 3. Final Wipe
  -- Delete from auth.users (Cascades to public.profiles if configured, but let's be explicit)
  DELETE FROM public.profiles WHERE id = v_user_id;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;


ALTER FUNCTION "public"."delete_user_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_order_status_logic"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Prevent directly going from 'pending' to 'delivered'
    IF OLD.status = 'pending' AND NEW.status = 'delivered' THEN
        RAISE EXCEPTION 'Invalid transition: Must go through preparing/accepted and out_for_delivery stages first.';
    END IF;
    
    -- Prevent changing status once 'delivered'
    IF OLD.status = 'delivered' AND NEW.status != 'delivered' THEN
        RAISE EXCEPTION 'Order is already delivered and cannot be modified.';
    END IF;

    -- Update audit log for visibility
    IF OLD.status != NEW.status THEN
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, old_value, new_value)
        VALUES (auth.uid(), 'STATUS_CHANGE', 'order', NEW.id::text, jsonb_build_object('status', OLD.status), jsonb_build_object('status', NEW.status));
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."enforce_order_status_logic"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_pgcrypto"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Try to create extension if not exists
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    
    -- Verify gen_salt is available
    PERFORM gen_salt('bf');
EXCEPTION
    WHEN undefined_function THEN
        RAISE EXCEPTION 'pgcrypto extension is not properly installed. Please enable it manually in Supabase dashboard.';
END;
$$;


ALTER FUNCTION "public"."ensure_pgcrypto"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_digital_receipt_data"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_order RECORD;
    v_items JSONB;
BEGIN
    -- Get Order Header
    SELECT id, station_name, customer_name, customer_address, total_amount, subtotal, delivery_fee, payment_method, created_at, actual_completion_at
    INTO v_order
    FROM public.orders WHERE id = p_order_id;

    -- Get Items
    SELECT json_agg(json_build_object('name', product_name, 'qty', quantity, 'price', price_at_purchase, 'total', subtotal))
    INTO v_items
    FROM public.order_items WHERE order_id = p_order_id;

    RETURN jsonb_build_object(
        'receipt_id', v_order.id,
        'station', v_order.station_name,
        'customer', v_order.customer_name,
        'address', v_order.customer_address,
        'date', v_order.actual_completion_at,
        'payment', v_order.payment_method,
        'items', v_items,
        'summary', jsonb_build_object(
            'net', v_order.subtotal,
            'delivery', v_order.delivery_fee,
            'gross', v_order.total_amount
        )
    );
END;
$$;


ALTER FUNCTION "public"."get_digital_receipt_data"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dispatch_recommendation"("p_owner_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_peak_hour INT;
    v_avg_hourly_orders INT;
    v_current_riders INT;
    v_suggestion TEXT;
BEGIN
    -- Simplified logic: If avg peak orders > (riders * 5 orders/hr), suggest more.
    -- (Placeholder for a more complex heuristic)
    
    SELECT EXTRACT(HOUR FROM created_at) INTO v_peak_hour
    FROM public.orders WHERE owner_id = p_owner_id
    GROUP BY 1 ORDER BY COUNT(*) DESC LIMIT 1;

    SELECT COUNT(*) INTO v_current_riders FROM public.profiles WHERE owner_id = p_owner_id AND role = 'rider' AND is_online = TRUE;

    IF v_current_riders = 0 THEN
        v_suggestion := 'Add and onboard your first rider to begin accepting orders.';
    ELSIF v_peak_hour BETWEEN 16 AND 19 THEN
        v_suggestion := 'Peak Demand detected (4PM-7PM). Ensure at least ' || (v_current_riders + 1) || ' riders are online during this window.';
    ELSE
        v_suggestion := 'Current fleet capacity looks stable. Focus on reducing avg delivery time for top performers.';
    END IF;

    RETURN jsonb_build_object(
        'recommendation', v_suggestion,
        'peak_window', v_peak_hour || ':00 - ' || (v_peak_hour + 1) || ':00'
    );
END;
$$;


ALTER FUNCTION "public"."get_dispatch_recommendation"("p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_chat_rooms"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    v_user_id uuid;
    v_result jsonb;
begin
    v_user_id := auth.uid();
    if v_user_id is null then
        return '[]'::jsonb;
    end if;

    with user_rooms as (
        -- Get all rooms where user is a participant or owner
        select distinct cr.*
        from public.chat_rooms cr
        left join public.chat_participants cp on cp.room_id = cr.id
        where cr.owner_id = v_user_id or cp.user_id = v_user_id
    ),
    room_last_messages as (
        -- Get the most recent message for each room
        select distinct on (room_id)
            room_id,
            jsonb_build_object(
                'id', id,
                'room_id', room_id, -- ADDED: This fixes the Dart model error
                'content', content,
                'sender_id', sender_id,
                'message_type', message_type,
                'created_at', created_at
            ) as last_message
        from public.messages
        where deleted_at is null
        order by room_id, created_at desc
    ),
    room_unread_counts as (
        -- Get unread count for the current user in each room
        select 
            m.room_id,
            count(*) as unread_count
        from public.messages m
        join public.chat_participants cp on cp.room_id = m.room_id and cp.user_id = v_user_id
        where m.sender_id != v_user_id
        and not m.read_by @> jsonb_build_array(v_user_id::text)
        and m.deleted_at is null
        group by m.room_id
    ),
    room_participants as (
        -- Get all participants for each room with profile details
        select 
            cp.room_id,
            jsonb_agg(
                jsonb_build_object(
                    'id', p.id,
                    'full_name', p.full_name,
                    'avatar_url', p.avatar_url,
                    'role', cp.role_in_room
                )
            ) as participants
        from public.chat_participants cp
        join public.profiles p on p.id = cp.user_id
        group by cp.room_id
    )
    select 
        jsonb_agg(
            jsonb_build_object(
                'id', ur.id,
                'room_type', ur.room_type,
                'reference_id', ur.reference_id,
                'status', ur.status,
                'owner_id', ur.owner_id,
                'title', ur.title,
                'updated_at', ur.updated_at,
                'metadata', ur.metadata,
                'last_message', lmf.last_message,
                'unread_count', coalesce(ruc.unread_count, 0),
                'participants', coalesce(rp.participants, '[]'::jsonb)
            )
            order by ur.updated_at desc
        )
    into v_result
    from user_rooms ur
    left join room_last_messages lmf on lmf.room_id = ur.id
    left join room_unread_counts ruc on ruc.room_id = ur.id
    left join room_participants rp on rp.room_id = ur.id;

    return coalesce(v_result, '[]'::jsonb);
end;
$$;


ALTER FUNCTION "public"."get_my_chat_rooms"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_order_batch_suggestions"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_order_barangay TEXT;
    v_order_owner_id UUID;
    v_suggestions JSONB;
BEGIN
    -- Get current order's cluster (Barangay)
    SELECT customer_barangay, owner_id INTO v_order_barangay, v_order_owner_id
    FROM public.orders WHERE id = p_order_id;

    -- Find other active orders in the same cluster that haven't been dispatched yet
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', id,
            'customer_name', customer_name,
            'status', status,
            'cluster', customer_barangay
        )
    ) INTO v_suggestions
    FROM public.orders
    WHERE owner_id = v_order_owner_id
      AND customer_barangay = v_order_barangay
      AND status IN ('pending', 'accepted', 'preparing')
      AND id != p_order_id;

    RETURN COALESCE(v_suggestions, '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."get_order_batch_suggestions"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_peak_hour_stats"("p_owner_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_stats JSONB;
BEGIN
    SELECT json_agg(row_to_json(t)) INTO v_stats
    FROM (
        SELECT 
            EXTRACT(HOUR FROM created_at) AS hour_of_day,
            COUNT(*) AS order_count
        FROM public.orders
        WHERE owner_id = p_owner_id AND created_at >= NOW() - INTERVAL '7 days'
        GROUP BY hour_of_day
        ORDER BY hour_of_day ASC
    ) t;
    
    RETURN COALESCE(v_stats, '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."get_peak_hour_stats"("p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_platform_fee_config"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT jsonb_build_object(
    'enabled', coalesce((
      SELECT CASE
        WHEN jsonb_typeof(value) = 'boolean' THEN (value)::text::boolean
        WHEN jsonb_typeof(value) = 'string' THEN lower(trim(both '"' from value::text)) IN ('true', '1', 'yes')
        ELSE false
      END
      FROM public.system_config WHERE key = 'platform_fee_enabled'
    ), false),
    'percent', coalesce((
      SELECT CASE
        WHEN jsonb_typeof(value) = 'number' THEN (value)::text::numeric
        ELSE nullif(trim(both '"' from value::text), '')::numeric
      END
      FROM public.system_config WHERE key = 'platform_fee_percent'
    ), 0),
    'fixed', coalesce((
      SELECT CASE
        WHEN jsonb_typeof(value) = 'number' THEN (value)::text::numeric
        ELSE nullif(trim(both '"' from value::text), '')::numeric
      END
      FROM public.system_config WHERE key = 'platform_fee_fixed'
    ), 0)
  );
$$;


ALTER FUNCTION "public"."get_platform_fee_config"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_station_available_payment_methods"("p_owner_id" "uuid") RETURNS TABLE("type" "text", "label" "text", "available" boolean, "reason" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    method.type,
    method.label,
    method.type = ANY(COALESCE(settings.enabled_payment_methods,
      ARRAY['cod', 'gcash', 'maya', 'card']::text[])) AS available,
    CASE WHEN method.type = ANY(COALESCE(settings.enabled_payment_methods,
      ARRAY['cod', 'gcash', 'maya', 'card']::text[]))
      THEN NULL ELSE 'This station has disabled this payment method.' END AS reason
  FROM (
    VALUES
      ('cod'::text, 'Cash on Delivery'::text),
      ('gcash'::text, 'GCash'::text),
      ('maya'::text, 'Maya'::text),
      ('card'::text, 'Credit/Debit Card'::text)
  ) AS method(type, label)
  LEFT JOIN public.owner_settings settings ON settings.owner_id = p_owner_id
  WHERE EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_owner_id AND role = 'owner'
  );
$$;


ALTER FUNCTION "public"."get_station_available_payment_methods"("p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unread_count"("p_user_id" "uuid") RETURNS TABLE("room_id" "uuid", "unread_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    return query
    select 
        m.room_id,
        count(*) as unread_count
    from public.messages m
    join public.chat_participants cp on cp.room_id = m.room_id and cp.user_id = p_user_id
    where m.sender_id != p_user_id
    and not (p_user_id = any(m.read_by))
    and m.deleted_at is null
    group by m.room_id;
end;
$$;


ALTER FUNCTION "public"."get_unread_count"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    v_count integer;
begin
    select count(*) into v_count
    from public.system_notifications
    where user_id = p_user_id
    and is_read = false
    and (expires_at is null or expires_at > now());
    
    return v_count;
end;
$$;


ALTER FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_profile_role_changes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF (NEW.role IS DISTINCT FROM OLD.role)
    OR (NEW.is_suspended IS DISTINCT FROM OLD.is_suspended)
    OR (NEW.owner_id IS DISTINCT FROM OLD.owner_id)
  THEN
    -- Only service_role or a verified admin can change privileged account fields.
    IF auth.role() IS DISTINCT FROM 'service_role' AND NOT EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: You cannot alter protected account fields.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."guard_profile_role_changes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_system_message_spoofing"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF (NEW.sender_id IS NULL OR NEW.message_type = 'system') THEN
    IF auth.role() IS DISTINCT FROM 'service_role' AND NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: Only system service or administrator can issue system messages.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."guard_system_message_spoofing"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_inventory_deduction"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Only deduct for products that exist in the products table (UUID)
    IF NEW.product_id IS NOT NULL THEN
        UPDATE public.products
        SET stock_level = stock_level - NEW.quantity
        WHERE id = NEW.product_id;
        
        -- Log a Low Stock event if needed
        IF EXISTS (SELECT 1 FROM public.products WHERE id = NEW.product_id AND stock_level <= low_stock_threshold) THEN
            INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
            VALUES (NULL, 'LOW_STOCK_WARNING', 'product', NEW.product_id::text, jsonb_build_object('current_stock', (SELECT stock_level FROM public.products WHERE id = NEW.product_id)));
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_inventory_deduction"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    username,
    full_name,
    first_name,
    last_name,
    mi,
    suffix,
    role,
    phone,
    town,
    barangay,
    complete_address,
    landmark,
    station_name,
    latitude,
    longitude
  )
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)),
    COALESCE(new.raw_user_meta_data->>'full_name', 'New User'),
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name',
    new.raw_user_meta_data->>'mi',
    new.raw_user_meta_data->>'suffix',
    COALESCE((new.raw_user_meta_data->>'role'), 'customer')::user_role,
    new.raw_user_meta_data->>'phone',
    (new.raw_user_meta_data->>'town')::municipality,
    new.raw_user_meta_data->>'barangay',
    new.raw_user_meta_data->>'complete_address',
    new.raw_user_meta_data->>'landmark',
    new.raw_user_meta_data->>'station_name',
    (new.raw_user_meta_data->>'latitude')::DOUBLE PRECISION,
    (new.raw_user_meta_data->>'longitude')::DOUBLE PRECISION
  )
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        username = EXCLUDED.username,
        full_name = EXCLUDED.full_name,
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        mi = EXCLUDED.mi,
        suffix = EXCLUDED.suffix,
        role = EXCLUDED.role,
        phone = EXCLUDED.phone,
        town = EXCLUDED.town,
        barangay = EXCLUDED.barangay,
        complete_address = EXCLUDED.complete_address,
        landmark = EXCLUDED.landmark,
        station_name = EXCLUDED.station_name,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude;

  RETURN new;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role::text = 'admin'
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return exists (
        select 1 from public.chat_rooms
        where id = p_room_id
        and owner_id = p_user_id
    );
end;
$$;


ALTER FUNCTION "public"."is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return exists (
        select 1 from public.chat_participants
        where room_id = p_room_id
        and user_id = p_user_id
    );
end;
$$;


ALTER FUNCTION "public"."is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_station_payment_method_available"("p_owner_id" "uuid", "p_payment_method" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles owner_profile
    LEFT JOIN public.owner_settings settings
      ON settings.owner_id = owner_profile.id
    WHERE owner_profile.id = p_owner_id
      AND owner_profile.role = 'owner'
      AND COALESCE(settings.enabled_payment_methods,
        ARRAY['cod', 'gcash', 'maya', 'card']::text[])
        @> ARRAY[
          CASE lower(trim(p_payment_method))
            WHEN 'cash' THEN 'cod'
            WHEN 'paymaya' THEN 'maya'
            ELSE lower(trim(p_payment_method))
          END
        ]::text[]
  );
$$;


ALTER FUNCTION "public"."is_station_payment_method_available"("p_owner_id" "uuid", "p_payment_method" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_super_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role::text = 'admin'
      AND coalesce(admin_tier, 'super') = 'super'
  );
$$;


ALTER FUNCTION "public"."is_super_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_owner_inventory_tx"("p_tx_type" "text", "p_gallons" integer, "p_notes" "text" DEFAULT NULL::"text", "p_product_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_owner_id uuid := auth.uid();
    v_product record;
    v_new_stock integer;
    v_empty_stock integer;
BEGIN
    IF v_owner_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Authentication required.');
    END IF;

    IF p_gallons = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Gallon amount must not be zero.');
    END IF;

    IF p_tx_type IN ('load_filled', 'adjust_filled') THEN
        IF p_product_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'message', 'Product is required for filled-gallon updates.');
        END IF;

        SELECT * INTO v_product
        FROM public.products
        WHERE id = p_product_id AND owner_id = v_owner_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'Product not found for this station.');
        END IF;

        IF p_tx_type = 'load_filled' AND p_gallons < 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'Load amount must be positive.');
        END IF;

        v_new_stock := coalesce(v_product.stock_level, 0) + p_gallons;

        IF v_new_stock < 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'Filled stock cannot go below zero.');
        END IF;

        UPDATE public.products SET stock_level = v_new_stock WHERE id = p_product_id;

        INSERT INTO public.owner_inventory_ledger (
            owner_id, tx_type, gallons, product_id, notes, actor_id
        ) VALUES (
            v_owner_id, p_tx_type, p_gallons, p_product_id,
            nullif(trim(p_notes), ''), v_owner_id
        );
    ELSIF p_tx_type IN ('load_empty', 'adjust_empty') THEN
        IF p_tx_type = 'load_empty' AND p_gallons < 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'Load amount must be positive.');
        END IF;

        INSERT INTO public.owner_settings (owner_id, empty_gallons_stock)
        VALUES (v_owner_id, 0)
        ON CONFLICT (owner_id) DO NOTHING;

        SELECT empty_gallons_stock INTO v_empty_stock
        FROM public.owner_settings
        WHERE owner_id = v_owner_id
        FOR UPDATE;

        IF coalesce(v_empty_stock, 0) + p_gallons < 0 THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Empty gallon stock cannot go below zero.'
            );
        END IF;

        UPDATE public.owner_settings
        SET empty_gallons_stock = empty_gallons_stock + p_gallons,
            updated_at = now()
        WHERE owner_id = v_owner_id;

        INSERT INTO public.owner_inventory_ledger (
            owner_id, tx_type, gallons, notes, actor_id
        ) VALUES (
            v_owner_id, p_tx_type, p_gallons,
            nullif(trim(p_notes), ''), v_owner_id
        );
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Unsupported inventory transaction type.');
    END IF;

    RETURN jsonb_build_object('success', true, 'message', 'Inventory updated.');
END;
$$;


ALTER FUNCTION "public"."log_owner_inventory_tx"("p_tx_type" "text", "p_gallons" integer, "p_notes" "text", "p_product_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_all_notifications_read"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    update public.system_notifications
    set is_read = true,
        read_at = now()
    where user_id = auth.uid()
    and is_read = false;
end;
$$;


ALTER FUNCTION "public"."mark_all_notifications_read"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_message_delivered"("p_message_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    UPDATE public.messages 
    SET status = 'delivered', updated_at = NOW()
    WHERE id = p_message_id AND status = 'sent';
END;
$$;


ALTER FUNCTION "public"."mark_message_delivered"("p_message_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    -- Update messages to mark as read by current user
    update public.messages
    set read_by = case
        when auth.uid() = any(read_by) then read_by
        else read_by || auth.uid()::text::jsonb
    end,
    is_read = true
    where room_id = p_room_id
    and sender_id != auth.uid()
    and not (auth.uid() = any(read_by));
    
    -- Update participant's last_read_at
    update public.chat_participants
    set last_read_at = now()
    where room_id = p_room_id
    and user_id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    -- Add the user_id to the read_by jsonb array if it's not already there
    -- Only for messages where the user is NOT the sender
    update public.messages
    set read_by = (
        case 
            when read_by is null or read_by = '[]'::jsonb then jsonb_build_array(p_user_id)
            else read_by || jsonb_build_array(p_user_id)
        end
    ),
    is_read = true
    where room_id = p_room_id
    and sender_id != p_user_id
    and not (read_by @> jsonb_build_array(p_user_id)::jsonb);
end;
$$;


ALTER FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_notification_read"("p_notification_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    update public.system_notifications
    set is_read = true,
        read_at = now()
    where id = p_notification_id
    and user_id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."mark_notification_read"("p_notification_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_room_as_seen"("p_room_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Update participant's last read mark
    UPDATE public.chat_participants 
    SET last_read_at = NOW() 
    WHERE room_id = p_room_id AND user_id = p_user_id;

    -- Update all messages in room to 'seen' if they aren't from the seer
    UPDATE public.messages 
    SET status = 'seen', updated_at = NOW()
    WHERE room_id = p_room_id 
      AND sender_id != p_user_id 
      AND status != 'seen';
END;
$$;


ALTER FUNCTION "public"."mark_room_as_seen"("p_room_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_earnings_payout"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    -- Create notification for rider about earnings
    insert into public.system_notifications (
        user_id,
        type,
        priority,
        title,
        content,
        metadata
    ) values (
        new.rider_id,
        'earnings_payout',
        'normal',
        'Earnings Processed',
        format('Your earnings of ₱%s have been processed and added to your account.', 
               new.amount),
        jsonb_build_object(
            'remittance_id', new.id,
            'amount', new.amount,
            'period_start', new.period_start,
            'period_end', new.period_end
        )
    );
    
    return new;
end;
$$;


ALTER FUNCTION "public"."notify_earnings_payout"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_rider_order_assigned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    v_order_details record;
begin
    if new.assigned_rider_id is not null and 
       (old.assigned_rider_id is null or old.assigned_rider_id != new.assigned_rider_id) then
        
        select 
            o.id,
            o.total_amount,
            p.full_name as customer_name,
            p.complete_address as delivery_address
        into v_order_details
        from public.orders o
        left join public.profiles p on p.id = o.customer_id
        where o.id = new.id;
        
        insert into public.system_notifications (
            user_id, type, priority, title, content, metadata
        ) values (
            new.assigned_rider_id, 'order_assigned', 'high', 'New Order Assigned!',
            format('You have been assigned a new order from %s for ₱%s', 
                   v_order_details.customer_name, v_order_details.total_amount),
            jsonb_build_object(
                'order_id', new.id,
                'total_amount', v_order_details.total_amount,
                'customer_name', v_order_details.customer_name,
                'delivery_address', v_order_details.delivery_address
            )
        );
    end if;
    return new;
end;
$$;


ALTER FUNCTION "public"."notify_rider_order_assigned"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pmin"("a" double precision, "b" double precision) RETURNS double precision
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT CASE WHEN a < b THEN a ELSE b END;
$$;


ALTER FUNCTION "public"."pmin"("a" double precision, "b" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proc_analyze_rider_behavior"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_order_duration INTERVAL;
    v_distance_to_customer DOUBLE PRECISION;
    v_customer_lat DOUBLE PRECISION;
    v_customer_lng DOUBLE PRECISION;
BEGIN
    -- Only trigger when status changes to 'delivered'
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        
        -- A. Fast Delivery Check (e.g. < 2 mins between 'out_for_delivery' and 'delivered')
        -- Note: We need a timestamp when it was marked 'out_for_delivery'
        -- For now, we'll use actual_completion_at vs updated_at? 
        -- Better: let's assume 'updated_at' is when it moved to 'delivered'
        -- and we'd need another column for 'out_for_delivery_at'.
        -- (Skipping timing for this exact migration, focusing on location mismatch)

        -- B. Location Mismatch Check (PoD Location vs Profile Location)
        -- Get customer profile location (Pinned location)
        SELECT latitude, longitude INTO v_customer_lat, v_customer_lng 
        FROM public.profiles 
        WHERE id = NEW.customer_id;

        IF NEW.delivery_latitude IS NOT NULL AND v_customer_lat IS NOT NULL THEN
            -- Simple cartesian distance (simplified for SQL proof of concept)
            IF ABS(NEW.delivery_latitude - v_customer_lat) > 0.005 OR 
               ABS(NEW.delivery_longitude - v_customer_lng) > 0.005 THEN
                
                INSERT INTO public.suspicious_activities (rider_id, order_id, activity_type, severity, details)
                VALUES (NEW.assigned_rider_id, NEW.id, 'LOCATION_MISMATCH', 'HIGH', 
                        jsonb_build_object('delivery_lat', NEW.delivery_latitude, 'customer_lat', v_customer_lat));
                
                UPDATE public.profiles SET flagged_count = flagged_count + 1 WHERE id = NEW.assigned_rider_id;
            END IF;
        END IF;

        -- Update total delivery count
        UPDATE public.profiles SET total_deliveries = total_deliveries + 1 WHERE id = NEW.assigned_rider_id;

        -- Recalculate Score (Basic logic: Start 5.0, subtract 0.5 per flag, but min 1.0)
        UPDATE public.profiles 
        SET reliability_score = GREATEST(1.0, 5.0 - (flagged_count * 0.5))
        WHERE id = NEW.assigned_rider_id;

    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."proc_analyze_rider_behavior"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proc_finalize_order_finances"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_commission NUMERIC;
BEGIN
    -- Only act when status changes to 'delivered'
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        
        -- 1. Record Station Sale (Credit)
        INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
        VALUES (NEW.owner_id, NEW.id, NEW.total_amount, 'SALE', 'Order completion payment');

        -- 2. Calculate and Record Rider Commission (Step 5: Transparency)
        -- Hardcoded 10% for now or from owner_settings if implemented
        v_commission := NEW.total_amount * 0.10;
        
        IF NEW.assigned_rider_id IS NOT NULL THEN
            INSERT INTO public.ledger_entries (account_id, order_id, amount, entry_type, description)
            VALUES (NEW.assigned_rider_id, NEW.id, v_commission, 'COMMISSION', 'Delivery commission for order');
        END IF;

        -- 3. Broadcast Event (Step 3: Event-Driven)
        INSERT INTO public.domain_events (event_type, payload, actor_id)
        VALUES ('ORDER_COMPLETED', jsonb_build_object('order_id', NEW.id, 'total', NEW.total_amount, 'rider_id', NEW.assigned_rider_id), auth.uid());

    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."proc_finalize_order_finances"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proc_log_dispute_event"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    INSERT INTO public.domain_events (event_type, payload, actor_id)
    VALUES ('DISPUTE_CREATED', jsonb_build_object('order_id', NEW.order_id, 'reason', NEW.reason, 'dispute_id', NEW.id), NEW.reporter_id);
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."proc_log_dispute_event"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proc_log_inventory_event"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Only log into inventory_ledger if the product_id is not null.
    -- Virtual products (synthesized by app for single-product stations) do not have 
    -- entries in the products table and thus do not need stock auditing.
    IF NEW.product_id IS NOT NULL THEN
        INSERT INTO public.inventory_ledger (product_id, change_amount, reason, actor_id)
        VALUES (NEW.product_id, -NEW.quantity, 'SALE', NULL);
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."proc_log_inventory_event"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proc_restore_inventory_on_cancellation"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    item RECORD;
BEGIN
    -- Only trigger if status changes to 'cancelled'
    IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
        FOR item IN SELECT product_id, quantity FROM public.order_items WHERE order_id = NEW.id
        LOOP
            IF item.product_id IS NOT NULL THEN
                UPDATE public.products 
                SET stock_level = stock_level + item.quantity 
                WHERE id = item.product_id;
                
                -- Log the restoration for financial audit
                INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
                VALUES (auth.uid(), 'INVENTORY_RESTORED', 'product', item.product_id::text, jsonb_build_object('order_id', NEW.id, 'restored_qty', item.quantity));
            END IF;
        END LOOP;
        
        -- Update payment status if it was still pending/processing
        IF NEW.payment_status IN ('pending', 'processing') THEN
            NEW.payment_status := 'failed';
        END IF;

    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."proc_restore_inventory_on_cancellation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proc_sync_order_chat_participants"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_room_id UUID;
BEGIN
    -- Check if assigned_rider_id changed
    IF OLD.assigned_rider_id IS DISTINCT FROM NEW.assigned_rider_id THEN
        
        -- Find the chat room associated with this order
        SELECT id INTO v_room_id FROM public.chat_rooms WHERE reference_id = NEW.id AND room_type = 'order_delivery' LIMIT 1;
        
        IF v_room_id IS NOT NULL THEN
            -- A. Remove old rider (if any)
            IF OLD.assigned_rider_id IS NOT NULL THEN
                DELETE FROM public.chat_participants 
                WHERE room_id = v_room_id AND user_id = OLD.assigned_rider_id AND role_in_room = 'rider';
            END IF;
            
            -- B. Add new rider (if any)
            IF NEW.assigned_rider_id IS NOT NULL THEN
                INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                VALUES (v_room_id, NEW.assigned_rider_id, 'rider')
                ON CONFLICT (room_id, user_id) DO UPDATE SET role_in_room = 'rider';
            END IF;
        END IF;

    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."proc_sync_order_chat_participants"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_payment_checkout"("p_order_id" "uuid", "p_customer_id" "uuid", "p_owner_id" "uuid", "p_payment_method" "text", "p_provider_checkout_id" "text", "p_checkout_url" "text", "p_amount" numeric, "p_status" "text", "p_raw_response" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Only the payment service can record checkout sessions.';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND
    OR v_order.customer_id IS DISTINCT FROM p_customer_id
    OR v_order.owner_id IS DISTINCT FROM p_owner_id
    OR lower(v_order.payment_method) IS DISTINCT FROM lower(p_payment_method)
    OR v_order.total_amount IS DISTINCT FROM p_amount
    OR v_order.payment_status = 'success'
    OR v_order.status IN ('cancelled', 'delivered')
  THEN
    RAISE EXCEPTION 'Order is not eligible for this checkout session.';
  END IF;

  IF v_order.payment_status = 'processing'
    AND EXISTS (
      SELECT 1
      FROM public.payment_checkouts checkout
      WHERE checkout.order_id = p_order_id
        AND lower(checkout.status) NOT IN (
          'failed', 'expired', 'cancelled', 'canceled', 'paid', 'succeeded', 'completed'
        )
    )
  THEN
    RAISE EXCEPTION 'An active checkout session already exists for this order.';
  END IF;

  INSERT INTO public.payment_checkouts (
    order_id, customer_id, owner_id, provider, payment_method,
    provider_checkout_id, checkout_url, amount, currency, status, raw_response
  ) VALUES (
    p_order_id, p_customer_id, p_owner_id, 'paymongo', p_payment_method,
    p_provider_checkout_id, p_checkout_url, p_amount, 'PHP', p_status,
    p_raw_response
  );

  UPDATE public.orders
  SET payment_checkout_id = p_provider_checkout_id,
      payment_checkout_url = p_checkout_url,
      payment_status = 'processing',
      payment_error = NULL,
      updated_at = now()
  WHERE id = p_order_id;
END;
$$;


ALTER FUNCTION "public"."record_payment_checkout"("p_order_id" "uuid", "p_customer_id" "uuid", "p_owner_id" "uuid", "p_payment_method" "text", "p_provider_checkout_id" "text", "p_checkout_url" "text", "p_amount" numeric, "p_status" "text", "p_raw_response" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_integrity_watchdog"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_report JSONB;
BEGIN
    -- A. HEAL: Revert orphaned 'En Route' orders back to 'Preparing' for re-dispatch
    UPDATE public.orders 
    SET status = 'preparing'
    WHERE status = 'out_for_delivery' AND assigned_rider_id IS NULL;

    -- B. FLAG: Log critical inconsistencies into Domain Events for manual review
    INSERT INTO public.domain_events (event_type, payload, actor_id)
    SELECT 'INTEGRITY_VIOLATION', jsonb_build_object('order_id', order_id, 'type', violation_type, 'desc', description), owner_id
    FROM public.integrity_violations;

    SELECT jsonb_build_object('violations_found', (SELECT COUNT(*) FROM public.integrity_violations)) INTO v_report;
    RETURN v_report;
END;
$$;


ALTER FUNCTION "public"."run_integrity_watchdog"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sec_def_is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.chat_rooms
        WHERE id = p_room_id
        AND owner_id = p_user_id
    );
END;
$$;


ALTER FUNCTION "public"."sec_def_is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sec_def_is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.chat_participants
        WHERE room_id = p_room_id
        AND user_id = p_user_id
    );
END;
$$;


ALTER FUNCTION "public"."sec_def_is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_quick_reply"("p_room_id" "uuid", "p_quick_reply_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    v_message_text text;
    v_rider_id uuid;
    v_message_id uuid;
begin
    -- Get the quick reply details and verify ownership
    select qr.message_text, qr.rider_id
    into v_message_text, v_rider_id
    from public.quick_replies qr
    where qr.id = p_quick_reply_id
    and qr.rider_id = auth.uid();
    
    if v_message_text is null then
        raise exception 'Quick reply not found or not authorized';
    end if;
    
    -- Send the message
    insert into public.messages (room_id, sender_id, content, message_type, metadata)
    values (
        p_room_id, 
        auth.uid(), 
        v_message_text, 
        'quick_reply',
        jsonb_build_object('quick_reply_id', p_quick_reply_id, 'quick_reply_label', (
            select label from public.quick_replies where id = p_quick_reply_id
        ))
    )
    returning id into v_message_id;
    
    return v_message_id;
end;
$$;


ALTER FUNCTION "public"."send_quick_reply"("p_room_id" "uuid", "p_quick_reply_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_system_message"("p_room_id" "uuid", "p_content" "text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    v_message_id uuid;
begin
    insert into public.messages (room_id, sender_id, content, message_type, metadata)
    values (p_room_id, null, p_content, 'system', p_metadata)
    returning id into v_message_id;
    
    return v_message_id;
end;
$$;


ALTER FUNCTION "public"."send_system_message"("p_room_id" "uuid", "p_content" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_payment_account_default"("p_user_id" "uuid", "p_account_id" "uuid", "p_scope" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Only the payment service can update default accounts.';
  END IF;

  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = p_user_id
  FOR UPDATE;

  IF (p_scope = 'customer_payment_methods' AND v_role IS DISTINCT FROM 'customer')
    OR (p_scope = 'owner_payout_accounts' AND v_role IS DISTINCT FROM 'owner')
    OR p_scope NOT IN ('customer_payment_methods', 'owner_payout_accounts')
  THEN
    RAISE EXCEPTION 'Invalid payment account scope.';
  END IF;

  IF p_scope = 'customer_payment_methods' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.customer_payment_methods
      WHERE id = p_account_id AND customer_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Payment account not found.';
    END IF;
    UPDATE public.customer_payment_methods
    SET is_default = false
    WHERE customer_id = p_user_id AND is_default;
    UPDATE public.customer_payment_methods
    SET is_default = true, updated_at = now()
    WHERE id = p_account_id AND customer_id = p_user_id;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM public.owner_payout_accounts
      WHERE id = p_account_id AND owner_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Payout account not found.';
    END IF;
    UPDATE public.owner_payout_accounts
    SET is_default = false
    WHERE owner_id = p_user_id AND is_default;
    UPDATE public.owner_payout_accounts
    SET is_default = true, updated_at = now()
    WHERE id = p_account_id AND owner_id = p_user_id;
  END IF;
END;
$$;


ALTER FUNCTION "public"."set_payment_account_default"("p_user_id" "uuid", "p_account_id" "uuid", "p_scope" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."smart_dispatch_rider"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_order RECORD;
    v_best_rider_id UUID;
    v_success BOOLEAN;
BEGIN
    -- Get order details
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
    
    IF NOT FOUND OR v_order.status != 'pending' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Order is not pending or not found');
    END IF;

    -- Find best rider:
    -- 1. Must be online
    -- 2. Must belong to the same station (owner_id)
    -- 3. Must have the FEWEST current active orders
    SELECT id INTO v_best_rider_id
    FROM public.profiles p
    WHERE p.role = 'rider'
      AND p.is_online = TRUE
      AND p.station_id = v_order.owner_id -- Simplified: Rider must be manually assigned to a station_id
    ORDER BY (
        SELECT count(*) FROM public.orders o 
        WHERE o.assigned_rider_id = p.id 
          AND o.status IN ('accepted', 'preparing', 'out_for_delivery')
    ) ASC
    LIMIT 1;

    IF v_best_rider_id IS NULL THEN
        -- Fallback: If no rider is specifically 'station_id' matched, 
        -- check for any rider who has previously delivered for this owner?
        -- No, let's keep it strict for now.
        RETURN jsonb_build_object('success', false, 'message', 'No available riders found for this station');
    END IF;

    -- Assign atomically
    SELECT public.assign_rider_safely(p_order_id, v_best_rider_id) INTO v_success;

    IF v_success THEN
        -- Log the action
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_value)
        VALUES (NULL, 'SMART_DISPATCH', 'order', p_order_id::text, jsonb_build_object('rider_id', v_best_rider_id));
        
        RETURN jsonb_build_object('success', true, 'rider_id', v_best_rider_id);
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Concurrent assignment conflict occurred');
    END IF;
END;
$$;


ALTER FUNCTION "public"."smart_dispatch_rider"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."smart_dispatch_rider_regional"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_order RECORD;
    v_best_rider_id UUID;
    v_success BOOLEAN;
BEGIN
    -- Get order details including its assigned region
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
    
    IF NOT FOUND OR v_order.status != 'pending' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Order is not pending or not found');
    END IF;

    -- Find BEST regional rider
    SELECT id INTO v_best_rider_id
    FROM public.profiles p
    WHERE p.role = 'rider'
      AND p.is_online = TRUE
      AND p.region_id = v_order.region_id -- GEOGRAPHICAL POOL ENFORCEMENT
      AND p.station_id = v_order.owner_id
    ORDER BY (
        SELECT count(*) FROM public.orders o 
        WHERE o.assigned_rider_id = p.id 
          AND o.status IN ('accepted', 'preparing', 'out_for_delivery')
    ) ASC
    LIMIT 1;

    IF v_best_rider_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'No available riders found in this region pool.');
    END IF;

    -- Assign atomically
    SELECT public.assign_rider_safely(p_order_id, v_best_rider_id) INTO v_success;

    IF v_success THEN
        RETURN jsonb_build_object('success', true, 'rider_id', v_best_rider_id, 'region', (SELECT name FROM public.regions WHERE id = v_order.region_id));
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Concurrent assignment conflict occurred');
    END IF;
END;
$$;


ALTER FUNCTION "public"."smart_dispatch_rider_regional"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_owner_default_product"("p_owner_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_price numeric(10,2); v_water_type text; v_category text; v_name text;
  v_product_id uuid; v_row public.products%ROWTYPE;
BEGIN
  IF p_owner_id IS NULL OR auth.uid() IS NULL THEN RETURN NULL; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_owner_id AND role = 'owner') THEN RETURN NULL; END IF;
  IF auth.role() <> 'service_role'
    AND auth.uid() <> p_owner_id
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    )
  THEN
    RAISE EXCEPTION 'You cannot synchronize another station''s product.';
  END IF;
  SELECT price_per_gallon INTO v_price FROM public.owner_settings WHERE owner_id = p_owner_id;
  IF v_price IS NULL OR v_price <= 0 THEN RETURN NULL; END IF;
  SELECT primary_water_type INTO v_water_type FROM public.profiles WHERE id = p_owner_id;
  v_water_type := COALESCE(NULLIF(trim(v_water_type), ''), 'Purified Water');
  IF lower(v_water_type) LIKE '%alkaline%' THEN v_category := 'Alkaline'; v_name := 'Alkaline Water';
  ELSIF lower(v_water_type) LIKE '%mineral%' THEN v_category := 'Mineral'; v_name := 'Mineral Water';
  ELSE v_category := 'Purified'; v_name := 'Purified Water'; END IF;
  SELECT id INTO v_product_id FROM public.products WHERE owner_id = p_owner_id
    ORDER BY is_available DESC, created_at ASC NULLS LAST LIMIT 1 FOR UPDATE;
  IF v_product_id IS NOT NULL THEN
    UPDATE public.products SET price = v_price, name = v_name, category = v_category, is_available = true
    WHERE id = v_product_id RETURNING * INTO v_row;
    RETURN to_jsonb(v_row);
  END IF;
  INSERT INTO public.products (owner_id, name, description, price, category, is_available)
  VALUES (p_owner_id, v_name, v_name || ' refill service', v_price, v_category, true)
  RETURNING * INTO v_row;
  RETURN to_jsonb(v_row);
END; $$;


ALTER FUNCTION "public"."sync_owner_default_product"("p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."transition_order_status_safely"("p_order_id" "uuid", "p_new_status" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not found');
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();

  IF v_role = 'owner' AND auth.uid() = v_order.owner_id THEN
    IF NOT (
      (v_order.status = 'pending' AND p_new_status IN ('accepted', 'cancelled'))
      OR (v_order.status = 'accepted' AND p_new_status IN ('preparing', 'cancelled'))
      OR (v_order.status = 'preparing' AND p_new_status IN ('ready_for_pickup', 'cancelled'))
    ) THEN
      RAISE EXCEPTION 'Invalid station order status transition.';
    END IF;
  ELSIF v_role = 'rider'
      AND auth.uid() = v_order.assigned_rider_id
      AND v_order.status = 'assigned_to_rider'
      AND p_new_status = 'out_for_delivery' THEN
    NULL;
  ELSIF v_role = 'customer'
      AND auth.uid() = v_order.customer_id
      AND v_order.status = 'pending'
      AND p_new_status = 'cancelled' THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'You are not authorized to make this order status change.';
  END IF;

  UPDATE public.orders
  SET
    status = p_new_status::public.order_status,
    updated_at = now()
  WHERE id = p_order_id;

  -- Lifecycle status notifications for customer
  IF p_new_status = 'accepted' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Order Accepted',
      'The water station accepted your refill order and is preparing to refill.',
      jsonb_build_object('order_id', p_order_id, 'status', 'accepted')
    );
  ELSIF p_new_status = 'preparing' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'normal', 'Refill in Preparation',
      'Your water containers are now being refilled and inspected.',
      jsonb_build_object('order_id', p_order_id, 'status', 'preparing')
    );
  ELSIF p_new_status = 'ready_for_pickup' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'normal', 'Refill Ready for Dispatch',
      'Your containers are refilled and ready for rider pickup.',
      jsonb_build_object('order_id', p_order_id, 'status', 'ready_for_pickup')
    );
  ELSIF p_new_status = 'out_for_delivery' THEN
    INSERT INTO public.system_notifications (
      user_id, type, priority, title, content, metadata
    ) VALUES (
      v_order.customer_id, 'system_alert', 'high', 'Out for Delivery',
      'Your rider picked up your refill and is heading to your address.',
      jsonb_build_object('order_id', p_order_id, 'status', 'out_for_delivery')
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'Order status updated successfully');
END;
$$;


ALTER FUNCTION "public"."transition_order_status_safely"("p_order_id" "uuid", "p_new_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_sync_owner_default_product"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.price_per_gallon IS NOT NULL AND NEW.price_per_gallon > 0 THEN
    PERFORM public.sync_owner_default_product(NEW.owner_id);
  END IF;
  RETURN NEW;
END; $$;


ALTER FUNCTION "public"."trigger_sync_owner_default_product"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_chat_room_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    new.updated_at = now();
    return new;
end;
$$;


ALTER FUNCTION "public"."update_chat_room_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_last_read"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    update public.chat_participants
    set last_read_at = now()
    where room_id = new.room_id
    and user_id = auth.uid();
    
    return new;
end;
$$;


ALTER FUNCTION "public"."update_last_read"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_message_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    new.updated_at = now();
    return new;
end;
$$;


ALTER FUNCTION "public"."update_message_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_quick_reply_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    new.updated_at = now();
    return new;
end;
$$;


ALTER FUNCTION "public"."update_quick_reply_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_room_on_new_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
    update public.chat_rooms
    set updated_at = now()
    where id = new.room_id;
    
    return new;
end;
$$;


ALTER FUNCTION "public"."update_room_on_new_message"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_station_stats"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE public.profiles
  SET
    average_rating = (
      SELECT COALESCE(AVG(rating), 0)
      FROM public.reviews
      WHERE station_id = NEW.station_id
    ),
    review_count = (
      SELECT COUNT(*)
      FROM public.reviews
      WHERE station_id = NEW.station_id
    )
  WHERE id = NEW.station_id;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_station_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."user_is_room_participant"("p_room_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return exists (
        select 1 from public.chat_participants
        where room_id = p_room_id
        and user_id = auth.uid()
    );
end;
$$;


ALTER FUNCTION "public"."user_is_room_participant"("p_room_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "actor_id" "uuid",
    "action" "text" NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "text" NOT NULL,
    "old_value" "jsonb",
    "new_value" "jsonb",
    "metadata" "jsonb"
);


ALTER TABLE "public"."audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_participants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "room_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role_in_room" "public"."participant_role" DEFAULT 'customer'::"public"."participant_role" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"(),
    "last_read_at" timestamp with time zone,
    "is_muted" boolean DEFAULT false,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb"
);


ALTER TABLE "public"."chat_participants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_rooms" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "room_type" "public"."chat_room_type" DEFAULT 'customer_support'::"public"."chat_room_type" NOT NULL,
    "reference_id" "uuid",
    "status" "public"."chat_room_status" DEFAULT 'active'::"public"."chat_room_status" NOT NULL,
    "owner_id" "uuid",
    "title" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "archived_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb"
);


ALTER TABLE "public"."chat_rooms" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_addresses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "label" "text" DEFAULT 'Home'::"text" NOT NULL,
    "complete_address" "text" NOT NULL,
    "barangay" "text",
    "town" "text",
    "landmark" "text",
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."customer_addresses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_payment_methods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "label" "text" NOT NULL,
    "masked_value" "text" NOT NULL,
    "gateway_payment_method_id" "text",
    "card_brand" "text",
    "card_last4" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."customer_payment_methods" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid",
    "owner_id" "uuid",
    "rider_id" "uuid",
    "water_type" "text",
    "container_type" "text",
    "quantity" integer DEFAULT 1,
    "total_price" numeric,
    "status" "public"."order_status" DEFAULT 'pending'::"public"."order_status",
    "delivery_lat" double precision,
    "delivery_lng" double precision,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "delivery_fee" numeric(10,2) DEFAULT 0 NOT NULL,
    "payment_method" "text" DEFAULT 'cod'::"text" NOT NULL,
    "payment_proof_url" "text",
    "assigned_rider_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "station_name" "text",
    "items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "subtotal" numeric(10,2) DEFAULT 0 NOT NULL,
    "total_amount" numeric(10,2) DEFAULT 0 NOT NULL,
    "customer_name" "text",
    "customer_phone" "text",
    "customer_address" "text",
    "customer_barangay" "text",
    "customer_landmark" "text",
    "customer_municipality" "text",
    "idempotency_key" "uuid",
    "delivery_latitude" double precision,
    "delivery_longitude" double precision,
    "delivery_photo_url" "text",
    "delivery_signature_url" "text",
    "actual_completion_at" timestamp with time zone,
    "payment_status" "public"."payment_status" DEFAULT 'pending'::"public"."payment_status",
    "payment_error" "text",
    "retry_allowed" boolean DEFAULT true,
    "region_id" "uuid",
    "notes" "text",
    "empty_gallons_returned" integer DEFAULT 0 NOT NULL,
    "payment_checkout_id" "text",
    "payment_checkout_url" "text",
    "platform_fee" numeric(10,2) DEFAULT 0 NOT NULL,
    CONSTRAINT "empty_gallons_returned_non_negative" CHECK (("empty_gallons_returned" >= 0)),
    CONSTRAINT "orders_container_type_check" CHECK (("container_type" = ANY (ARRAY['Slim'::"text", 'Round'::"text"]))),
    CONSTRAINT "orders_payment_method_check" CHECK (("payment_method" = ANY (ARRAY['cod'::"text", 'gcash'::"text", 'maya'::"text", 'card'::"text"]))),
    CONSTRAINT "orders_water_type_check" CHECK (("water_type" = ANY (ARRAY['Refill'::"text", 'New Container'::"text"])))
);

ALTER TABLE ONLY "public"."orders" REPLICA IDENTITY FULL;


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."dispatch_urgency_queue" AS
 SELECT "id" AS "order_id",
    "status",
    "station_name",
    "customer_name",
    "customer_barangay",
    "owner_id",
    "created_at",
    ("now"() - "created_at") AS "elapsed_time",
        CASE
            WHEN (("status" = 'pending'::"public"."order_status") AND (("now"() - "created_at") > '00:10:00'::interval)) THEN 3
            WHEN (("status" = 'preparing'::"public"."order_status") AND (("now"() - "created_at") > '00:20:00'::interval)) THEN 2
            ELSE 1
        END AS "urgency_level",
        CASE
            WHEN ("status" = 'pending'::"public"."order_status") THEN 'BREACH_IMMINENT'::"text"
            ELSE 'STABLE'::"text"
        END AS "sla_status"
   FROM "public"."orders" "o"
  WHERE ("status" <> ALL (ARRAY['delivered'::"public"."order_status", 'cancelled'::"public"."order_status", 'out_for_delivery'::"public"."order_status"]))
  ORDER BY
        CASE
            WHEN (("status" = 'pending'::"public"."order_status") AND (("now"() - "created_at") > '00:10:00'::interval)) THEN 3
            WHEN (("status" = 'preparing'::"public"."order_status") AND (("now"() - "created_at") > '00:20:00'::interval)) THEN 2
            ELSE 1
        END DESC, "created_at";


ALTER VIEW "public"."dispatch_urgency_queue" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."disputes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "reporter_id" "uuid" NOT NULL,
    "reason" "text" NOT NULL,
    "description" "text",
    "status" "public"."dispute_status" DEFAULT 'open'::"public"."dispute_status",
    "evidence_url" "text",
    "resolution_notes" "text",
    "resolved_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."disputes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_credits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid",
    "rider_id" "uuid",
    "delivery_id" "uuid",
    "credit_type" "text" NOT NULL,
    "debtor_name" "text" NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "paid_amount" numeric(10,2) DEFAULT 0,
    "remaining" numeric(10,2) GENERATED ALWAYS AS (("amount" - "paid_amount")) STORED,
    "is_paid" boolean DEFAULT false,
    "payment_date" "date",
    "notes" "text",
    "is_synced" boolean DEFAULT false,
    "local_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "dm_credits_credit_type_check" CHECK (("credit_type" = ANY (ARRAY['customer'::"text", 'rider'::"text"])))
);


ALTER TABLE "public"."dm_credits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_deliveries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid",
    "rider_id" "uuid",
    "delivery_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "gallons" numeric(8,2) NOT NULL,
    "price_per_gallon" numeric(8,2) NOT NULL,
    "expenses" numeric(8,2) DEFAULT 0,
    "notes" "text",
    "empty_gallons_returned" numeric(8,2) DEFAULT 0,
    "income" numeric(10,2) GENERATED ALWAYS AS (("gallons" * "price_per_gallon")) STORED,
    "commission" numeric(10,2),
    "owner_profit" numeric(10,2),
    "credit_amount" numeric(10,2) DEFAULT 0,
    "is_synced" boolean DEFAULT false,
    "local_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."dm_deliveries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_inventory" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid",
    "transaction_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "transaction_type" "text" NOT NULL,
    "gallons" numeric(8,2) NOT NULL,
    "notes" "text",
    "delivery_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "dm_inventory_transaction_type_check" CHECK (("transaction_type" = ANY (ARRAY['load'::"text", 'deduct'::"text", 'adjustment'::"text"])))
);


ALTER TABLE "public"."dm_inventory" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_riders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid",
    "linked_user_id" "uuid",
    "full_name" "text" NOT NULL,
    "phone" "text",
    "email" "text",
    "commission_per_gallon" numeric(8,2) DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."dm_riders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."domain_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_type" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "actor_id" "uuid",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."domain_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expenses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "category" "text",
    "amount" numeric(10,2) NOT NULL,
    "description" "text",
    "expense_date" "date" DEFAULT CURRENT_DATE,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "expenses_category_check" CHECK (("category" = ANY (ARRAY['Fuel'::"text", 'Electricity'::"text", 'Maintenance'::"text", 'Labor'::"text", 'Others'::"text"])))
);


ALTER TABLE "public"."expenses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."favorites" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "station_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."favorites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ledger_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "order_id" "uuid",
    "amount" numeric(12,2) NOT NULL,
    "entry_type" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb"
);


ALTER TABLE "public"."ledger_entries" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."integrity_violations" AS
 SELECT "orders"."id" AS "order_id",
    "orders"."status",
    "orders"."owner_id",
    'ORPHANED_DELIVERY'::"text" AS "violation_type",
    'Order marked EN ROUTE but has no assigned rider.'::"text" AS "description"
   FROM "public"."orders"
  WHERE (("orders"."status" = 'out_for_delivery'::"public"."order_status") AND ("orders"."assigned_rider_id" IS NULL))
UNION ALL
 SELECT "o"."id" AS "order_id",
    "o"."status",
    "o"."owner_id",
    'MISSING_LEDGER_ENTRY'::"text" AS "violation_type",
    'Order DELIVERED but no final financial entry found.'::"text" AS "description"
   FROM ("public"."orders" "o"
     LEFT JOIN "public"."ledger_entries" "l" ON (("l"."order_id" = "o"."id")))
  WHERE (("o"."status" = 'delivered'::"public"."order_status") AND ("l"."id" IS NULL));


ALTER VIEW "public"."integrity_violations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "change_amount" integer NOT NULL,
    "reason" "text",
    "actor_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."inventory_ledger" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "room_id" "uuid" NOT NULL,
    "sender_id" "uuid",
    "content" "text" NOT NULL,
    "message_type" "public"."message_type" DEFAULT 'text'::"public"."message_type" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "is_read" boolean DEFAULT false,
    "read_by" "jsonb" DEFAULT '[]'::"jsonb",
    "reply_to" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "deleted_at" timestamp with time zone,
    "status" "public"."message_status" DEFAULT 'sent'::"public"."message_status",
    "retry_count" integer DEFAULT 0,
    "error_message" "text",
    "is_sms_fallback_triggered" boolean DEFAULT false
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."operational_metrics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "station_id" "uuid",
    "metric_name" "text" NOT NULL,
    "metric_value" numeric(12,4) NOT NULL,
    "snapshot_time" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."operational_metrics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid",
    "product_name" "text" NOT NULL,
    "quantity" integer NOT NULL,
    "price_at_purchase" numeric(10,2) NOT NULL,
    "product_id" "uuid",
    "subtotal" numeric(10,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."order_items" REPLICA IDENTITY FULL;


ALTER TABLE "public"."order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."owner_inventory_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "tx_type" "text" NOT NULL,
    "gallons" integer NOT NULL,
    "product_id" "uuid",
    "order_id" "uuid",
    "notes" "text",
    "actor_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "owner_inventory_ledger_gallons_check" CHECK (("gallons" <> 0)),
    CONSTRAINT "owner_inventory_ledger_tx_type_check" CHECK (("tx_type" = ANY (ARRAY['load_filled'::"text", 'adjust_filled'::"text", 'load_empty'::"text", 'adjust_empty'::"text", 'empty_return'::"text"])))
);

ALTER TABLE ONLY "public"."owner_inventory_ledger" REPLICA IDENTITY FULL;


ALTER TABLE "public"."owner_inventory_ledger" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."owner_payout_accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "label" "text" NOT NULL,
    "masked_value" "text" NOT NULL,
    "encrypted_account_ref" "text",
    "provider_name" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."owner_payout_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."owner_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "base_delivery_fee" double precision DEFAULT 25.0,
    "price_per_gallon" double precision DEFAULT 15.0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "service_radius_km" double precision DEFAULT 10.0,
    "max_concurrent_orders" integer DEFAULT 20,
    "empty_gallons_stock" integer DEFAULT 0 NOT NULL,
    "enabled_payment_methods" "text"[] DEFAULT ARRAY['cod'::"text", 'gcash'::"text", 'maya'::"text", 'card'::"text"] NOT NULL,
    CONSTRAINT "empty_gallons_stock_non_negative" CHECK (("empty_gallons_stock" >= 0))
);

ALTER TABLE ONLY "public"."owner_settings" REPLICA IDENTITY FULL;


ALTER TABLE "public"."owner_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payment_checkouts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "provider" "text" DEFAULT 'paymongo'::"text" NOT NULL,
    "payment_method" "text" NOT NULL,
    "provider_checkout_id" "text",
    "checkout_url" "text",
    "amount" numeric(10,2) NOT NULL,
    "currency" "text" DEFAULT 'PHP'::"text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "raw_response" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "payment_checkouts_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "payment_checkouts_payment_method_check" CHECK (("payment_method" = ANY (ARRAY['gcash'::"text", 'maya'::"text", 'card'::"text"])))
);


ALTER TABLE "public"."payment_checkouts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payment_webhook_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "checkout_id" "uuid",
    "order_id" "uuid",
    "customer_id" "uuid",
    "owner_id" "uuid",
    "provider" "text" DEFAULT 'paymongo'::"text" NOT NULL,
    "provider_checkout_id" "text" DEFAULT ''::"text" NOT NULL,
    "event_type" "text" DEFAULT ''::"text" NOT NULL,
    "provider_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "processing_status" "text" DEFAULT 'received'::"text" NOT NULL,
    "error_message" "text",
    "raw_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    "provider_event_id" "text",
    CONSTRAINT "payment_webhook_events_processing_status_check" CHECK (("processing_status" = ANY (ARRAY['received'::"text", 'processed'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."payment_webhook_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "price" numeric(10,2) NOT NULL,
    "image_url" "text",
    "category" "text",
    "is_available" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "stock_level" integer DEFAULT 100,
    "low_stock_threshold" integer DEFAULT 10,
    "preparation_minutes" integer DEFAULT 15 NOT NULL,
    "container_size" "text" DEFAULT '5 gallon'::"text" NOT NULL,
    CONSTRAINT "products_category_check" CHECK (("category" = ANY (ARRAY['Purified'::"text", 'Mineral'::"text", 'Alkaline'::"text", 'Refill'::"text", 'Products'::"text", 'Accessories'::"text"]))),
    CONSTRAINT "stock_non_negative" CHECK (("stock_level" >= 0))
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "username" "text",
    "full_name" "text",
    "role" "public"."user_role" DEFAULT 'customer'::"public"."user_role",
    "town" "public"."municipality",
    "owner_id" "uuid",
    "phone" "text",
    "station_name" "text",
    "barangay" "text",
    "complete_address" "text",
    "landmark" "text",
    "lat" double precision,
    "lng" double precision,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "email" "text",
    "average_rating" numeric(3,2) DEFAULT 0.00,
    "review_count" integer DEFAULT 0,
    "is_open" boolean DEFAULT true,
    "station_description" "text",
    "station_logo_url" "text",
    "commission_rate" numeric(10,2) DEFAULT 5.00,
    "primary_water_type" "public"."water_type_option",
    "station_photo_url" "text",
    "bio_description" "text",
    "price_per_gallon" numeric(10,2) DEFAULT 25.00,
    "water_type" "public"."primary_water_type",
    "owner_phone" "text",
    "vehicle_type" "text",
    "license_number" "text",
    "avatar_url" "text",
    "first_name" "text",
    "last_name" "text",
    "mi" "text",
    "suffix" "text",
    "latitude" double precision,
    "longitude" double precision,
    "is_online" boolean DEFAULT true,
    "station_id" "uuid",
    "reliability_score" numeric(3,2) DEFAULT 5.00,
    "total_deliveries" integer DEFAULT 0,
    "flagged_count" integer DEFAULT 0,
    "region_id" "uuid",
    "purok" "text",
    "zip_code" "text",
    "preferred_water_type" "text",
    "station_availability" "text" DEFAULT 'open'::"text" NOT NULL,
    "is_suspended" boolean DEFAULT false NOT NULL,
    "suspended_at" timestamp with time zone,
    "suspended_reason" "text",
    "admin_tier" "text",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"())
);

ALTER TABLE ONLY "public"."profiles" REPLICA IDENTITY FULL;


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."purok" IS 'Selected purok for customer delivery address.';



COMMENT ON COLUMN "public"."profiles"."zip_code" IS 'Postal code based on selected municipality.';



COMMENT ON COLUMN "public"."profiles"."preferred_water_type" IS 'Customer preferred water type at registration (Purified, Mineral, Alkaline).';



COMMENT ON COLUMN "public"."profiles"."admin_tier" IS 'For role=admin: super (full) or support (read + limited writes). NULL treated as super.';



CREATE TABLE IF NOT EXISTS "public"."quick_replies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rider_id" "uuid",
    "label" "text" NOT NULL,
    "message_text" "text" NOT NULL,
    "sort_order" integer DEFAULT 0,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."quick_replies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rate_limit_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_id" "uuid",
    "action" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rate_limit_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."regions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "code" "text" NOT NULL,
    "base_delivery_fee" numeric(10,2) DEFAULT 15.00,
    "sla_goal_mins" integer DEFAULT 45,
    "is_active" boolean DEFAULT true,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."regions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."remittances" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rider_id" "uuid",
    "owner_id" "uuid",
    "customer_name" "text",
    "gallons_delivered" integer DEFAULT 0,
    "empty_returned" integer DEFAULT 0,
    "cash_collected" numeric DEFAULT 0,
    "is_credit" boolean DEFAULT false,
    "credit_amount" numeric DEFAULT 0,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_settled" boolean DEFAULT false,
    "settled_at" timestamp with time zone
);


ALTER TABLE "public"."remittances" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "station_id" "uuid",
    "customer_id" "uuid",
    "order_id" "uuid",
    "rating" integer,
    "comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "reviews_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."reviews" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rider_earnings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rider_id" "uuid" NOT NULL,
    "order_id" "uuid" NOT NULL,
    "amount_earned" numeric(10,2) NOT NULL,
    "is_paid_out" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rider_earnings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rider_locations" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "rider_id" "uuid" NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "heading" double precision,
    "speed" double precision,
    "timestamp" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."rider_locations" REPLICA IDENTITY FULL;


ALTER TABLE "public"."rider_locations" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."sla_violations" AS
 SELECT "id" AS "order_id",
    "status",
    "owner_id",
    "created_at",
    ("now"() - "created_at") AS "duration_since_creation",
        CASE
            WHEN (("status" = 'pending'::"public"."order_status") AND (("now"() - "created_at") > '00:15:00'::interval)) THEN 'STUCK_PENDING_15M'::"text"
            WHEN (("status" = 'preparing'::"public"."order_status") AND (("now"() - "created_at") > '00:30:00'::interval)) THEN 'STUCK_PREPARING_30M'::"text"
            WHEN (("status" = 'out_for_delivery'::"public"."order_status") AND (("now"() - "created_at") > '01:00:00'::interval)) THEN 'SLOW_DELIVERY_1H'::"text"
            ELSE 'NONE'::"text"
        END AS "violation_type"
   FROM "public"."orders" "o"
  WHERE (("status" <> 'delivered'::"public"."order_status") AND ("status" <> 'cancelled'::"public"."order_status") AND ((("status" = 'pending'::"public"."order_status") AND (("now"() - "created_at") > '00:15:00'::interval)) OR (("status" = 'preparing'::"public"."order_status") AND (("now"() - "created_at") > '00:30:00'::interval)) OR (("status" = 'out_for_delivery'::"public"."order_status") AND (("now"() - "created_at") > '01:00:00'::interval))));


ALTER VIEW "public"."sla_violations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity" integer DEFAULT 1,
    "frequency" "public"."schedule_frequency" NOT NULL,
    "delivery_days" integer[] DEFAULT '{}'::integer[],
    "next_delivery_date" "date",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."suspicious_activities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rider_id" "uuid" NOT NULL,
    "order_id" "uuid",
    "activity_type" "text" NOT NULL,
    "severity" "text" DEFAULT 'MEDIUM'::"text",
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."suspicious_activities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "value" "jsonb" NOT NULL,
    "description" "text",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."system_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "type" "public"."notification_type" DEFAULT 'system_alert'::"public"."notification_type" NOT NULL,
    "priority" "public"."notification_priority" DEFAULT 'normal'::"public"."notification_priority" NOT NULL,
    "title" "text" NOT NULL,
    "content" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "is_read" boolean DEFAULT false,
    "read_at" timestamp with time zone,
    "action_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "expires_at" timestamp with time zone
);


ALTER TABLE "public"."system_notifications" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_barangay_demand_heatmap" AS
 SELECT "owner_id",
    "customer_barangay" AS "barangay",
    "count"(*) AS "total_orders",
    "sum"("total_amount") AS "total_revenue"
   FROM "public"."orders"
  WHERE ("status" = 'delivered'::"public"."order_status")
  GROUP BY "owner_id", "customer_barangay"
  ORDER BY ("count"(*)) DESC;


ALTER VIEW "public"."v_barangay_demand_heatmap" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_rider_performance_leaderboard" AS
 SELECT "p"."id" AS "rider_id",
    "p"."full_name",
    "p"."owner_id" AS "station_id",
    "count"("o"."id") AS "deliveries_completed",
    COALESCE("p"."reliability_score", 5.0) AS "rating",
    COALESCE("p"."flagged_count", 0) AS "behavioral_flags",
    COALESCE("avg"((EXTRACT(epoch FROM ("o"."actual_completion_at" - "o"."created_at")) / (60)::numeric)), (0)::numeric) AS "avg_delivery_time_mins"
   FROM ("public"."profiles" "p"
     LEFT JOIN "public"."orders" "o" ON ((("o"."assigned_rider_id" = "p"."id") AND ("o"."status" = 'delivered'::"public"."order_status"))))
  WHERE ("p"."role" = 'rider'::"public"."user_role")
  GROUP BY "p"."id", "p"."full_name", "p"."owner_id", "p"."reliability_score", "p"."flagged_count";


ALTER VIEW "public"."v_rider_performance_leaderboard" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_tax_reconciliation" AS
 SELECT "owner_id",
    "to_char"("created_at", 'YYYY-MM'::"text") AS "report_month",
    "count"(*) AS "total_orders",
    "sum"("total_amount") AS "total_gross_revenue",
    "sum"("subtotal") AS "net_revenue",
    "sum"(("total_amount" - "subtotal")) AS "total_fees_and_tax",
    "round"(("sum"("subtotal") * 0.12), 2) AS "estimated_vat"
   FROM "public"."orders"
  WHERE ("status" = 'delivered'::"public"."order_status")
  GROUP BY "owner_id", ("to_char"("created_at", 'YYYY-MM'::"text"))
  ORDER BY ("to_char"("created_at", 'YYYY-MM'::"text")) DESC;


ALTER VIEW "public"."v_tax_reconciliation" OWNER TO "postgres";


ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_participants"
    ADD CONSTRAINT "chat_participants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_rooms"
    ADD CONSTRAINT "chat_rooms_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_addresses"
    ADD CONSTRAINT "customer_addresses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_payment_methods"
    ADD CONSTRAINT "customer_payment_methods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dm_credits"
    ADD CONSTRAINT "dm_credits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dm_deliveries"
    ADD CONSTRAINT "dm_deliveries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dm_inventory"
    ADD CONSTRAINT "dm_inventory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dm_riders"
    ADD CONSTRAINT "dm_riders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."domain_events"
    ADD CONSTRAINT "domain_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_user_id_station_id_key" UNIQUE ("user_id", "station_id");



ALTER TABLE ONLY "public"."inventory_ledger"
    ADD CONSTRAINT "inventory_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ledger_entries"
    ADD CONSTRAINT "ledger_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."operational_metrics"
    ADD CONSTRAINT "operational_metrics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."owner_inventory_ledger"
    ADD CONSTRAINT "owner_inventory_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."owner_payout_accounts"
    ADD CONSTRAINT "owner_payout_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."owner_settings"
    ADD CONSTRAINT "owner_settings_owner_id_key" UNIQUE ("owner_id");



ALTER TABLE ONLY "public"."owner_settings"
    ADD CONSTRAINT "owner_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payment_checkouts"
    ADD CONSTRAINT "payment_checkouts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payment_checkouts"
    ADD CONSTRAINT "payment_checkouts_provider_checkout_id_key" UNIQUE ("provider_checkout_id");



ALTER TABLE ONLY "public"."payment_webhook_events"
    ADD CONSTRAINT "payment_webhook_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."quick_replies"
    ADD CONSTRAINT "quick_replies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rate_limit_events"
    ADD CONSTRAINT "rate_limit_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."regions"
    ADD CONSTRAINT "regions_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."regions"
    ADD CONSTRAINT "regions_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."regions"
    ADD CONSTRAINT "regions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."remittances"
    ADD CONSTRAINT "remittances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_order_unique" UNIQUE ("order_id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rider_earnings"
    ADD CONSTRAINT "rider_earnings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rider_locations"
    ADD CONSTRAINT "rider_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suspicious_activities"
    ADD CONSTRAINT "suspicious_activities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_config"
    ADD CONSTRAINT "system_config_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."system_config"
    ADD CONSTRAINT "system_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_notifications"
    ADD CONSTRAINT "system_notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "unique_customer_idempotency" UNIQUE ("customer_id", "idempotency_key");



CREATE INDEX "customer_addresses_customer_idx" ON "public"."customer_addresses" USING "btree" ("customer_id", "is_default" DESC, "created_at" DESC);



CREATE INDEX "idx_chat_participants_composite" ON "public"."chat_participants" USING "btree" ("room_id", "user_id");



CREATE INDEX "idx_chat_participants_room_id" ON "public"."chat_participants" USING "btree" ("room_id");



CREATE INDEX "idx_chat_participants_user_id" ON "public"."chat_participants" USING "btree" ("user_id");



CREATE INDEX "idx_chat_rooms_owner_id" ON "public"."chat_rooms" USING "btree" ("owner_id");



CREATE INDEX "idx_chat_rooms_reference_id" ON "public"."chat_rooms" USING "btree" ("reference_id");



CREATE INDEX "idx_chat_rooms_status" ON "public"."chat_rooms" USING "btree" ("status");



CREATE INDEX "idx_chat_rooms_type" ON "public"."chat_rooms" USING "btree" ("room_type");



CREATE INDEX "idx_chat_rooms_updated_at" ON "public"."chat_rooms" USING "btree" ("updated_at" DESC);



CREATE UNIQUE INDEX "idx_customer_payment_methods_one_default" ON "public"."customer_payment_methods" USING "btree" ("customer_id") WHERE "is_default";



CREATE INDEX "idx_domain_events_created" ON "public"."domain_events" USING "btree" ("created_at");



CREATE INDEX "idx_domain_events_type" ON "public"."domain_events" USING "btree" ("event_type");



CREATE INDEX "idx_messages_created_at" ON "public"."messages" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_messages_room_created" ON "public"."messages" USING "btree" ("room_id", "created_at" DESC);



CREATE INDEX "idx_messages_room_id" ON "public"."messages" USING "btree" ("room_id");



CREATE INDEX "idx_messages_sender_id" ON "public"."messages" USING "btree" ("sender_id");



CREATE INDEX "idx_messages_unread" ON "public"."messages" USING "btree" ("room_id", "is_read") WHERE ("is_read" = false);



CREATE INDEX "idx_order_items_order_id" ON "public"."order_items" USING "btree" ("order_id");



CREATE INDEX "idx_orders_customer_created" ON "public"."orders" USING "btree" ("customer_id", "created_at" DESC);



CREATE UNIQUE INDEX "idx_orders_idempotency_key" ON "public"."orders" USING "btree" ("idempotency_key") WHERE ("idempotency_key" IS NOT NULL);



CREATE INDEX "idx_orders_owner_status_created" ON "public"."orders" USING "btree" ("owner_id", "status", "created_at" DESC);



CREATE INDEX "idx_orders_rider_status_created" ON "public"."orders" USING "btree" ("assigned_rider_id", "status", "created_at" DESC);



CREATE INDEX "idx_owner_inventory_ledger_owner_created" ON "public"."owner_inventory_ledger" USING "btree" ("owner_id", "created_at" DESC);



CREATE UNIQUE INDEX "idx_owner_payout_accounts_one_default" ON "public"."owner_payout_accounts" USING "btree" ("owner_id") WHERE "is_default";



CREATE INDEX "idx_payment_checkouts_order_id" ON "public"."payment_checkouts" USING "btree" ("order_id");



CREATE INDEX "idx_payment_checkouts_provider_id" ON "public"."payment_checkouts" USING "btree" ("provider_checkout_id");



CREATE INDEX "idx_payment_webhook_events_order" ON "public"."payment_webhook_events" USING "btree" ("order_id");



CREATE INDEX "idx_payment_webhook_events_owner_failure" ON "public"."payment_webhook_events" USING "btree" ("owner_id", "processing_status", "created_at" DESC);



CREATE INDEX "idx_payment_webhook_events_provider_checkout" ON "public"."payment_webhook_events" USING "btree" ("provider_checkout_id", "created_at" DESC);



CREATE INDEX "idx_payment_webhook_events_provider_event" ON "public"."payment_webhook_events" USING "btree" ("provider_event_id");



CREATE INDEX "idx_products_owner_available" ON "public"."products" USING "btree" ("owner_id", "is_available");



CREATE INDEX "idx_quick_replies_rider_id" ON "public"."quick_replies" USING "btree" ("rider_id");



CREATE INDEX "idx_quick_replies_sort_order" ON "public"."quick_replies" USING "btree" ("sort_order");



CREATE INDEX "idx_system_notifications_created_at" ON "public"."system_notifications" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_system_notifications_type" ON "public"."system_notifications" USING "btree" ("type");



CREATE INDEX "idx_system_notifications_unread" ON "public"."system_notifications" USING "btree" ("user_id", "is_read") WHERE ("is_read" = false);



CREATE INDEX "idx_system_notifications_user_id" ON "public"."system_notifications" USING "btree" ("user_id");



CREATE UNIQUE INDEX "idx_unique_participant" ON "public"."chat_participants" USING "btree" ("room_id", "user_id");



CREATE INDEX "profiles_email_idx" ON "public"."profiles" USING "btree" ("email");



CREATE UNIQUE INDEX "profiles_username_unique_idx" ON "public"."profiles" USING "btree" ("username");



CREATE INDEX "rider_locations_rider_id_idx" ON "public"."rider_locations" USING "btree" ("rider_id");



CREATE INDEX "rider_locations_timestamp_idx" ON "public"."rider_locations" USING "btree" ("timestamp" DESC);



CREATE OR REPLACE TRIGGER "on_chat_room_add_participants" AFTER INSERT ON "public"."chat_rooms" FOR EACH ROW EXECUTE FUNCTION "public"."auto_add_order_chat_participants"();



CREATE OR REPLACE TRIGGER "on_chat_room_updated" BEFORE UPDATE ON "public"."chat_rooms" FOR EACH ROW EXECUTE FUNCTION "public"."update_chat_room_timestamp"();



CREATE OR REPLACE TRIGGER "on_message_update_room" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."update_room_on_new_message"();



CREATE OR REPLACE TRIGGER "on_message_updated" BEFORE UPDATE ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."update_message_timestamp"();



CREATE OR REPLACE TRIGGER "on_order_assign_notify_rider" AFTER UPDATE ON "public"."orders" FOR EACH ROW WHEN (("new"."assigned_rider_id" IS DISTINCT FROM "old"."assigned_rider_id")) EXECUTE FUNCTION "public"."notify_rider_order_assigned"();



CREATE OR REPLACE TRIGGER "on_order_delivered_archive_chat" AFTER UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."archive_order_chat_on_delivery"();



CREATE OR REPLACE TRIGGER "on_order_item_added" AFTER INSERT ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."handle_inventory_deduction"();



CREATE OR REPLACE TRIGGER "on_order_status_update" BEFORE UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_order_status_logic"();



CREATE OR REPLACE TRIGGER "on_quick_reply_updated" BEFORE UPDATE ON "public"."quick_replies" FOR EACH ROW EXECUTE FUNCTION "public"."update_quick_reply_timestamp"();



CREATE OR REPLACE TRIGGER "on_review_added" AFTER INSERT ON "public"."reviews" FOR EACH ROW EXECUTE FUNCTION "public"."update_station_stats"();



CREATE OR REPLACE TRIGGER "on_rider_create_quick_replies" AFTER INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."create_default_quick_replies"();



CREATE OR REPLACE TRIGGER "trg_analyze_rider_behavior" AFTER UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."proc_analyze_rider_behavior"();



CREATE OR REPLACE TRIGGER "trg_disputes_update_at" BEFORE UPDATE ON "public"."disputes" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_finalize_order_finances" AFTER UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."proc_finalize_order_finances"();



CREATE OR REPLACE TRIGGER "trg_guard_profile_role_changes" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."guard_profile_role_changes"();



CREATE OR REPLACE TRIGGER "trg_guard_system_message_spoofing" BEFORE INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."guard_system_message_spoofing"();



CREATE OR REPLACE TRIGGER "trg_inventory_ledger_logging" AFTER INSERT ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."proc_log_inventory_event"();



CREATE OR REPLACE TRIGGER "trg_log_dispute_event" AFTER INSERT ON "public"."disputes" FOR EACH ROW EXECUTE FUNCTION "public"."proc_log_dispute_event"();



CREATE OR REPLACE TRIGGER "trg_restore_inventory_on_cancellation" BEFORE UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."proc_restore_inventory_on_cancellation"();



CREATE OR REPLACE TRIGGER "trg_sync_order_chat_participants" AFTER UPDATE OF "assigned_rider_id" ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."proc_sync_order_chat_participants"();



CREATE OR REPLACE TRIGGER "trg_sync_owner_default_product" AFTER INSERT OR UPDATE OF "price_per_gallon" ON "public"."owner_settings" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_sync_owner_default_product"();



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."chat_participants"
    ADD CONSTRAINT "chat_participants_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."chat_rooms"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_participants"
    ADD CONSTRAINT "chat_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_participants"
    ADD CONSTRAINT "chat_participants_user_id_profiles_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_rooms"
    ADD CONSTRAINT "chat_rooms_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_addresses"
    ADD CONSTRAINT "customer_addresses_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_payment_methods"
    ADD CONSTRAINT "customer_payment_methods_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id");



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."dm_credits"
    ADD CONSTRAINT "dm_credits_delivery_id_fkey" FOREIGN KEY ("delivery_id") REFERENCES "public"."dm_deliveries"("id");



ALTER TABLE ONLY "public"."dm_credits"
    ADD CONSTRAINT "dm_credits_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dm_credits"
    ADD CONSTRAINT "dm_credits_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "public"."dm_riders"("id");



ALTER TABLE ONLY "public"."dm_deliveries"
    ADD CONSTRAINT "dm_deliveries_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dm_deliveries"
    ADD CONSTRAINT "dm_deliveries_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "public"."dm_riders"("id");



ALTER TABLE ONLY "public"."dm_inventory"
    ADD CONSTRAINT "dm_inventory_delivery_id_fkey" FOREIGN KEY ("delivery_id") REFERENCES "public"."dm_deliveries"("id");



ALTER TABLE ONLY "public"."dm_inventory"
    ADD CONSTRAINT "dm_inventory_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dm_riders"
    ADD CONSTRAINT "dm_riders_linked_user_id_fkey" FOREIGN KEY ("linked_user_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."dm_riders"
    ADD CONSTRAINT "dm_riders_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."domain_events"
    ADD CONSTRAINT "domain_events_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_station_id_fkey" FOREIGN KEY ("station_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_ledger"
    ADD CONSTRAINT "inventory_ledger_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."inventory_ledger"
    ADD CONSTRAINT "inventory_ledger_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."ledger_entries"
    ADD CONSTRAINT "ledger_entries_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."ledger_entries"
    ADD CONSTRAINT "ledger_entries_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_reply_to_fkey" FOREIGN KEY ("reply_to") REFERENCES "public"."messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."chat_rooms"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."operational_metrics"
    ADD CONSTRAINT "operational_metrics_station_id_fkey" FOREIGN KEY ("station_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_assigned_rider_id_fkey" FOREIGN KEY ("assigned_rider_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."owner_inventory_ledger"
    ADD CONSTRAINT "owner_inventory_ledger_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."owner_inventory_ledger"
    ADD CONSTRAINT "owner_inventory_ledger_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."owner_inventory_ledger"
    ADD CONSTRAINT "owner_inventory_ledger_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."owner_inventory_ledger"
    ADD CONSTRAINT "owner_inventory_ledger_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."owner_payout_accounts"
    ADD CONSTRAINT "owner_payout_accounts_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."owner_settings"
    ADD CONSTRAINT "owner_settings_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payment_checkouts"
    ADD CONSTRAINT "payment_checkouts_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payment_checkouts"
    ADD CONSTRAINT "payment_checkouts_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payment_checkouts"
    ADD CONSTRAINT "payment_checkouts_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payment_webhook_events"
    ADD CONSTRAINT "payment_webhook_events_checkout_id_fkey" FOREIGN KEY ("checkout_id") REFERENCES "public"."payment_checkouts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payment_webhook_events"
    ADD CONSTRAINT "payment_webhook_events_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payment_webhook_events"
    ADD CONSTRAINT "payment_webhook_events_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payment_webhook_events"
    ADD CONSTRAINT "payment_webhook_events_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id");



ALTER TABLE ONLY "public"."quick_replies"
    ADD CONSTRAINT "quick_replies_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."remittances"
    ADD CONSTRAINT "remittances_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."remittances"
    ADD CONSTRAINT "remittances_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_station_id_fkey" FOREIGN KEY ("station_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rider_earnings"
    ADD CONSTRAINT "rider_earnings_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id");



ALTER TABLE ONLY "public"."rider_earnings"
    ADD CONSTRAINT "rider_earnings_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."rider_locations"
    ADD CONSTRAINT "rider_locations_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."suspicious_activities"
    ADD CONSTRAINT "suspicious_activities_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id");



ALTER TABLE ONLY "public"."suspicious_activities"
    ADD CONSTRAINT "suspicious_activities_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."system_notifications"
    ADD CONSTRAINT "system_notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Admins and service role read webhook events" ON "public"."payment_webhook_events" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'admin'::"public"."user_role")))));



CREATE POLICY "Admins can delete reviews" ON "public"."reviews" FOR DELETE TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can insert notifications" ON "public"."system_notifications" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_admin"());



CREATE POLICY "Admins can manage all products" ON "public"."products" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "Admins can update disputes" ON "public"."disputes" FOR UPDATE TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view all audit logs" ON "public"."audit_logs" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view all disputes" ON "public"."disputes" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view all notifications" ON "public"."system_notifications" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view all orders" ON "public"."orders" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view all payment checkouts" ON "public"."payment_checkouts" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view all payment webhook events" ON "public"."payment_webhook_events" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view all products" ON "public"."products" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view all reviews" ON "public"."reviews" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view inventory ledger" ON "public"."owner_inventory_ledger" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "Admins can view rider locations" ON "public"."rider_locations" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "All users can view reviews for public stations" ON "public"."reviews" FOR SELECT USING (true);



CREATE POLICY "Anyone can append to ledger" ON "public"."inventory_ledger" FOR INSERT WITH CHECK (true);



CREATE POLICY "Authenticated can view ledger" ON "public"."inventory_ledger" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read station pricing" ON "public"."owner_settings" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Customers and owners can read payment checkouts" ON "public"."payment_checkouts" FOR SELECT TO "authenticated" USING ((("customer_id" = "auth"."uid"()) OR ("owner_id" = "auth"."uid"())));



CREATE POLICY "Customers can create orders" ON "public"."orders" FOR INSERT WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can create reviews for their delivered orders" ON "public"."reviews" FOR INSERT WITH CHECK ((("customer_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "reviews"."order_id") AND ("o"."customer_id" = "auth"."uid"()) AND ("o"."status" = 'delivered'::"public"."order_status"))))));



CREATE POLICY "Customers can initiate support chat rooms" ON "public"."chat_rooms" FOR INSERT WITH CHECK ((("room_type" = 'customer_support'::"public"."chat_room_type") AND ("auth"."role"() = 'authenticated'::"text")));



CREATE POLICY "Customers can join support chats they initiate" ON "public"."chat_participants" FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."chat_rooms"
  WHERE (("chat_rooms"."id" = "chat_participants"."room_id") AND ("chat_rooms"."room_type" = 'customer_support'::"public"."chat_room_type")))) AND ("user_id" = "auth"."uid"())));



CREATE POLICY "Customers can view own orders" ON "public"."orders" FOR SELECT USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can view own payment checkouts" ON "public"."payment_checkouts" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can view their own orders" ON "public"."orders" FOR SELECT USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can view their own reviews" ON "public"."reviews" FOR SELECT USING (("customer_id" = "auth"."uid"()));



CREATE POLICY "Customers manage own addresses" ON "public"."customer_addresses" TO "authenticated" USING (("customer_id" = "auth"."uid"())) WITH CHECK (("customer_id" = "auth"."uid"()));



CREATE POLICY "Customers manage their payment methods" ON "public"."customer_payment_methods" TO "authenticated" USING (("customer_id" = "auth"."uid"())) WITH CHECK (("customer_id" = "auth"."uid"()));



CREATE POLICY "Customers view own payment callback events" ON "public"."payment_webhook_events" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Owners can add participants to their rooms" ON "public"."chat_participants" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."chat_rooms" "cr"
  WHERE (("cr"."id" = "chat_participants"."room_id") AND ("cr"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners can create chat rooms" ON "public"."chat_rooms" FOR INSERT WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can create notifications for their riders" ON "public"."system_notifications" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "system_notifications"."user_id") AND ("profiles"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners can delete own products" ON "public"."products" FOR DELETE USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can insert own products" ON "public"."products" FOR INSERT WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can insert their own settings" ON "public"."owner_settings" FOR INSERT WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can join support chats for their station" ON "public"."chat_participants" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."chat_rooms"
  WHERE (("chat_rooms"."id" = "chat_participants"."room_id") AND ("chat_rooms"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners can remove participants from their rooms" ON "public"."chat_participants" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."chat_rooms" "cr"
  WHERE (("cr"."id" = "chat_participants"."room_id") AND ("cr"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners can update chat room status" ON "public"."chat_rooms" FOR UPDATE USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can update disputes for their station" ON "public"."disputes" FOR UPDATE USING (("auth"."uid"() IN ( SELECT "orders"."owner_id"
   FROM "public"."orders"
  WHERE ("orders"."id" = "disputes"."order_id"))));



CREATE POLICY "Owners can update own products" ON "public"."products" FOR UPDATE USING (("auth"."uid"() = "owner_id")) WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can update settlement status" ON "public"."remittances" FOR UPDATE USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can update their orders" ON "public"."orders" FOR UPDATE USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can update their own settings" ON "public"."owner_settings" FOR UPDATE USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can view all chat rooms for their station" ON "public"."chat_rooms" FOR SELECT USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can view messages for their rooms" ON "public"."messages" FOR SELECT USING ((("deleted_at" IS NULL) AND (EXISTS ( SELECT 1
   FROM "public"."chat_rooms" "cr"
  WHERE (("cr"."id" = "messages"."room_id") AND ("cr"."owner_id" = "auth"."uid"()))))));



CREATE POLICY "Owners can view orders for their station" ON "public"."orders" FOR SELECT USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can view participants for their rooms" ON "public"."chat_participants" FOR SELECT USING ("public"."is_room_owner"("room_id", "auth"."uid"()));



CREATE POLICY "Owners can view station payment checkouts" ON "public"."payment_checkouts" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can view their own settings" ON "public"."owner_settings" FOR SELECT USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can view their riders' quick replies" ON "public"."quick_replies" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "quick_replies"."rider_id") AND ("profiles"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners manage own expenses" ON "public"."expenses" USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners manage own products" ON "public"."products" USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners manage station earnings" ON "public"."rider_earnings" USING (("auth"."uid"() = ( SELECT "profiles"."owner_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "rider_earnings"."rider_id"))));



CREATE POLICY "Owners manage station orders" ON "public"."orders" TO "authenticated" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Owners manage their payout accounts" ON "public"."owner_payout_accounts" TO "authenticated" USING (("owner_id" = "auth"."uid"())) WITH CHECK (("owner_id" = "auth"."uid"()));



CREATE POLICY "Owners manage their station data" ON "public"."orders" USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners see their own logs" ON "public"."audit_logs" FOR SELECT USING (("auth"."uid"() IN ( SELECT "profiles"."id"
   FROM "public"."profiles"
  WHERE ("profiles"."role" = 'owner'::"public"."user_role"))));



CREATE POLICY "Owners update own station" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Owners view own inventory ledger" ON "public"."owner_inventory_ledger" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners view station ledger" ON "public"."remittances" FOR SELECT TO "authenticated" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Owners view station payment callback events" ON "public"."payment_webhook_events" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners view their own riders" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Participants can update chat rooms" ON "public"."chat_rooms" FOR UPDATE USING ("public"."sec_def_is_room_participant"("id", "auth"."uid"()));



CREATE POLICY "Products are viewable by everyone" ON "public"."products" FOR SELECT USING (true);



CREATE POLICY "Public can insert into audit_logs" ON "public"."audit_logs" FOR INSERT WITH CHECK (true);



CREATE POLICY "Public can view rider locations" ON "public"."rider_locations" FOR SELECT USING (true);



CREATE POLICY "Public profiles are viewable by everyone for chat" ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "Public profiles are viewable by everyone." ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "Riders can create their own quick replies" ON "public"."quick_replies" FOR INSERT WITH CHECK (("rider_id" = "auth"."uid"()));



CREATE POLICY "Riders can delete their own quick replies" ON "public"."quick_replies" FOR DELETE USING (("rider_id" = "auth"."uid"()));



CREATE POLICY "Riders can update assigned orders" ON "public"."orders" FOR UPDATE USING (("auth"."uid"() = "assigned_rider_id"));



CREATE POLICY "Riders can update own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Riders can update their own location" ON "public"."rider_locations" FOR INSERT WITH CHECK (("auth"."uid"() = "rider_id"));



CREATE POLICY "Riders can update their own quick replies" ON "public"."quick_replies" FOR UPDATE USING (("rider_id" = "auth"."uid"()));



CREATE POLICY "Riders can view assigned orders" ON "public"."orders" FOR SELECT USING (("auth"."uid"() = "assigned_rider_id"));



CREATE POLICY "Riders can view their own quick replies" ON "public"."quick_replies" FOR SELECT USING (("rider_id" = "auth"."uid"()));



CREATE POLICY "Riders see assigned tasks" ON "public"."orders" FOR SELECT USING (("auth"."uid"() = "rider_id"));



CREATE POLICY "Riders view own earnings" ON "public"."rider_earnings" FOR SELECT USING (("auth"."uid"() = "rider_id"));



CREATE POLICY "Service role manages checkouts" ON "public"."payment_checkouts" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "Station owners can view reviews for their station" ON "public"."reviews" FOR SELECT USING (("station_id" = "auth"."uid"()));



CREATE POLICY "System config is viewable by all authenticated users" ON "public"."system_config" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Users can add their own favorites" ON "public"."favorites" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own orders" ON "public"."orders" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Users can delete their own messages" ON "public"."messages" FOR UPDATE USING (("sender_id" = "auth"."uid"())) WITH CHECK (("deleted_at" IS NOT NULL));



CREATE POLICY "Users can delete their own notifications" ON "public"."system_notifications" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can only update their own profile." ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can remove their own favorites" ON "public"."favorites" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can send messages" ON "public"."messages" FOR INSERT WITH CHECK ((("sender_id" = "auth"."uid"()) AND ("public"."sec_def_is_room_participant"("room_id", "auth"."uid"()) OR "public"."sec_def_is_room_owner"("room_id", "auth"."uid"()))));



CREATE POLICY "Users can update their own messages" ON "public"."messages" FOR UPDATE USING (("sender_id" = "auth"."uid"()));



CREATE POLICY "Users can update their own notifications" ON "public"."system_notifications" FOR UPDATE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can update their own participant record" ON "public"."chat_participants" FOR UPDATE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view participants in their rooms" ON "public"."chat_participants" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_room_participant"("room_id", "auth"."uid"())));



CREATE POLICY "Users can view room messages" ON "public"."messages" FOR SELECT USING (("public"."sec_def_is_room_participant"("room_id", "auth"."uid"()) OR "public"."sec_def_is_room_owner"("room_id", "auth"."uid"())));



CREATE POLICY "Users can view room participants" ON "public"."chat_participants" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."sec_def_is_room_participant"("room_id", "auth"."uid"()) OR "public"."sec_def_is_room_owner"("room_id", "auth"."uid"())));



CREATE POLICY "Users can view rooms they participate in" ON "public"."chat_rooms" FOR SELECT USING ((("owner_id" = "auth"."uid"()) OR "public"."user_is_room_participant"("id")));



CREATE POLICY "Users can view their chat rooms" ON "public"."chat_rooms" FOR SELECT USING ((("owner_id" = "auth"."uid"()) OR "public"."sec_def_is_room_participant"("id", "auth"."uid"())));



CREATE POLICY "Users can view their own favorites" ON "public"."favorites" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own notifications" ON "public"."system_notifications" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own orders" ON "public"."orders" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Users involved see disputes" ON "public"."disputes" FOR SELECT USING (("auth"."uid"() IN ( SELECT "orders"."customer_id"
   FROM "public"."orders"
  WHERE ("orders"."id" = "disputes"."order_id")
UNION
 SELECT "orders"."owner_id"
   FROM "public"."orders"
  WHERE ("orders"."id" = "disputes"."order_id")
UNION
 SELECT "orders"."assigned_rider_id"
   FROM "public"."orders"
  WHERE ("orders"."id" = "disputes"."order_id"))));



CREATE POLICY "Users manage own subscriptions" ON "public"."subscriptions" USING (("auth"."uid"() = "customer_id"));



ALTER TABLE "public"."audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_participants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_rooms" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_addresses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_payment_methods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."disputes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dm_credits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dm_deliveries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dm_inventory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dm_riders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."expenses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."favorites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventory_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "owner_full_access_credits" ON "public"."dm_credits" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "owner_full_access_deliveries" ON "public"."dm_deliveries" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "owner_full_access_inventory" ON "public"."dm_inventory" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "owner_full_access_riders" ON "public"."dm_riders" USING (("owner_id" = "auth"."uid"()));



ALTER TABLE "public"."owner_inventory_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."owner_payout_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."owner_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payment_checkouts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payment_webhook_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_users_update_own" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



ALTER TABLE "public"."quick_replies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reviews" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rider_earnings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rider_locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rider_own_credits" ON "public"."dm_credits" FOR SELECT USING (("rider_id" IN ( SELECT "dm_riders"."id"
   FROM "public"."dm_riders"
  WHERE ("dm_riders"."linked_user_id" = "auth"."uid"()))));



CREATE POLICY "rider_own_deliveries" ON "public"."dm_deliveries" FOR SELECT USING (("rider_id" IN ( SELECT "dm_riders"."id"
   FROM "public"."dm_riders"
  WHERE ("dm_riders"."linked_user_id" = "auth"."uid"()))));



ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."system_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."system_notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "system_notifications_user_select" ON "public"."system_notifications" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "system_notifications_user_update" ON "public"."system_notifications" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chat_participants";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chat_rooms";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."customer_addresses";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."customer_payment_methods";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."disputes";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."messages";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."order_items";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."orders";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."owner_inventory_ledger";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."owner_payout_accounts";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."owner_settings";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."payment_checkouts";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."payment_webhook_events";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."products";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profiles";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."reviews";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."rider_locations";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."system_notifications";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































REVOKE ALL ON FUNCTION "public"."_admin_cleanup_user_links"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_admin_cleanup_user_links"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."_admin_cleanup_user_links"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_admin_cleanup_user_links"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_broadcast_notification"("p_role" "text", "p_title" "text", "p_content" "text", "p_priority" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_broadcast_notification"("p_role" "text", "p_title" "text", "p_content" "text", "p_priority" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_broadcast_notification"("p_role" "text", "p_title" "text", "p_content" "text", "p_priority" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_broadcast_notification"("p_role" "text", "p_title" "text", "p_content" "text", "p_priority" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_cancel_order"("p_order_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_cancel_order"("p_order_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_cancel_order"("p_order_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_cancel_order"("p_order_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_create_station"("p_email" "text", "p_password" "text", "p_station_name" "text", "p_owner_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_region_id" "uuid", "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_create_station"("p_email" "text", "p_password" "text", "p_station_name" "text", "p_owner_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_region_id" "uuid", "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_create_station"("p_email" "text", "p_password" "text", "p_station_name" "text", "p_owner_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_region_id" "uuid", "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_create_station"("p_email" "text", "p_password" "text", "p_station_name" "text", "p_owner_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_region_id" "uuid", "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_create_user"("p_email" "text", "p_password" "text", "p_role" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_owner_id" "uuid", "p_region_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_create_user"("p_email" "text", "p_password" "text", "p_role" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_owner_id" "uuid", "p_region_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_create_user"("p_email" "text", "p_password" "text", "p_role" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_owner_id" "uuid", "p_region_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_create_user"("p_email" "text", "p_password" "text", "p_role" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_owner_id" "uuid", "p_region_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_dashboard_stats"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_dashboard_stats"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_dashboard_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_dashboard_stats"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_delete_product"("p_product_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_delete_product"("p_product_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_delete_product"("p_product_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_delete_product"("p_product_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_delete_review"("p_review_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_delete_review"("p_review_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_delete_review"("p_review_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_delete_review"("p_review_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_delete_station"("p_owner_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_delete_station"("p_owner_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_delete_station"("p_owner_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_delete_station"("p_owner_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_delete_user"("p_user_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_delete_user"("p_user_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_delete_user"("p_user_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_delete_user"("p_user_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_failed_payments_count"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_failed_payments_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_failed_payments_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_failed_payments_count"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_get_activity_timeline"("p_entity_type" "text", "p_entity_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_activity_timeline"("p_entity_type" "text", "p_entity_id" "uuid", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_get_activity_timeline"("p_entity_type" "text", "p_entity_id" "uuid", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_get_activity_timeline"("p_entity_type" "text", "p_entity_id" "uuid", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_get_order_detail"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_order_detail"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_get_order_detail"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_get_order_detail"("p_order_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_get_platform_fee"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_platform_fee"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_get_platform_fee"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_get_platform_fee"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_get_station_detail"("p_owner_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_station_detail"("p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_get_station_detail"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_get_station_detail"("p_owner_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_get_user_detail"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_user_detail"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_get_user_detail"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_get_user_detail"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_admins"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_admins"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_admins"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_admins"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_audit_logs"("p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_audit_logs"("p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_audit_logs"("p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_audit_logs"("p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_disputes"("p_limit" integer, "p_offset" integer, "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_disputes"("p_limit" integer, "p_offset" integer, "p_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_disputes"("p_limit" integer, "p_offset" integer, "p_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_disputes"("p_limit" integer, "p_offset" integer, "p_status" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_inventory_ledger"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_inventory_ledger"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_inventory_ledger"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_inventory_ledger"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_live_riders"("p_region_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_live_riders"("p_region_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_live_riders"("p_region_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_live_riders"("p_region_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_orders"("p_limit" integer, "p_offset" integer, "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_orders"("p_limit" integer, "p_offset" integer, "p_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_orders"("p_limit" integer, "p_offset" integer, "p_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_orders"("p_limit" integer, "p_offset" integer, "p_status" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_payment_failures"("p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_payment_failures"("p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_payment_failures"("p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_payment_failures"("p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_regions"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_regions"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_regions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_regions"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_reviews"("p_limit" integer, "p_offset" integer, "p_min_rating" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_reviews"("p_limit" integer, "p_offset" integer, "p_min_rating" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_reviews"("p_limit" integer, "p_offset" integer, "p_min_rating" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_reviews"("p_limit" integer, "p_offset" integer, "p_min_rating" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_station_customers"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_station_customers"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_station_customers"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_station_customers"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_station_products"("p_owner_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_station_products"("p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_station_products"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_station_products"("p_owner_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_station_riders"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_station_riders"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_station_riders"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_station_riders"("p_owner_id" "uuid", "p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text", "p_region_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text", "p_region_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_stations"("p_limit" integer, "p_offset" integer, "p_search" "text", "p_region_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_users"("p_role" "text", "p_limit" integer, "p_offset" integer, "p_search" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_users"("p_role" "text", "p_limit" integer, "p_offset" integer, "p_search" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_users"("p_role" "text", "p_limit" integer, "p_offset" integer, "p_search" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_users"("p_role" "text", "p_limit" integer, "p_offset" integer, "p_search" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_reassign_rider"("p_order_id" "uuid", "p_rider_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_reassign_rider"("p_order_id" "uuid", "p_rider_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_reassign_rider"("p_order_id" "uuid", "p_rider_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_reassign_rider"("p_order_id" "uuid", "p_rider_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_refund_order"("p_order_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_refund_order"("p_order_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_refund_order"("p_order_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_refund_order"("p_order_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_retry_payment_event"("p_event_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_retry_payment_event"("p_event_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_retry_payment_event"("p_event_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_retry_payment_event"("p_event_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_revenue_analytics"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_revenue_analytics"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_revenue_analytics"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_revenue_analytics"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_send_notification"("p_user_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "text", "p_priority" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_send_notification"("p_user_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "text", "p_priority" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_send_notification"("p_user_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "text", "p_priority" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_send_notification"("p_user_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "text", "p_priority" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_admin_tier"("p_user_id" "uuid", "p_tier" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_admin_tier"("p_user_id" "uuid", "p_tier" "text", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_set_admin_tier"("p_user_id" "uuid", "p_tier" "text", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_admin_tier"("p_user_id" "uuid", "p_tier" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_platform_fee"("p_percent" numeric, "p_fixed" numeric, "p_enabled" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_platform_fee"("p_percent" numeric, "p_fixed" numeric, "p_enabled" boolean, "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_set_platform_fee"("p_percent" numeric, "p_fixed" numeric, "p_enabled" boolean, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_platform_fee"("p_percent" numeric, "p_fixed" numeric, "p_enabled" boolean, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_station_availability"("p_owner_id" "uuid", "p_availability" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_station_availability"("p_owner_id" "uuid", "p_availability" "text", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_set_station_availability"("p_owner_id" "uuid", "p_availability" "text", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_station_availability"("p_owner_id" "uuid", "p_availability" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_system_config"("p_key" "text", "p_value" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_system_config"("p_key" "text", "p_value" "jsonb", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_set_system_config"("p_key" "text", "p_value" "jsonb", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_system_config"("p_key" "text", "p_value" "jsonb", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_suspend_user"("p_user_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_suspend_user"("p_user_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_suspend_user"("p_user_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_suspend_user"("p_user_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_unsuspend_user"("p_user_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_unsuspend_user"("p_user_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_unsuspend_user"("p_user_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_unsuspend_user"("p_user_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_dispute"("p_dispute_id" "uuid", "p_status" "text", "p_resolution_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_dispute"("p_dispute_id" "uuid", "p_status" "text", "p_resolution_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_update_dispute"("p_dispute_id" "uuid", "p_status" "text", "p_resolution_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_dispute"("p_dispute_id" "uuid", "p_status" "text", "p_resolution_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_station_profile"("p_owner_id" "uuid", "p_station_name" "text", "p_station_description" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_service_radius_km" numeric, "p_max_concurrent_orders" integer, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_station_profile"("p_owner_id" "uuid", "p_station_name" "text", "p_station_description" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_service_radius_km" numeric, "p_max_concurrent_orders" integer, "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_update_station_profile"("p_owner_id" "uuid", "p_station_name" "text", "p_station_description" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_service_radius_km" numeric, "p_max_concurrent_orders" integer, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_station_profile"("p_owner_id" "uuid", "p_station_name" "text", "p_station_description" "text", "p_full_name" "text", "p_phone" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_latitude" double precision, "p_longitude" double precision, "p_base_delivery_fee" numeric, "p_price_per_gallon" numeric, "p_service_radius_km" numeric, "p_max_concurrent_orders" integer, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_user_email"("p_user_id" "uuid", "p_email" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_user_email"("p_user_id" "uuid", "p_email" "text", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_update_user_email"("p_user_id" "uuid", "p_email" "text", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_user_email"("p_user_id" "uuid", "p_email" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_user_password"("p_user_id" "uuid", "p_password" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_user_password"("p_user_id" "uuid", "p_password" "text", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_update_user_password"("p_user_id" "uuid", "p_password" "text", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_user_password"("p_user_id" "uuid", "p_password" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_user_profile"("p_user_id" "uuid", "p_full_name" "text", "p_phone" "text", "p_username" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_landmark" "text", "p_vehicle_type" "text", "p_license_number" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_user_profile"("p_user_id" "uuid", "p_full_name" "text", "p_phone" "text", "p_username" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_landmark" "text", "p_vehicle_type" "text", "p_license_number" "text", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_update_user_profile"("p_user_id" "uuid", "p_full_name" "text", "p_phone" "text", "p_username" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_landmark" "text", "p_vehicle_type" "text", "p_license_number" "text", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_user_profile"("p_user_id" "uuid", "p_full_name" "text", "p_phone" "text", "p_username" "text", "p_town" "text", "p_barangay" "text", "p_complete_address" "text", "p_landmark" "text", "p_vehicle_type" "text", "p_license_number" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_upsert_product"("p_product_id" "uuid", "p_owner_id" "uuid", "p_name" "text", "p_description" "text", "p_price" numeric, "p_category" "text", "p_stock_level" integer, "p_is_available" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_upsert_product"("p_product_id" "uuid", "p_owner_id" "uuid", "p_name" "text", "p_description" "text", "p_price" numeric, "p_category" "text", "p_stock_level" integer, "p_is_available" boolean, "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_upsert_product"("p_product_id" "uuid", "p_owner_id" "uuid", "p_name" "text", "p_description" "text", "p_price" numeric, "p_category" "text", "p_stock_level" integer, "p_is_available" boolean, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_upsert_product"("p_product_id" "uuid", "p_owner_id" "uuid", "p_name" "text", "p_description" "text", "p_price" numeric, "p_category" "text", "p_stock_level" integer, "p_is_available" boolean, "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."algorithm_sign"("signables" "text", "secret" "text", "algorithm" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."algorithm_sign"("signables" "text", "secret" "text", "algorithm" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."algorithm_sign"("signables" "text", "secret" "text", "algorithm" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."algorithm_sign"("signables" "text", "secret" "text", "algorithm" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."archive_order_chat_on_delivery"() TO "anon";
GRANT ALL ON FUNCTION "public"."archive_order_chat_on_delivery"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."archive_order_chat_on_delivery"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."assign_rider_safely"("p_order_id" "uuid", "p_rider_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assign_rider_safely"("p_order_id" "uuid", "p_rider_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_rider_safely"("p_order_id" "uuid", "p_rider_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_add_order_chat_participants"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_add_order_chat_participants"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_add_order_chat_participants"() TO "service_role";



GRANT ALL ON FUNCTION "public"."broadcast_to_riders"("p_owner_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "public"."notification_type", "p_priority" "public"."notification_priority") TO "anon";
GRANT ALL ON FUNCTION "public"."broadcast_to_riders"("p_owner_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "public"."notification_type", "p_priority" "public"."notification_priority") TO "authenticated";
GRANT ALL ON FUNCTION "public"."broadcast_to_riders"("p_owner_id" "uuid", "p_title" "text", "p_content" "text", "p_type" "public"."notification_type", "p_priority" "public"."notification_priority") TO "service_role";



REVOKE ALL ON FUNCTION "public"."calculate_platform_fee"("p_subtotal" numeric, "p_delivery_fee" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."calculate_platform_fee"("p_subtotal" numeric, "p_delivery_fee" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_platform_fee"("p_subtotal" numeric, "p_delivery_fee" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_platform_fee"("p_subtotal" numeric, "p_delivery_fee" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_app_compatibility"("p_app_version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_app_compatibility"("p_app_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_app_compatibility"("p_app_version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_station_availability"("p_station_id" "uuid", "p_customer_lat" double precision, "p_customer_lng" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."check_station_availability"("p_station_id" "uuid", "p_customer_lat" double precision, "p_customer_lng" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_station_availability"("p_station_id" "uuid", "p_customer_lat" double precision, "p_customer_lng" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_old_notifications"("p_days" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_old_notifications"("p_days" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_old_notifications"("p_days" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text", "p_delivery_note" "text", "p_empty_gallons_returned" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text", "p_delivery_note" "text", "p_empty_gallons_returned" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_delivery_safely"("p_order_id" "uuid", "p_lat" double precision, "p_lng" double precision, "p_photo_url" "text", "p_signature_url" "text", "p_delivery_note" "text", "p_empty_gallons_returned" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_default_quick_replies"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_default_quick_replies"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_default_quick_replies"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_order_atomic"("p_order_data" "jsonb", "p_items_data" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_order_atomic"("p_order_data" "jsonb", "p_items_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_order_atomic"("p_order_data" "jsonb", "p_items_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_order_chat_room"("p_order_id" "uuid", "p_customer_id" "uuid", "p_owner_id" "uuid", "p_rider_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_order_chat_room"("p_order_id" "uuid", "p_customer_id" "uuid", "p_owner_id" "uuid", "p_rider_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_rider_account"("p_email" "text", "p_password" "text", "p_username" "text", "p_full_name" "text", "p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_rider_account"("p_email" "text", "p_password" "text", "p_username" "text", "p_full_name" "text", "p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_rider_account"("p_email" "text", "p_password" "text", "p_username" "text", "p_full_name" "text", "p_owner_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_support_chat_room"("p_customer_id" "uuid", "p_owner_id" "uuid", "p_title" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_support_chat_room"("p_customer_id" "uuid", "p_owner_id" "uuid", "p_title" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_support_chat_room"("p_customer_id" "uuid", "p_owner_id" "uuid", "p_title" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cron_nightly_ops"() TO "anon";
GRANT ALL ON FUNCTION "public"."cron_nightly_ops"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cron_nightly_ops"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cron_nightly_ops_refined"() TO "anon";
GRANT ALL ON FUNCTION "public"."cron_nightly_ops_refined"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cron_nightly_ops_refined"() TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_user_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_user_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_user_account"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_order_status_logic"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_order_status_logic"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_order_status_logic"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_pgcrypto"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_pgcrypto"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_pgcrypto"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_digital_receipt_data"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_digital_receipt_data"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_digital_receipt_data"("p_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dispatch_recommendation"("p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dispatch_recommendation"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dispatch_recommendation"("p_owner_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_chat_rooms"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_chat_rooms"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_chat_rooms"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_order_batch_suggestions"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_order_batch_suggestions"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_order_batch_suggestions"("p_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_peak_hour_stats"("p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_peak_hour_stats"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_peak_hour_stats"("p_owner_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_platform_fee_config"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_platform_fee_config"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_platform_fee_config"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_platform_fee_config"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_station_available_payment_methods"("p_owner_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_station_available_payment_methods"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_station_available_payment_methods"("p_owner_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_unread_count"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_unread_count"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unread_count"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."guard_profile_role_changes"() TO "anon";
GRANT ALL ON FUNCTION "public"."guard_profile_role_changes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."guard_profile_role_changes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."guard_system_message_spoofing"() TO "anon";
GRANT ALL ON FUNCTION "public"."guard_system_message_spoofing"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."guard_system_message_spoofing"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_inventory_deduction"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_inventory_deduction"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_inventory_deduction"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_station_payment_method_available"("p_owner_id" "uuid", "p_payment_method" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_station_payment_method_available"("p_owner_id" "uuid", "p_payment_method" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_station_payment_method_available"("p_owner_id" "uuid", "p_payment_method" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_super_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_super_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_super_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_super_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."log_owner_inventory_tx"("p_tx_type" "text", "p_gallons" integer, "p_notes" "text", "p_product_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."log_owner_inventory_tx"("p_tx_type" "text", "p_gallons" integer, "p_notes" "text", "p_product_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_owner_inventory_tx"("p_tx_type" "text", "p_gallons" integer, "p_notes" "text", "p_product_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_all_notifications_read"() TO "anon";
GRANT ALL ON FUNCTION "public"."mark_all_notifications_read"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_all_notifications_read"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_message_delivered"("p_message_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_message_delivered"("p_message_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_message_delivered"("p_message_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_messages_as_read"("p_room_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_notification_read"("p_notification_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_notification_read"("p_notification_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_notification_read"("p_notification_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_room_as_seen"("p_room_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_room_as_seen"("p_room_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_room_as_seen"("p_room_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_earnings_payout"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_earnings_payout"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_earnings_payout"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_rider_order_assigned"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_rider_order_assigned"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_rider_order_assigned"() TO "service_role";



GRANT ALL ON FUNCTION "public"."pmin"("a" double precision, "b" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."pmin"("a" double precision, "b" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pmin"("a" double precision, "b" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."proc_analyze_rider_behavior"() TO "anon";
GRANT ALL ON FUNCTION "public"."proc_analyze_rider_behavior"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."proc_analyze_rider_behavior"() TO "service_role";



GRANT ALL ON FUNCTION "public"."proc_finalize_order_finances"() TO "anon";
GRANT ALL ON FUNCTION "public"."proc_finalize_order_finances"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."proc_finalize_order_finances"() TO "service_role";



GRANT ALL ON FUNCTION "public"."proc_log_dispute_event"() TO "anon";
GRANT ALL ON FUNCTION "public"."proc_log_dispute_event"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."proc_log_dispute_event"() TO "service_role";



GRANT ALL ON FUNCTION "public"."proc_log_inventory_event"() TO "anon";
GRANT ALL ON FUNCTION "public"."proc_log_inventory_event"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."proc_log_inventory_event"() TO "service_role";



GRANT ALL ON FUNCTION "public"."proc_restore_inventory_on_cancellation"() TO "anon";
GRANT ALL ON FUNCTION "public"."proc_restore_inventory_on_cancellation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."proc_restore_inventory_on_cancellation"() TO "service_role";



GRANT ALL ON FUNCTION "public"."proc_sync_order_chat_participants"() TO "anon";
GRANT ALL ON FUNCTION "public"."proc_sync_order_chat_participants"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."proc_sync_order_chat_participants"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_payment_checkout"("p_order_id" "uuid", "p_customer_id" "uuid", "p_owner_id" "uuid", "p_payment_method" "text", "p_provider_checkout_id" "text", "p_checkout_url" "text", "p_amount" numeric, "p_status" "text", "p_raw_response" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_payment_checkout"("p_order_id" "uuid", "p_customer_id" "uuid", "p_owner_id" "uuid", "p_payment_method" "text", "p_provider_checkout_id" "text", "p_checkout_url" "text", "p_amount" numeric, "p_status" "text", "p_raw_response" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_integrity_watchdog"() TO "anon";
GRANT ALL ON FUNCTION "public"."run_integrity_watchdog"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_integrity_watchdog"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sec_def_is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."sec_def_is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sec_def_is_room_owner"("p_room_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."sec_def_is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."sec_def_is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sec_def_is_room_participant"("p_room_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_quick_reply"("p_room_id" "uuid", "p_quick_reply_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."send_quick_reply"("p_room_id" "uuid", "p_quick_reply_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_quick_reply"("p_room_id" "uuid", "p_quick_reply_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_system_message"("p_room_id" "uuid", "p_content" "text", "p_metadata" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."send_system_message"("p_room_id" "uuid", "p_content" "text", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_system_message"("p_room_id" "uuid", "p_content" "text", "p_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_payment_account_default"("p_user_id" "uuid", "p_account_id" "uuid", "p_scope" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_payment_account_default"("p_user_id" "uuid", "p_account_id" "uuid", "p_scope" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sign"("payload" json, "secret" "text", "algorithm" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."sign"("payload" json, "secret" "text", "algorithm" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sign"("payload" json, "secret" "text", "algorithm" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sign"("payload" json, "secret" "text", "algorithm" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."smart_dispatch_rider"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."smart_dispatch_rider"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."smart_dispatch_rider"("p_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."smart_dispatch_rider_regional"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."smart_dispatch_rider_regional"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."smart_dispatch_rider_regional"("p_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_owner_default_product"("p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."sync_owner_default_product"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_owner_default_product"("p_owner_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."transition_order_status_safely"("p_order_id" "uuid", "p_new_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."transition_order_status_safely"("p_order_id" "uuid", "p_new_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."transition_order_status_safely"("p_order_id" "uuid", "p_new_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_sync_owner_default_product"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_sync_owner_default_product"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_sync_owner_default_product"() TO "service_role";



GRANT ALL ON FUNCTION "public"."try_cast_double"("inp" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."try_cast_double"("inp" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."try_cast_double"("inp" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."try_cast_double"("inp" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_chat_room_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_chat_room_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_chat_room_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_last_read"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_last_read"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_last_read"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_message_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_message_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_message_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_quick_reply_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_quick_reply_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_quick_reply_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_room_on_new_message"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_room_on_new_message"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_room_on_new_message"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_station_stats"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_station_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_station_stats"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."url_decode"("data" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."url_decode"("data" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."url_decode"("data" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."url_decode"("data" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."url_encode"("data" "bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."url_encode"("data" "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."url_encode"("data" "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."url_encode"("data" "bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."user_is_room_participant"("p_room_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."user_is_room_participant"("p_room_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."user_is_room_participant"("p_room_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."verify"("token" "text", "secret" "text", "algorithm" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."verify"("token" "text", "secret" "text", "algorithm" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."verify"("token" "text", "secret" "text", "algorithm" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."verify"("token" "text", "secret" "text", "algorithm" "text") TO "service_role";


















GRANT ALL ON TABLE "public"."audit_logs" TO "anon";
GRANT ALL ON TABLE "public"."audit_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."chat_participants" TO "anon";
GRANT ALL ON TABLE "public"."chat_participants" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_participants" TO "service_role";



GRANT ALL ON TABLE "public"."chat_rooms" TO "anon";
GRANT ALL ON TABLE "public"."chat_rooms" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_rooms" TO "service_role";



GRANT ALL ON TABLE "public"."customer_addresses" TO "anon";
GRANT ALL ON TABLE "public"."customer_addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_addresses" TO "service_role";



GRANT ALL ON TABLE "public"."customer_payment_methods" TO "anon";
GRANT ALL ON TABLE "public"."customer_payment_methods" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_payment_methods" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."dispatch_urgency_queue" TO "anon";
GRANT ALL ON TABLE "public"."dispatch_urgency_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."dispatch_urgency_queue" TO "service_role";



GRANT ALL ON TABLE "public"."disputes" TO "anon";
GRANT ALL ON TABLE "public"."disputes" TO "authenticated";
GRANT ALL ON TABLE "public"."disputes" TO "service_role";



GRANT ALL ON TABLE "public"."dm_credits" TO "anon";
GRANT ALL ON TABLE "public"."dm_credits" TO "authenticated";
GRANT ALL ON TABLE "public"."dm_credits" TO "service_role";



GRANT ALL ON TABLE "public"."dm_deliveries" TO "anon";
GRANT ALL ON TABLE "public"."dm_deliveries" TO "authenticated";
GRANT ALL ON TABLE "public"."dm_deliveries" TO "service_role";



GRANT ALL ON TABLE "public"."dm_inventory" TO "anon";
GRANT ALL ON TABLE "public"."dm_inventory" TO "authenticated";
GRANT ALL ON TABLE "public"."dm_inventory" TO "service_role";



GRANT ALL ON TABLE "public"."dm_riders" TO "anon";
GRANT ALL ON TABLE "public"."dm_riders" TO "authenticated";
GRANT ALL ON TABLE "public"."dm_riders" TO "service_role";



GRANT ALL ON TABLE "public"."domain_events" TO "anon";
GRANT ALL ON TABLE "public"."domain_events" TO "authenticated";
GRANT ALL ON TABLE "public"."domain_events" TO "service_role";



GRANT ALL ON TABLE "public"."expenses" TO "anon";
GRANT ALL ON TABLE "public"."expenses" TO "authenticated";
GRANT ALL ON TABLE "public"."expenses" TO "service_role";



GRANT ALL ON TABLE "public"."favorites" TO "anon";
GRANT ALL ON TABLE "public"."favorites" TO "authenticated";
GRANT ALL ON TABLE "public"."favorites" TO "service_role";



GRANT ALL ON TABLE "public"."ledger_entries" TO "anon";
GRANT ALL ON TABLE "public"."ledger_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."ledger_entries" TO "service_role";



GRANT ALL ON TABLE "public"."integrity_violations" TO "anon";
GRANT ALL ON TABLE "public"."integrity_violations" TO "authenticated";
GRANT ALL ON TABLE "public"."integrity_violations" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_ledger" TO "anon";
GRANT ALL ON TABLE "public"."inventory_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."operational_metrics" TO "anon";
GRANT ALL ON TABLE "public"."operational_metrics" TO "authenticated";
GRANT ALL ON TABLE "public"."operational_metrics" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON TABLE "public"."owner_inventory_ledger" TO "anon";
GRANT ALL ON TABLE "public"."owner_inventory_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."owner_inventory_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."owner_payout_accounts" TO "anon";
GRANT ALL ON TABLE "public"."owner_payout_accounts" TO "authenticated";
GRANT ALL ON TABLE "public"."owner_payout_accounts" TO "service_role";



GRANT ALL ON TABLE "public"."owner_settings" TO "anon";
GRANT ALL ON TABLE "public"."owner_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."owner_settings" TO "service_role";



GRANT ALL ON TABLE "public"."payment_checkouts" TO "anon";
GRANT ALL ON TABLE "public"."payment_checkouts" TO "authenticated";
GRANT ALL ON TABLE "public"."payment_checkouts" TO "service_role";



GRANT ALL ON TABLE "public"."payment_webhook_events" TO "anon";
GRANT ALL ON TABLE "public"."payment_webhook_events" TO "authenticated";
GRANT ALL ON TABLE "public"."payment_webhook_events" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."quick_replies" TO "anon";
GRANT ALL ON TABLE "public"."quick_replies" TO "authenticated";
GRANT ALL ON TABLE "public"."quick_replies" TO "service_role";



GRANT ALL ON TABLE "public"."rate_limit_events" TO "anon";
GRANT ALL ON TABLE "public"."rate_limit_events" TO "authenticated";
GRANT ALL ON TABLE "public"."rate_limit_events" TO "service_role";



GRANT ALL ON TABLE "public"."regions" TO "anon";
GRANT ALL ON TABLE "public"."regions" TO "authenticated";
GRANT ALL ON TABLE "public"."regions" TO "service_role";



GRANT ALL ON TABLE "public"."remittances" TO "anon";
GRANT ALL ON TABLE "public"."remittances" TO "authenticated";
GRANT ALL ON TABLE "public"."remittances" TO "service_role";



GRANT ALL ON TABLE "public"."reviews" TO "anon";
GRANT ALL ON TABLE "public"."reviews" TO "authenticated";
GRANT ALL ON TABLE "public"."reviews" TO "service_role";



GRANT ALL ON TABLE "public"."rider_earnings" TO "anon";
GRANT ALL ON TABLE "public"."rider_earnings" TO "authenticated";
GRANT ALL ON TABLE "public"."rider_earnings" TO "service_role";



GRANT ALL ON TABLE "public"."rider_locations" TO "anon";
GRANT ALL ON TABLE "public"."rider_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."rider_locations" TO "service_role";



GRANT ALL ON TABLE "public"."sla_violations" TO "anon";
GRANT ALL ON TABLE "public"."sla_violations" TO "authenticated";
GRANT ALL ON TABLE "public"."sla_violations" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."suspicious_activities" TO "anon";
GRANT ALL ON TABLE "public"."suspicious_activities" TO "authenticated";
GRANT ALL ON TABLE "public"."suspicious_activities" TO "service_role";



GRANT ALL ON TABLE "public"."system_config" TO "anon";
GRANT ALL ON TABLE "public"."system_config" TO "authenticated";
GRANT ALL ON TABLE "public"."system_config" TO "service_role";



GRANT ALL ON TABLE "public"."system_notifications" TO "anon";
GRANT ALL ON TABLE "public"."system_notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."system_notifications" TO "service_role";



GRANT ALL ON TABLE "public"."v_barangay_demand_heatmap" TO "anon";
GRANT ALL ON TABLE "public"."v_barangay_demand_heatmap" TO "authenticated";
GRANT ALL ON TABLE "public"."v_barangay_demand_heatmap" TO "service_role";



GRANT ALL ON TABLE "public"."v_rider_performance_leaderboard" TO "anon";
GRANT ALL ON TABLE "public"."v_rider_performance_leaderboard" TO "authenticated";
GRANT ALL ON TABLE "public"."v_rider_performance_leaderboard" TO "service_role";



GRANT ALL ON TABLE "public"."v_tax_reconciliation" TO "anon";
GRANT ALL ON TABLE "public"."v_tax_reconciliation" TO "authenticated";
GRANT ALL ON TABLE "public"."v_tax_reconciliation" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
































-- ── rider_payout_requests ──
CREATE TABLE IF NOT EXISTS public.rider_payout_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    rider_name text NOT NULL DEFAULT '',
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    station_name text,
    amount numeric(12, 2) NOT NULL CHECK (amount > 0),
    payout_method text NOT NULL DEFAULT 'gcash',
    account_number text NOT NULL DEFAULT '',
    account_name text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'disbursed', 'rejected')),
    reference_number text,
    rejection_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    disbursed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_rider_payout_requests_rider_id ON public.rider_payout_requests(rider_id);
CREATE INDEX IF NOT EXISTS idx_rider_payout_requests_owner_id ON public.rider_payout_requests(owner_id);
CREATE INDEX IF NOT EXISTS idx_rider_payout_requests_status ON public.rider_payout_requests(status);

ALTER TABLE public.rider_payout_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Riders can view own payout requests" ON public.rider_payout_requests;
CREATE POLICY "Riders can view own payout requests"
  ON public.rider_payout_requests FOR SELECT TO authenticated
  USING (auth.uid() = rider_id);

DROP POLICY IF EXISTS "Riders can insert own payout requests" ON public.rider_payout_requests;
CREATE POLICY "Riders can insert own payout requests"
  ON public.rider_payout_requests FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = rider_id);

DROP POLICY IF EXISTS "Owners can view station payout requests" ON public.rider_payout_requests;
CREATE POLICY "Owners can view station payout requests"
  ON public.rider_payout_requests FOR SELECT TO authenticated
  USING (auth.uid() = owner_id);

DROP POLICY IF EXISTS "Owners can update station payout requests" ON public.rider_payout_requests;
CREATE POLICY "Owners can update station payout requests"
  ON public.rider_payout_requests FOR UPDATE TO authenticated
  USING (auth.uid() = owner_id);

DROP POLICY IF EXISTS "Admins full access on rider_payout_requests" ON public.rider_payout_requests;
CREATE POLICY "Admins full access on rider_payout_requests"
  ON public.rider_payout_requests FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));

GRANT ALL ON TABLE public.rider_payout_requests TO authenticated;
GRANT ALL ON TABLE public.rider_payout_requests TO service_role;
