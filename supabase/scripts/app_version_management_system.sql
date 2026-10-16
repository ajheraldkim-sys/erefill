-- ============================================================================
-- EREFILL APPLICATION UPDATE & VERSION MANAGEMENT SYSTEM
-- Production-Ready Centralized Version Enforcement, Semver Comparison & Audit Logs
-- ============================================================================

-- 1. App Releases Catalog & Policy Table
CREATE TABLE IF NOT EXISTS public.app_releases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    platform text NOT NULL CHECK (platform IN ('android', 'ios', 'web', 'all')),
    channel text NOT NULL CHECK (channel IN ('official_apk', 'google_play', 'web_deployment', 'app_store')),
    version text NOT NULL,
    build_number integer NOT NULL CHECK (build_number > 0),
    min_supported_version text NOT NULL,
    min_supported_build integer NOT NULL CHECK (min_supported_build > 0),
    title text NOT NULL,
    release_notes text NOT NULL DEFAULT '',
    update_type text NOT NULL CHECK (update_type IN ('optional', 'mandatory')),
    status text NOT NULL CHECK (status IN ('draft', 'scheduled', 'published', 'deprecated', 'withdrawn')),
    download_url text NOT NULL,
    checksum_sha256 text,
    file_size_bytes bigint,
    is_active boolean NOT NULL DEFAULT false,
    published_at timestamptz,
    published_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Ensure only one active release per platform and channel
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_release_per_platform_channel
    ON public.app_releases (platform, channel)
    WHERE (is_active = true AND status = 'published');

CREATE INDEX IF NOT EXISTS idx_app_releases_status_platform
    ON public.app_releases (status, platform, channel);

CREATE INDEX IF NOT EXISTS idx_app_releases_created_at
    ON public.app_releases (created_at DESC);

-- 2. Release Management Audit Logs
CREATE TABLE IF NOT EXISTS public.app_release_audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    release_id uuid REFERENCES public.app_releases(id) ON DELETE SET NULL,
    admin_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    admin_email text,
    action text NOT NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_release_audit_logs_created_at
    ON public.app_release_audit_logs (created_at DESC);

-- Enable RLS
ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_release_audit_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies for App Releases
-- Public read for active published releases (required by clients on startup)
DROP POLICY IF EXISTS "Public can view active published releases" ON public.app_releases;
CREATE POLICY "Public can view active published releases"
    ON public.app_releases FOR SELECT
    TO anon, authenticated
    USING (is_active = true AND status = 'published');

-- Admins can view all releases
DROP POLICY IF EXISTS "Admins can view all releases" ON public.app_releases;
CREATE POLICY "Admins can view all releases"
    ON public.app_releases FOR SELECT
    TO authenticated
    USING (public.is_admin());

-- Only Admins can modify releases
DROP POLICY IF EXISTS "Admins can insert releases" ON public.app_releases;
CREATE POLICY "Admins can insert releases"
    ON public.app_releases FOR INSERT
    TO authenticated
    WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can update releases" ON public.app_releases;
CREATE POLICY "Admins can update releases"
    ON public.app_releases FOR UPDATE
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can delete draft releases" ON public.app_releases;
CREATE POLICY "Admins can delete draft releases"
    ON public.app_releases FOR DELETE
    TO authenticated
    USING (public.is_admin() AND status = 'draft');

-- RLS Policies for Audit Logs
DROP POLICY IF EXISTS "Admins can view release audit logs" ON public.app_release_audit_logs;
CREATE POLICY "Admins can view release audit logs"
    ON public.app_release_audit_logs FOR SELECT
    TO authenticated
    USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can insert release audit logs" ON public.app_release_audit_logs;
CREATE POLICY "Admins can insert release audit logs"
    ON public.app_release_audit_logs FOR INSERT
    TO authenticated
    WITH CHECK (public.is_admin());

