-- ==============================================================================
-- Migration: Separate Chat Conversations & Role-Based Identity Resolution
-- 
-- 1. Separates Rider-Customer, Customer-Owner, and Owner-Rider chats into
--    completely isolated channels (never merged).
-- 2. Prevents auto-adding unintended participants across conversation channels.
-- 3. Provides optimized RPCs for instant channel retrieval & creation.
-- 4. Optimizes get_my_chat_rooms() with participant profiles and batch metadata.
-- ==============================================================================

-- 1. Update auto_add_order_chat_participants trigger function
CREATE OR REPLACE FUNCTION public.auto_add_order_chat_participants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order_record record;
    v_channel text;
BEGIN
    v_channel := NEW.metadata->>'channel';

    IF NEW.reference_id IS NOT NULL THEN
        SELECT customer_id, assigned_rider_id, owner_id
        INTO v_order_record
        FROM public.orders
        WHERE id = NEW.reference_id;
        
        IF v_order_record IS NOT NULL THEN
            IF v_channel = 'customer_rider' THEN
                -- Only add customer and assigned rider
                IF v_order_record.customer_id IS NOT NULL THEN
                    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                    VALUES (NEW.id, v_order_record.customer_id, 'customer')
                    ON CONFLICT (room_id, user_id) DO NOTHING;
                END IF;
                IF v_order_record.assigned_rider_id IS NOT NULL THEN
                    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                    VALUES (NEW.id, v_order_record.assigned_rider_id, 'rider')
                    ON CONFLICT (room_id, user_id) DO NOTHING;
                END IF;

            ELSIF v_channel = 'customer_owner' THEN
                -- Only add customer and station owner
                IF v_order_record.customer_id IS NOT NULL THEN
                    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                    VALUES (NEW.id, v_order_record.customer_id, 'customer')
                    ON CONFLICT (room_id, user_id) DO NOTHING;
                END IF;
                IF v_order_record.owner_id IS NOT NULL THEN
                    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                    VALUES (NEW.id, v_order_record.owner_id, 'owner')
                    ON CONFLICT (room_id, user_id) DO NOTHING;
                END IF;

            ELSIF v_channel = 'owner_rider' THEN
                -- Only add owner and assigned rider
                IF v_order_record.owner_id IS NOT NULL THEN
                    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                    VALUES (NEW.id, v_order_record.owner_id, 'owner')
                    ON CONFLICT (room_id, user_id) DO NOTHING;
                END IF;
                IF v_order_record.assigned_rider_id IS NOT NULL THEN
                    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                    VALUES (NEW.id, v_order_record.assigned_rider_id, 'rider')
                    ON CONFLICT (room_id, user_id) DO NOTHING;
                END IF;

            ELSIF NEW.room_type = 'order_delivery' THEN
                -- For unchannelled order_delivery rooms, only add customer & rider
                IF v_order_record.customer_id IS NOT NULL THEN
                    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                    VALUES (NEW.id, v_order_record.customer_id, 'customer')
                    ON CONFLICT (room_id, user_id) DO NOTHING;
                END IF;
                IF v_order_record.assigned_rider_id IS NOT NULL THEN
                    INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                    VALUES (NEW.id, v_order_record.assigned_rider_id, 'rider')
                    ON CONFLICT (room_id, user_id) DO NOTHING;
                END IF;
            END IF;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- 2. Update proc_sync_order_chat_participants for rider assignments
CREATE OR REPLACE FUNCTION public.proc_sync_order_chat_participants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_room_id uuid;
BEGIN
    IF OLD.assigned_rider_id IS DISTINCT FROM NEW.assigned_rider_id THEN
        -- Find customer-rider chat room for this order
        SELECT id INTO v_room_id
        FROM public.chat_rooms
        WHERE reference_id = NEW.id
          AND (metadata->>'channel' = 'customer_rider' OR room_type = 'order_delivery')
        LIMIT 1;

        IF v_room_id IS NOT NULL THEN
            IF OLD.assigned_rider_id IS NOT NULL THEN
                DELETE FROM public.chat_participants 
                WHERE room_id = v_room_id
                  AND user_id = OLD.assigned_rider_id
                  AND role_in_room = 'rider';
            END IF;

            IF NEW.assigned_rider_id IS NOT NULL THEN
                INSERT INTO public.chat_participants (room_id, user_id, role_in_room)
                VALUES (v_room_id, NEW.assigned_rider_id, 'rider')
                ON CONFLICT (room_id, user_id) DO NOTHING;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- 3. Dedicated RPC: get_or_create_customer_rider_chat_room
