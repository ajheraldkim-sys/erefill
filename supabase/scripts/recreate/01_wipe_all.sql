-- ==============================================================================
-- Step 1: Wipe all data, storage objects, auth accounts, and drop public schema
-- ==============================================================================

-- 1. Remove all uploaded storage files
SET storage.allow_delete_query = 'true';
DELETE FROM storage.objects;

-- 2. Drop and cleanly recreate public schema first (clears all public tables & foreign keys)
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- 3. Re-grant default permissions to Supabase roles
GRANT USAGE, CREATE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;

-- 4. Remove all existing auth identities and accounts (now unblocked by public FKs)
DELETE FROM auth.identities;
DELETE FROM auth.users;

