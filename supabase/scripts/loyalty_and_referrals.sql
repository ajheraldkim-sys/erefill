-- ============================================================================
-- eRefill Customer Loyalty & Referral Program
-- File: supabase/scripts/loyalty_and_referrals.sql
-- ============================================================================

-- 1. Customer Loyalty Profiles
CREATE TABLE IF NOT EXISTS customer_loyalty_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    referral_code TEXT UNIQUE NOT NULL,
    points_balance INT NOT NULL DEFAULT 50 CHECK (points_balance >= 0),
    total_earned INT NOT NULL DEFAULT 50 CHECK (total_earned >= 0),
    total_redeemed INT NOT NULL DEFAULT 0 CHECK (total_redeemed >= 0),
    referred_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for speedy referral lookups
CREATE INDEX IF NOT EXISTS idx_loyalty_referral_code 
    ON customer_loyalty_profiles(referral_code);

-- 2. Customer Reward Vouchers
CREATE TABLE IF NOT EXISTS customer_reward_vouchers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    discount_amount NUMERIC NOT NULL DEFAULT 0.00,
    points_cost INT NOT NULL DEFAULT 0,
    is_delivery_discount BOOLEAN NOT NULL DEFAULT false,
    is_used BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days')
);

CREATE INDEX IF NOT EXISTS idx_reward_vouchers_user_unused 
    ON customer_reward_vouchers(user_id, is_used);

-- 3. Loyalty Transactions Log
CREATE TABLE IF NOT EXISTS loyalty_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    points INT NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_user 
    ON loyalty_transactions(user_id, created_at DESC);

-- Enable Row Level Security
ALTER TABLE customer_loyalty_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_reward_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Profiles
DROP POLICY IF EXISTS "Users can view their own loyalty profile" ON customer_loyalty_profiles;
CREATE POLICY "Users can view their own loyalty profile"
    ON customer_loyalty_profiles FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own loyalty profile" ON customer_loyalty_profiles;
CREATE POLICY "Users can insert their own loyalty profile"
    ON customer_loyalty_profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own loyalty profile" ON customer_loyalty_profiles;
CREATE POLICY "Users can update their own loyalty profile"
    ON customer_loyalty_profiles FOR UPDATE
    USING (auth.uid() = user_id);

-- RLS Policies: Reward Vouchers
DROP POLICY IF EXISTS "Users can view their own vouchers" ON customer_reward_vouchers;
CREATE POLICY "Users can view their own vouchers"
    ON customer_reward_vouchers FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own vouchers" ON customer_reward_vouchers;
CREATE POLICY "Users can insert their own vouchers"
    ON customer_reward_vouchers FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own vouchers" ON customer_reward_vouchers;
CREATE POLICY "Users can update their own vouchers"
    ON customer_reward_vouchers FOR UPDATE
    USING (auth.uid() = user_id);

-- RLS Policies: Transactions
DROP POLICY IF EXISTS "Users can view their own transactions" ON loyalty_transactions;
CREATE POLICY "Users can view their own transactions"
    ON loyalty_transactions FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert transactions" ON loyalty_transactions;
CREATE POLICY "Users can insert transactions"
    ON loyalty_transactions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

GRANT ALL ON TABLE customer_loyalty_profiles TO authenticated, service_role;
GRANT ALL ON TABLE customer_reward_vouchers TO authenticated, service_role;
GRANT ALL ON TABLE loyalty_transactions TO authenticated, service_role;