CREATE OR REPLACE FUNCTION public.get_or_create_customer_rider_chat_room(
  p_order_id uuid,
  p_customer_id uuid,
  p_rider_id uuid,
  p_customer_name text DEFAULT NULL,
  p_rider_name text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_room_id uuid;
    v_result jsonb;
    v_title text;
BEGIN
    SELECT cr.id INTO v_room_id
    FROM chat_rooms cr
    WHERE cr.reference_id = p_order_id
      AND (cr.metadata->>'channel' = 'customer_rider' OR (cr.room_type = 'order_delivery' AND cr.metadata->>'channel' IS NULL))
    LIMIT 1;

    IF v_room_id IS NOT NULL THEN
        INSERT INTO chat_participants (room_id, user_id, role_in_room)
        VALUES (v_room_id, p_customer_id, 'customer')
        ON CONFLICT (room_id, user_id) DO NOTHING;

        IF p_rider_id IS NOT NULL THEN
            INSERT INTO chat_participants (room_id, user_id, role_in_room)
            VALUES (v_room_id, p_rider_id, 'rider')
            ON CONFLICT (room_id, user_id) DO NOTHING;
        END IF;

        SELECT jsonb_build_object(
            'id', cr.id,
            'room_type', cr.room_type,
            'reference_id', cr.reference_id,
            'owner_id', cr.owner_id,
            'title', cr.title,
            'status', cr.status,
            'created_at', cr.created_at,
            'updated_at', cr.updated_at,
            'metadata', cr.metadata,
            'participants', coalesce((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', cp.id,
                        'room_id', cp.room_id,
                        'user_id', cp.user_id,
                        'role_in_room', cp.role_in_room,
                        'joined_at', cp.joined_at,
                        'is_muted', false,
                        'full_name', p.full_name,
                        'username', p.username,
                        'avatar_url', p.avatar_url
                    )
                )
                FROM chat_participants cp
                LEFT JOIN profiles p ON p.id = cp.user_id
                WHERE cp.room_id = cr.id
            ), '[]'::jsonb)
        ) INTO v_result
        FROM chat_rooms cr
        WHERE cr.id = v_room_id;

        RETURN v_result;
    END IF;

    v_title := coalesce(p_rider_name, 'Rider Delivery');

    INSERT INTO chat_rooms (
        room_type,
        reference_id,
        owner_id,
        title,
        status,
        metadata
    ) VALUES (
        'order_delivery',
        p_order_id,
        p_customer_id,
        v_title,
        'active',
        jsonb_build_object(
            'channel', 'customer_rider',
            'order_id', p_order_id,
            'customer_name', p_customer_name,
            'rider_name', p_rider_name
        )
    ) RETURNING id INTO v_room_id;

    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_customer_id, 'customer')
    ON CONFLICT (room_id, user_id) DO NOTHING;

    IF p_rider_id IS NOT NULL THEN
        INSERT INTO chat_participants (room_id, user_id, role_in_room)
        VALUES (v_room_id, p_rider_id, 'rider')
        ON CONFLICT (room_id, user_id) DO NOTHING;
    END IF;

    PERFORM set_config('erefill.internal_system_message', 'on', true);
    INSERT INTO messages (room_id, sender_id, content, message_type)
    VALUES (v_room_id, null, 'Delivery chat started. Coordinate drop-off and directions directly with your rider.', 'system');

    SELECT jsonb_build_object(
        'id', cr.id,
        'room_type', cr.room_type,
        'reference_id', cr.reference_id,
        'owner_id', cr.owner_id,
        'title', cr.title,
        'status', cr.status,
        'created_at', cr.created_at,
        'updated_at', cr.updated_at,
        'metadata', cr.metadata,
        'participants', coalesce((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', cp.id,
                    'room_id', cp.room_id,
                    'user_id', cp.user_id,
                    'role_in_room', cp.role_in_room,
                    'joined_at', cp.joined_at,
                    'is_muted', false,
                    'full_name', p.full_name,
                    'username', p.username,
                    'avatar_url', p.avatar_url
                )
            )
            FROM chat_participants cp
            LEFT JOIN profiles p ON p.id = cp.user_id
            WHERE cp.room_id = cr.id
        ), '[]'::jsonb)
    ) INTO v_result
    FROM chat_rooms cr
    WHERE cr.id = v_room_id;

    RETURN v_result;