-- 3. Robust Semantic Version Parsing & Comparison
CREATE OR REPLACE FUNCTION public.parse_semver(p_version text)
RETURNS integer[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_clean text;
    v_parts text[];
    v_major int := 0;
    v_minor int := 0;
    v_patch int := 0;
BEGIN
    IF p_version IS NULL OR trim(p_version) = '' THEN
        RETURN ARRAY[0, 0, 0];
    END IF;

    -- Strip leading 'v' or 'V' and anything after '-' or '+' (pre-release/build metadata)
    v_clean := regexp_replace(trim(p_version), '^[vV]', '');
    v_clean := split_part(v_clean, '-', 1);
    v_clean := split_part(v_clean, '+', 1);

    v_parts := string_to_array(v_clean, '.');

    IF array_length(v_parts, 1) >= 1 THEN
        v_major := COALESCE(NULLIF(regexp_replace(v_parts[1], '\D', '', 'g'), '')::int, 0);
    END IF;
    IF array_length(v_parts, 1) >= 2 THEN
        v_minor := COALESCE(NULLIF(regexp_replace(v_parts[2], '\D', '', 'g'), '')::int, 0);
    END IF;
    IF array_length(v_parts, 1) >= 3 THEN
        v_patch := COALESCE(NULLIF(regexp_replace(v_parts[3], '\D', '', 'g'), '')::int, 0);
    END IF;

    RETURN ARRAY[v_major, v_minor, v_patch];
END;
$$;

-- Compare two semantic versions with numeric build numbers
-- Returns:
--  -1 if (v1, b1) < (v2, b2)
--   0 if (v1, b1) = (v2, b2)
--   1 if (v1, b1) > (v2, b2)
CREATE OR REPLACE FUNCTION public.semver_cmp(
    p_v1 text,
    p_b1 integer,
    p_v2 text,
    p_b2 integer
)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    s1 integer[] := public.parse_semver(p_v1);
    s2 integer[] := public.parse_semver(p_v2);
    i integer;
BEGIN
    FOR i IN 1..3 LOOP
        IF s1[i] < s2[i] THEN
            RETURN -1;
        ELSIF s1[i] > s2[i] THEN
            RETURN 1;
        END IF;
    END LOOP;

    -- If semver is identical, compare numeric build numbers
    IF COALESCE(p_b1, 0) < COALESCE(p_b2, 0) THEN
        RETURN -1;
    ELSIF COALESCE(p_b1, 0) > COALESCE(p_b2, 0) THEN
        RETURN 1;
    END IF;

    RETURN 0;
END;
$$;

-- 4. RPC: Get Active Version Policy
CREATE OR REPLACE FUNCTION public.get_active_app_version_policy(
    p_platform text DEFAULT 'android',
    p_channel text DEFAULT 'official_apk'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_release record;
    v_maintenance boolean := false;
BEGIN
    -- Check maintenance mode from system_config
    SELECT COALESCE((value->>0)::boolean, false)
    INTO v_maintenance
    FROM public.system_config
    WHERE key = 'maintenance_mode';

    SELECT *
    INTO v_release
    FROM public.app_releases
    WHERE (platform = p_platform OR platform = 'all')
      AND (channel = p_channel OR channel = 'official_apk')
      AND is_active = true
      AND status = 'published'
    ORDER BY
        CASE WHEN platform = p_platform THEN 0 ELSE 1 END,
        CASE WHEN channel = p_channel THEN 0 ELSE 1 END,
        published_at DESC
    LIMIT 1;

    IF v_release IS NULL THEN
        -- Fallback default policy if no release published yet
        RETURN jsonb_build_object(
            'has_policy', false,
            'maintenance_mode', v_maintenance,
            'message', 'No active version policy configured'
        );
    END IF;

    RETURN jsonb_build_object(
        'has_policy', true,
        'release_id', v_release.id,
        'platform', v_release.platform,
        'channel', v_release.channel,
        'latest_version', v_release.version,
        'latest_build', v_release.build_number,
        'min_supported_version', v_release.min_supported_version,
        'min_supported_build', v_release.min_supported_build,
        'title', v_release.title,
        'release_notes', v_release.release_notes,
        'update_type', v_release.update_type,
        'download_url', v_release.download_url,
        'checksum_sha256', v_release.checksum_sha256,
        'file_size_bytes', v_release.file_size_bytes,
        'published_at', v_release.published_at,
        'maintenance_mode', v_maintenance
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_active_app_version_policy(text, text) TO anon, authenticated;

-- 5. RPC: Check App Version Compatibility
CREATE OR REPLACE FUNCTION public.check_app_version_compatibility(
    p_client_version text,
    p_client_build integer,
    p_platform text DEFAULT 'android',
    p_channel text DEFAULT 'official_apk'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_policy jsonb;
    v_min_version text;
    v_min_build int;
    v_latest_version text;
    v_latest_build int;
    v_update_type text;
    v_is_below_min boolean;
    v_is_below_latest boolean;
    v_maintenance boolean;
BEGIN
    v_policy := public.get_active_app_version_policy(p_platform, p_channel);

    v_maintenance := COALESCE((v_policy->>'maintenance_mode')::boolean, false);
    IF v_maintenance THEN
        RETURN jsonb_build_object(
            'status', 'MAINTENANCE',
            'is_mandatory', true,
            'message', 'eRefill is currently undergoing scheduled system maintenance. Please try again shortly.'
        );
    END IF;

    IF NOT COALESCE((v_policy->>'has_policy')::boolean, false) THEN
        RETURN jsonb_build_object(
            'status', 'VERSION_SUPPORTED',
            'is_mandatory', false,
            'message', 'Version check passed (default policy active)'
        );
    END IF;

    v_min_version := v_policy->>'min_supported_version';
    v_min_build := COALESCE((v_policy->>'min_supported_build')::int, 1);
    v_latest_version := v_policy->>'latest_version';
    v_latest_build := COALESCE((v_policy->>'latest_build')::int, 1);
    v_update_type := v_policy->>'update_type';

    -- Check if client is below minimum supported version
    v_is_below_min := public.semver_cmp(p_client_version, p_client_build, v_min_version, v_min_build) < 0;

    -- Check if client is below latest released version
    v_is_below_latest := public.semver_cmp(p_client_version, p_client_build, v_latest_version, v_latest_build) < 0;

    IF v_is_below_min THEN
        RETURN jsonb_build_object(
            'status', 'UPDATE_REQUIRED',
            'is_mandatory', true,
            'installed_version', p_client_version,
            'installed_build', p_client_build,
            'latest_version', v_latest_version,
            'latest_build', v_latest_build,
            'min_supported_version', v_min_version,
            'min_supported_build', v_min_build,
            'title', v_policy->>'title',
            'release_notes', v_policy->>'release_notes',
            'download_url', v_policy->>'download_url',
            'checksum_sha256', v_policy->>'checksum_sha256',
            'file_size_bytes', v_policy->'file_size_bytes',
            'published_at', v_policy->>'published_at',
            'checked_at', now(),
            'message', 'A critical security or platform update is required to continue using eRefill.'
        );
    ELSIF v_is_below_latest THEN
        RETURN jsonb_build_object(
            'status', 'UPDATE_AVAILABLE',
            'is_mandatory', (v_update_type = 'mandatory'),
            'installed_version', p_client_version,
            'installed_build', p_client_build,
            'latest_version', v_latest_version,
            'latest_build', v_latest_build,
            'min_supported_version', v_min_version,
            'min_supported_build', v_min_build,
            'title', v_policy->>'title',
            'release_notes', v_policy->>'release_notes',
            'download_url', v_policy->>'download_url',
            'checksum_sha256', v_policy->>'checksum_sha256',
            'file_size_bytes', v_policy->'file_size_bytes',
            'published_at', v_policy->>'published_at',
            'checked_at', now(),
            'message', 'A new version of eRefill is available with performance improvements and new features.'
        );
    ELSE
        RETURN jsonb_build_object(
            'status', 'VERSION_SUPPORTED',
            'is_mandatory', false,
            'installed_version', p_client_version,
            'installed_build', p_client_build,
            'latest_version', v_latest_version,
            'latest_build', v_latest_build,
            'checked_at', now(),
            'message', 'Your eRefill installation is up to date.'
        );
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_app_version_compatibility(text, integer, text, text) TO anon, authenticated;

-- 6. RPC: Publish Release (Admin-Only)
CREATE OR REPLACE FUNCTION public.publish_app_release(p_release_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_id uuid := auth.uid();
    v_admin_email text;
    v_release record;
BEGIN
    IF v_admin_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Only system administrators can publish releases.';
    END IF;

    SELECT email INTO v_admin_email FROM auth.users WHERE id = v_admin_id;

    SELECT * INTO v_release FROM public.app_releases WHERE id = p_release_id;
    IF v_release IS NULL THEN
        RAISE EXCEPTION 'Release not found.';
    END IF;

    -- Validate download URL format (Must be valid HTTPS)
    IF v_release.download_url NOT LIKE 'https://%' THEN
        RAISE EXCEPTION 'Security error: Download URL must use secure HTTPS protocol.';
    END IF;

    -- Validate semantic version format
    IF array_length(public.parse_semver(v_release.version), 1) < 3 THEN
        RAISE EXCEPTION 'Invalid semantic version format for release: %', v_release.version;
    END IF;

    -- Deactivate any current active release for this platform and channel
    UPDATE public.app_releases
    SET is_active = false,
        status = 'deprecated',
        updated_at = now()
    WHERE platform = v_release.platform
      AND channel = v_release.channel
      AND id != p_release_id
      AND is_active = true;

    -- Activate and publish this release
    UPDATE public.app_releases
    SET is_active = true,
        status = 'published',
        published_at = now(),
        published_by = v_admin_id,
        updated_at = now()
    WHERE id = p_release_id;

    -- Record Audit Log
    INSERT INTO public.app_release_audit_logs (
        release_id,
        admin_id,
        admin_email,
        action,
        details
    ) VALUES (
        p_release_id,
        v_admin_id,
        v_admin_email,
        'publish_release',
        jsonb_build_object(
            'version', v_release.version,
            'build_number', v_release.build_number,
            'min_supported_version', v_release.min_supported_version,
            'min_supported_build', v_release.min_supported_build,
            'update_type', v_release.update_type,
            'platform', v_release.platform,
            'channel', v_release.channel,
            'download_url', v_release.download_url
        )
    );

    -- Broadcast system-wide real-time notification if mandatory update
    IF v_release.update_type = 'mandatory' THEN
        INSERT INTO public.system_notifications (
            user_id,
            title,
            content,
            type,
            priority,
            metadata
        )
        SELECT
            id,
            'Important eRefill App Update Required',
            'Version ' || v_release.version || ' is now required to continue using eRefill.',
            'system_alert',
            'high',
            jsonb_build_object(
                'action', 'app_update',
                'release_id', p_release_id,
                'version', v_release.version,
                'is_mandatory', true
            )
        FROM auth.users;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'release_id', p_release_id,
        'version', v_release.version,
        'status', 'published'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.publish_app_release(uuid) TO authenticated;

-- 7. Ensure app_releases is in Realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND tablename = 'app_releases'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_releases;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not add app_releases to realtime publication: %', SQLERRM;
END $$;

-- 8. Seed Initial Authoritative Release (v1.0.0+1)
INSERT INTO public.app_releases (
    platform,
    channel,
    version,
    build_number,
    min_supported_version,
    min_supported_build,
    title,
    release_notes,
    update_type,
    status,
    download_url,
    is_active,
    published_at
)
VALUES (
    'android',
    'official_apk',
    '1.0.0',
    1,
    '1.0.0',
    1,
    'eRefill Official Release v1.0.0',
    '• Real-time delivery fee calculation and order tracking\n• In-app chat and notifications\n• Account security and password management',
    'optional',
    'published',
    'https://raw.githubusercontent.com/ajheraldkim-sys/erefill/main/web/downloads/eRefill.apk',
    true,
    now()
)
ON CONFLICT DO NOTHING;

