-- ==============================================================================
-- Seed Alkaline and Mineral Products for Stations
-- ==============================================================================

INSERT INTO public.products (
  owner_id, name, description, price, category, is_available, container_size, preparation_minutes
) VALUES (
  'e2c957bd-f90d-4cf6-a022-ab168245c1e6',
  'Alkaline Water Refill',
  'Ionized pH 8.5-9.0 alkaline drinking water refill',
  35.00,
  'Alkaline',
  true,
  '5 gallon',
  15
);

INSERT INTO public.products (
  owner_id, name, description, price, category, is_available, container_size, preparation_minutes
) VALUES (
  'e3ea185e-8685-4373-8271-857b33e2cf14',
  'Mineral Water Refill',
  'Natural mineral-rich crisp drinking water refill',
  25.00,
  'Mineral',
  true,
  '5 gallon',
  15
);

UPDATE public.profiles
SET primary_water_type = 'Alkaline Water'::water_type_option
WHERE id = 'e2c957bd-f90d-4cf6-a022-ab168245c1e6';

UPDATE public.profiles
SET primary_water_type = 'Mineral Water'::water_type_option
WHERE id = 'e3ea185e-8685-4373-8271-857b33e2cf14';