END;
$$;

-- 4. Dedicated RPC: get_or_create_customer_owner_chat_room
CREATE OR REPLACE FUNCTION public.get_or_create_customer_owner_chat_room(
  p_order_id uuid,
  p_customer_id uuid,
  p_owner_id uuid,
  p_station_name text DEFAULT NULL,
  p_customer_name text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_room_id uuid;
    v_result jsonb;
    v_title text;
BEGIN
    IF p_order_id IS NOT NULL THEN
        SELECT cr.id INTO v_room_id
        FROM chat_rooms cr
        WHERE cr.reference_id = p_order_id
          AND cr.room_type = 'customer_support'
        LIMIT 1;
    END IF;

    IF v_room_id IS NULL THEN
        SELECT cr.id INTO v_room_id
        FROM chat_rooms cr
        JOIN chat_participants cp1 ON cp1.room_id = cr.id AND cp1.user_id = p_customer_id
        JOIN chat_participants cp2 ON cp2.room_id = cr.id AND cp2.user_id = p_owner_id
        WHERE cr.room_type = 'customer_support'
          AND cr.status = 'active'
        LIMIT 1;
    END IF;

    IF v_room_id IS NOT NULL THEN
        INSERT INTO chat_participants (room_id, user_id, role_in_room)
        VALUES (v_room_id, p_customer_id, 'customer')
        ON CONFLICT (room_id, user_id) DO NOTHING;

        INSERT INTO chat_participants (room_id, user_id, role_in_room)
        VALUES (v_room_id, p_owner_id, 'owner')
        ON CONFLICT (room_id, user_id) DO NOTHING;

        SELECT jsonb_build_object(
            'id', cr.id,
            'room_type', cr.room_type,
            'reference_id', cr.reference_id,
            'owner_id', cr.owner_id,
            'title', cr.title,
            'status', cr.status,
            'created_at', cr.created_at,
            'updated_at', cr.updated_at,
            'metadata', cr.metadata,
            'participants', coalesce((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', cp.id,
                        'room_id', cp.room_id,
                        'user_id', cp.user_id,
                        'role_in_room', cp.role_in_room,
                        'joined_at', cp.joined_at,
                        'is_muted', false,
                        'full_name', p.full_name,
                        'username', p.username,
                        'avatar_url', p.avatar_url,
                        'station_name', p.station_name
                    )
                )
                FROM chat_participants cp
                LEFT JOIN profiles p ON p.id = cp.user_id
                WHERE cp.room_id = cr.id
            ), '[]'::jsonb)
        ) INTO v_result
        FROM chat_rooms cr
        WHERE cr.id = v_room_id;

        RETURN v_result;
    END IF;

    v_title := coalesce(p_station_name, 'Station Support');

    INSERT INTO chat_rooms (
        room_type,
        reference_id,
        owner_id,
        title,
        status,
        metadata
    ) VALUES (
        'customer_support',
        p_order_id,
        p_owner_id,
        v_title,
        'active',
        jsonb_build_object(
            'channel', 'customer_owner',
            'order_id', p_order_id,
            'station_name', p_station_name,
            'customer_name', p_customer_name
        )
    ) RETURNING id INTO v_room_id;

    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_customer_id, 'customer')
    ON CONFLICT (room_id, user_id) DO NOTHING;

    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_owner_id, 'owner')
    ON CONFLICT (room_id, user_id) DO NOTHING;

    PERFORM set_config('erefill.internal_system_message', 'on', true);
    INSERT INTO messages (room_id, sender_id, content, message_type)
    VALUES (v_room_id, null, 'Support chat started. You are connected directly with the refill station staff.', 'system');

    SELECT jsonb_build_object(
        'id', cr.id,
        'room_type', cr.room_type,
        'reference_id', cr.reference_id,
        'owner_id', cr.owner_id,
        'title', cr.title,
        'status', cr.status,
        'created_at', cr.created_at,
        'updated_at', cr.updated_at,
        'metadata', cr.metadata,
        'participants', coalesce((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', cp.id,
                    'room_id', cp.room_id,
                    'user_id', cp.user_id,
                    'role_in_room', cp.role_in_room,
                    'joined_at', cp.joined_at,
                    'is_muted', false,
                    'full_name', p.full_name,
                    'username', p.username,
                    'avatar_url', p.avatar_url,
                    'station_name', p.station_name
                )
            )
            FROM chat_participants cp
            LEFT JOIN profiles p ON p.id = cp.user_id
            WHERE cp.room_id = cr.id
        ), '[]'::jsonb)
    ) INTO v_result
    FROM chat_rooms cr
    WHERE cr.id = v_room_id;

    RETURN v_result;
