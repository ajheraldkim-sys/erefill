-- Migration: Create rider_payout_requests table with RLS and indexes
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

-- Indexes
CREATE INDEX IF NOT EXISTS idx_rider_payout_requests_rider_id ON public.rider_payout_requests(rider_id);
CREATE INDEX IF NOT EXISTS idx_rider_payout_requests_owner_id ON public.rider_payout_requests(owner_id);
CREATE INDEX IF NOT EXISTS idx_rider_payout_requests_status ON public.rider_payout_requests(status);

-- RLS
ALTER TABLE public.rider_payout_requests ENABLE ROW LEVEL SECURITY;

-- Riders can view their own payout requests
DROP POLICY IF EXISTS "Riders can view own payout requests" ON public.rider_payout_requests;
CREATE POLICY "Riders can view own payout requests"
  ON public.rider_payout_requests
  FOR SELECT
  TO authenticated
  USING (auth.uid() = rider_id);

-- Riders can insert their own payout requests
DROP POLICY IF EXISTS "Riders can insert own payout requests" ON public.rider_payout_requests;
CREATE POLICY "Riders can insert own payout requests"
  ON public.rider_payout_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = rider_id);

-- Owners can view payout requests for their stations
DROP POLICY IF EXISTS "Owners can view station payout requests" ON public.rider_payout_requests;
CREATE POLICY "Owners can view station payout requests"
  ON public.rider_payout_requests
  FOR SELECT
  TO authenticated
  USING (auth.uid() = owner_id);

-- Owners can update payout requests for their stations
DROP POLICY IF EXISTS "Owners can update station payout requests" ON public.rider_payout_requests;
CREATE POLICY "Owners can update station payout requests"
  ON public.rider_payout_requests
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = owner_id);

-- Admins full access
DROP POLICY IF EXISTS "Admins full access on rider_payout_requests" ON public.rider_payout_requests;
CREATE POLICY "Admins full access on rider_payout_requests"
  ON public.rider_payout_requests
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

GRANT ALL ON TABLE public.rider_payout_requests TO authenticated;
GRANT ALL ON TABLE public.rider_payout_requests TO service_role;

