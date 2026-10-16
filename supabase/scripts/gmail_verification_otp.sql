-- Use Supabase Auth's email-change verification flow. Never generate or expose
-- verification codes from an application RPC.
-- Configure the Supabase "Change Email" and "Confirm signup" templates to
-- include {{ .Token }}. Secure email changes can require both email addresses.

DROP FUNCTION IF EXISTS public.request_gmail_verification_otp(text);
DROP FUNCTION IF EXISTS public.verify_gmail_otp(text, text);
DROP TABLE IF EXISTS public.email_verifications;

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS gmail_verified_at;

CREATE OR REPLACE FUNCTION public.sync_profile_email_after_auth_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.profiles
  SET email = NEW.email
  WHERE id = NEW.id
    AND email IS DISTINCT FROM NEW.email;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_profile_email_after_auth_change()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS sync_profile_email_after_auth_change ON auth.users;
CREATE TRIGGER sync_profile_email_after_auth_change
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  WHEN (OLD.email IS DISTINCT FROM NEW.email)
  EXECUTE FUNCTION public.sync_profile_email_after_auth_change();