END;
$$;

-- 5. Dedicated RPC: get_or_create_owner_rider_chat_room
CREATE OR REPLACE FUNCTION public.get_or_create_owner_rider_chat_room(
  p_order_id uuid,
  p_owner_id uuid,
  p_rider_id uuid,
  p_station_name text DEFAULT NULL,
  p_rider_name text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_room_id uuid;
    v_result jsonb;
    v_title text;
BEGIN
    IF p_order_id IS NOT NULL THEN
        SELECT cr.id INTO v_room_id
        FROM chat_rooms cr
        WHERE cr.reference_id = p_order_id
          AND cr.room_type = 'rider_dispatch'
        LIMIT 1;
    END IF;

    IF v_room_id IS NULL THEN
        SELECT cr.id INTO v_room_id
        FROM chat_rooms cr
        JOIN chat_participants cp1 ON cp1.room_id = cr.id AND cp1.user_id = p_owner_id
        JOIN chat_participants cp2 ON cp2.room_id = cr.id AND cp2.user_id = p_rider_id
        WHERE cr.room_type = 'rider_dispatch'
          AND cr.status = 'active'
        LIMIT 1;
    END IF;

    IF v_room_id IS NOT NULL THEN
        INSERT INTO chat_participants (room_id, user_id, role_in_room)
        VALUES (v_room_id, p_owner_id, 'owner')
        ON CONFLICT (room_id, user_id) DO NOTHING;

        INSERT INTO chat_participants (room_id, user_id, role_in_room)
        VALUES (v_room_id, p_rider_id, 'rider')
        ON CONFLICT (room_id, user_id) DO NOTHING;

        SELECT jsonb_build_object(
            'id', cr.id,
            'room_type', cr.room_type,
            'reference_id', cr.reference_id,
            'owner_id', cr.owner_id,
            'title', cr.title,
            'status', cr.status,
            'created_at', cr.created_at,
            'updated_at', cr.updated_at,
            'metadata', cr.metadata,
            'participants', coalesce((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', cp.id,
                        'room_id', cp.room_id,
                        'user_id', cp.user_id,
                        'role_in_room', cp.role_in_room,
                        'joined_at', cp.joined_at,
                        'is_muted', false,
                        'full_name', p.full_name,
                        'username', p.username,
                        'avatar_url', p.avatar_url,
                        'station_name', p.station_name
                    )
                )
                FROM chat_participants cp
                LEFT JOIN profiles p ON p.id = cp.user_id
                WHERE cp.room_id = cr.id
            ), '[]'::jsonb)
        ) INTO v_result
        FROM chat_rooms cr
        WHERE cr.id = v_room_id;

        RETURN v_result;
    END IF;

    v_title := coalesce(p_rider_name, 'Rider Dispatch');

    INSERT INTO chat_rooms (
        room_type,
        reference_id,
        owner_id,
        title,
        status,
        metadata
    ) VALUES (
        'rider_dispatch',
        p_order_id,
        p_owner_id,
        v_title,
        'active',
        jsonb_build_object(
            'channel', 'owner_rider',
            'order_id', p_order_id,
            'station_name', p_station_name,
            'rider_name', p_rider_name
        )
    ) RETURNING id INTO v_room_id;

    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_owner_id, 'owner')
    ON CONFLICT (room_id, user_id) DO NOTHING;

    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_rider_id, 'rider')
    ON CONFLICT (room_id, user_id) DO NOTHING;

    PERFORM set_config('erefill.internal_system_message', 'on', true);
    INSERT INTO messages (room_id, sender_id, content, message_type)
    VALUES (v_room_id, null, 'Dispatch channel active between station operations and delivery rider.', 'system');

    SELECT jsonb_build_object(
        'id', cr.id,
        'room_type', cr.room_type,
        'reference_id', cr.reference_id,
        'owner_id', cr.owner_id,
        'title', cr.title,
        'status', cr.status,
        'created_at', cr.created_at,
        'updated_at', cr.updated_at,
        'metadata', cr.metadata,
        'participants', coalesce((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', cp.id,
                    'room_id', cp.room_id,
                    'user_id', cp.user_id,
                    'role_in_room', cp.role_in_room,
                    'joined_at', cp.joined_at,
                    'is_muted', false,
                    'full_name', p.full_name,
                    'username', p.username,
                    'avatar_url', p.avatar_url,
                    'station_name', p.station_name
                )
            )
            FROM chat_participants cp
            LEFT JOIN profiles p ON p.id = cp.user_id
            WHERE cp.room_id = cr.id
        ), '[]'::jsonb)
    ) INTO v_result
    FROM chat_rooms cr
    WHERE cr.id = v_room_id;

    RETURN v_result;
