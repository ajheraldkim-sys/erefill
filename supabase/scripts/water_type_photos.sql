-- Migration: Water type photos
--
-- Admins upload a product photo per water type (stored in the public
-- product_images bucket under water_types/). It replaces the icon picker;
-- icon_key stays as the fallback for types without a photo.

ALTER TABLE public.water_types
  ADD COLUMN IF NOT EXISTS photo_url text;

NOTIFY pgrst, 'reload schema';
