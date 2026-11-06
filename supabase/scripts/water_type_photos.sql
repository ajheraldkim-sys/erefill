-- Migration: Water type photos & Realtime sync
--
-- Admins upload a product photo per water type (stored in the public
-- product_images bucket under water_types/). It replaces the icon picker;
-- icon_key stays as the fallback for types without a photo.

ALTER TABLE public.water_types
  ADD COLUMN IF NOT EXISTS photo_url text;

-- Full replica identity so update events contain the entire row including photo_url
ALTER TABLE public.water_types REPLICA IDENTITY FULL;

-- Ensure public/authenticated users can SELECT from water_types so Realtime broadcasts
ALTER TABLE public.water_types ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'water_types' AND policyname = 'Anyone can view water types'
  ) THEN
    CREATE POLICY "Anyone can view water types"
      ON public.water_types FOR SELECT
      USING (true);
  END IF;
END $$;

-- Enable Supabase Realtime broadcast for water_types
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'water_types'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.water_types;
    END IF;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