END;
$$;

-- 6. Optimized get_my_chat_rooms RPC
CREATE OR REPLACE FUNCTION public.get_my_chat_rooms()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id uuid;
    v_result jsonb;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN '[]'::jsonb;
    END IF;

    WITH user_rooms AS (
        SELECT DISTINCT cr.*
        FROM public.chat_rooms cr
        JOIN public.chat_participants cp ON cp.room_id = cr.id
        WHERE cp.user_id = v_user_id
    ),
    room_last_messages AS (
        SELECT DISTINCT ON (room_id)
            room_id,
            jsonb_build_object(
                'id', id,
                'room_id', room_id,
                'content', content,
                'sender_id', sender_id,
                'message_type', message_type,
                'created_at', created_at
            ) AS last_message
        FROM public.messages
        WHERE deleted_at IS NULL
        ORDER BY room_id, created_at DESC
    ),
    room_unread_counts AS (
        SELECT 
            m.room_id,
            count(*) AS unread_count
        FROM public.messages m
        JOIN public.chat_participants cp ON cp.room_id = m.room_id AND cp.user_id = v_user_id
        WHERE m.sender_id != v_user_id
          AND NOT m.read_by @> jsonb_build_array(v_user_id::text)
          AND m.deleted_at IS NULL
        GROUP BY m.room_id
    ),
    room_participants AS (
        SELECT 
            cp.room_id,
            jsonb_agg(
                jsonb_build_object(
                    'id', cp.id,
                    'room_id', cp.room_id,
                    'user_id', cp.user_id,
                    'role_in_room', cp.role_in_room,
                    'joined_at', cp.joined_at,
                    'full_name', p.full_name,
                    'username', p.username,
                    'avatar_url', p.avatar_url,
                    'station_name', p.station_name
                )
            ) AS participants
        FROM public.chat_participants cp
        JOIN public.profiles p ON p.id = cp.user_id
        GROUP BY cp.room_id
    )
    SELECT 
        jsonb_agg(
            jsonb_build_object(
                'id', ur.id,
                'room_type', ur.room_type,
                'reference_id', ur.reference_id,
                'status', ur.status,
                'owner_id', ur.owner_id,
                'title', ur.title,
                'created_at', ur.created_at,
                'updated_at', ur.updated_at,
                'metadata', ur.metadata,
                'last_message', lmf.last_message,
                'unread_count', coalesce(ruc.unread_count, 0),
                'participants', coalesce(rp.participants, '[]'::jsonb)
            )
            ORDER BY ur.updated_at DESC
        )
    INTO v_result
    FROM user_rooms ur
    LEFT JOIN room_last_messages lmf ON lmf.room_id = ur.id
    LEFT JOIN room_unread_counts ruc ON ruc.room_id = ur.id
    LEFT JOIN room_participants rp ON rp.room_id = ur.id;

    RETURN coalesce(v_result, '[]'::jsonb);
END;
$$;

-- 7. Permissions
GRANT ALL ON FUNCTION public.get_or_create_customer_rider_chat_room(uuid, uuid, uuid, text, text) TO authenticated, service_role;
GRANT ALL ON FUNCTION public.get_or_create_customer_owner_chat_room(uuid, uuid, uuid, text, text) TO authenticated, service_role;
GRANT ALL ON FUNCTION public.get_or_create_owner_rider_chat_room(uuid, uuid, uuid, text, text) TO authenticated, service_role;
GRANT ALL ON FUNCTION public.get_my_chat_rooms() TO authenticated, service_role;

