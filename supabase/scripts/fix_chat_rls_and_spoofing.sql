-- Fix guard_system_message_spoofing, create_order_chat_room, create_support_chat_room, and RLS policies

CREATE OR REPLACE FUNCTION public.guard_system_message_spoofing()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF (NEW.sender_id IS NULL OR NEW.message_type = 'system') THEN
    IF current_setting('erefill.internal_system_message', true) = 'on' THEN
      RETURN NEW;
    END IF;
    IF auth.role() IS DISTINCT FROM 'service_role' AND NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: Only system service or administrator can issue system messages.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_order_chat_room(
  p_order_id uuid,
  p_customer_id uuid,
  p_owner_id uuid,
  p_rider_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
        -- Ensure participants exist
        insert into chat_participants (room_id, user_id, role_in_room)
        values (v_room_id, p_customer_id, 'customer')
        on conflict (room_id, user_id) do nothing;

        insert into chat_participants (room_id, user_id, role_in_room)
        values (v_room_id, p_owner_id, 'owner')
        on conflict (room_id, user_id) do nothing;

        if p_rider_id is not null then
            insert into chat_participants (room_id, user_id, role_in_room)
            values (v_room_id, p_rider_id, 'rider')
            on conflict (room_id, user_id) do nothing;
        end if;

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
    on conflict (room_id, user_id) do nothing;
    
    -- Add owner as participant
    insert into chat_participants (room_id, user_id, role_in_room)
    values (v_room_id, p_owner_id, 'owner')
    on conflict (room_id, user_id) do nothing;
    
    -- Add rider as participant if provided
    if p_rider_id is not null then
        insert into chat_participants (room_id, user_id, role_in_room)
        values (v_room_id, p_rider_id, 'rider')
        on conflict (room_id, user_id) do nothing;
    end if;
    
    -- Allow system message insert in this transaction
    perform set_config('erefill.internal_system_message', 'on', true);

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

CREATE OR REPLACE FUNCTION public.create_support_chat_room(
  p_customer_id uuid,
  p_owner_id uuid,
  p_title text DEFAULT 'Customer Support'::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_room_id UUID;
    v_result JSONB;
BEGIN
    SELECT cr.id INTO v_room_id
    FROM chat_rooms cr
    JOIN chat_participants cp1 ON cr.id = cp1.room_id AND cp1.user_id = p_customer_id
    JOIN chat_participants cp2 ON cr.id = cp2.room_id AND cp2.user_id = p_owner_id
    WHERE cr.room_type = 'customer_support'
    AND cr.status = 'active'
    LIMIT 1;
    
    IF v_room_id IS NOT NULL THEN
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
    
    INSERT INTO chat_rooms (room_type, owner_id, title, status)
    VALUES ('customer_support', p_owner_id, p_title, 'active')
    RETURNING id INTO v_room_id;
    
    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_customer_id, 'customer')
    ON CONFLICT (room_id, user_id) DO NOTHING;
    
    INSERT INTO chat_participants (room_id, user_id, role_in_room)
    VALUES (v_room_id, p_owner_id, 'owner')
    ON CONFLICT (room_id, user_id) DO NOTHING;
    
    PERFORM set_config('erefill.internal_system_message', 'on', true);

    INSERT INTO messages (room_id, content, message_type)
    VALUES (v_room_id, 'Support chat started. You can now message the station owner directly.', 'system');
    
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

-- RLS Policy: Allow order participants (customer, owner, assigned rider) to create order chat rooms
DROP POLICY IF EXISTS "Order participants can create order chat rooms" ON public.chat_rooms;
CREATE POLICY "Order participants can create order chat rooms" ON public.chat_rooms
FOR INSERT WITH CHECK (
  room_type = 'order_delivery' AND (
    auth.uid() = owner_id OR
    EXISTS (
      SELECT 1 FROM public.orders
      WHERE orders.id = chat_rooms.reference_id
      AND (
        orders.customer_id = auth.uid() OR
        orders.owner_id = auth.uid() OR
        orders.assigned_rider_id = auth.uid()
      )
    )
  )
);

-- RLS Policy: Allow order participants to join order chat rooms
DROP POLICY IF EXISTS "Order participants can join order chat rooms" ON public.chat_participants;
CREATE POLICY "Order participants can join order chat rooms" ON public.chat_participants
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.chat_rooms cr
    JOIN public.orders o ON o.id = cr.reference_id
    WHERE cr.id = chat_participants.room_id
    AND cr.room_type = 'order_delivery'
    AND (
      o.customer_id = auth.uid() OR
      o.owner_id = auth.uid() OR
      o.assigned_rider_id = auth.uid()
    )
  )
);

GRANT ALL ON FUNCTION public.create_order_chat_room(uuid, uuid, uuid, uuid) TO authenticated, service_role;
GRANT ALL ON FUNCTION public.create_support_chat_room(uuid, uuid, text) TO authenticated, service_role;

