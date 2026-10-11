-- Add station_id generated column to orders table
-- This provides full backward and forward compatibility for all queries referencing orders.station_id
ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS station_id uuid GENERATED ALWAYS AS (owner_id) STORED;

