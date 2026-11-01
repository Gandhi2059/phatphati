-- Migration 001: Initial Auction Schema
-- Supports Profiles with Admin/Seller & Buyer roles, Admin-generated Buyer IDs, Multi-Round Auctions, Normalized Images, Bids, Idempotent Payments, Notifications, Audit Logs, and Reminder Logs

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. PROFILES TABLE
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    buyer_id TEXT UNIQUE, -- Custom Admin-generated Buyer ID (e.g. BUYER-101)
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    role TEXT NOT NULL CHECK (role IN ('buyer', 'admin', 'seller')), -- Admin & Seller share admin capabilities
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure buyer_id column exists if table pre-existed
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS buyer_id TEXT UNIQUE;

-- Enable RLS for profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;
CREATE POLICY "Profiles are viewable by authenticated users" 
    ON public.profiles FOR SELECT 
    TO authenticated 
    USING (true);

DROP POLICY IF EXISTS "Admins can insert or update buyer profiles" ON public.profiles;
CREATE POLICY "Admins can insert or update buyer profiles" 
    ON public.profiles FOR ALL 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND (profiles.role = 'admin' OR profiles.role = 'seller')
        )
        OR auth.uid() = id
    );

-- 2. AUCTIONS TABLE (Admin & Seller manage auctions)
CREATE TABLE IF NOT EXISTS public.auctions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    starting_price NUMERIC(12,2) NOT NULL CHECK (starting_price >= 0),
    min_increment NUMERIC(12,2) NOT NULL DEFAULT 5000.00 CHECK (min_increment > 0),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'upcoming', 'live', 'secured', 'cancelled')),
    reopen_duration_minutes INT NOT NULL DEFAULT 30,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.auctions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auctions are viewable by authenticated users" ON public.auctions;
CREATE POLICY "Auctions are viewable by authenticated users" 
    ON public.auctions FOR SELECT 
    TO authenticated 
    USING (true);

DROP POLICY IF EXISTS "Admins and Sellers can insert or update auctions" ON public.auctions;
CREATE POLICY "Admins and Sellers can insert or update auctions" 
    ON public.auctions FOR ALL 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND (profiles.role = 'admin' OR profiles.role = 'seller')
        )
    );

-- 3. AUCTION IMAGES TABLE
CREATE TABLE IF NOT EXISTS public.auction_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auction_id UUID NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    is_cover BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.auction_images ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auction images are viewable by authenticated users" ON public.auction_images;
CREATE POLICY "Auction images are viewable by authenticated users" 
    ON public.auction_images FOR SELECT 
    TO authenticated 
    USING (true);

DROP POLICY IF EXISTS "Admins and Sellers can manage auction images" ON public.auction_images;
CREATE POLICY "Admins and Sellers can manage auction images" 
    ON public.auction_images FOR ALL 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND (profiles.role = 'admin' OR profiles.role = 'seller')
        )
    );

-- 4. AUCTION ROUNDS TABLE
CREATE TABLE IF NOT EXISTS public.auction_rounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auction_id UUID NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
    round_number INT NOT NULL DEFAULT 1,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'live', 'ended', 'winner_pending_deposit', 'secured', 'expired')),
    current_highest_bid NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    highest_bidder_id UUID REFERENCES public.profiles(id),
    winning_bid NUMERIC(12,2),
    deposit_required NUMERIC(12,2),
    deposit_deadline TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT check_round_times CHECK (end_at > start_at)
);

ALTER TABLE public.auction_rounds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auction rounds are viewable by authenticated users" ON public.auction_rounds;
CREATE POLICY "Auction rounds are viewable by authenticated users" 
    ON public.auction_rounds FOR SELECT 
    TO authenticated 
    USING (true);

DROP POLICY IF EXISTS "Admins and Sellers can modify auction rounds" ON public.auction_rounds;
CREATE POLICY "Admins and Sellers can modify auction rounds" 
    ON public.auction_rounds FOR ALL 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND (profiles.role = 'admin' OR profiles.role = 'seller')
        )
    );

-- 5. BIDS TABLE
CREATE TABLE IF NOT EXISTS public.bids (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id UUID NOT NULL REFERENCES public.auction_rounds(id) ON DELETE CASCADE,
    auction_id UUID NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
    bidder_id UUID NOT NULL REFERENCES public.profiles(id),
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.bids ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Bids viewable by authenticated users" ON public.bids;
CREATE POLICY "Bids viewable by authenticated users" 
    ON public.bids FOR SELECT 
    TO authenticated 
    USING (true);

DROP POLICY IF EXISTS "Buyers place bids" ON public.bids;
CREATE POLICY "Buyers place bids" 
    ON public.bids FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid() = bidder_id);

-- 6. DEPOSIT PAYMENTS TABLE
CREATE TABLE IF NOT EXISTS public.deposit_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key TEXT UNIQUE NOT NULL,
    round_id UUID NOT NULL REFERENCES public.auction_rounds(id) ON DELETE CASCADE,
    auction_id UUID NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
    buyer_id UUID NOT NULL REFERENCES public.profiles(id),
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    provider_transaction_id TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'failed', 'expired')),
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.deposit_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own payments" ON public.deposit_payments;
CREATE POLICY "Users view own payments" 
    ON public.deposit_payments FOR SELECT 
    TO authenticated 
    USING (auth.uid() = buyer_id OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role = 'admin' OR role = 'seller')));

-- 7. NOTIFICATIONS TABLE
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('auction_started', 'leading_bid', 'outbid', 'auction_ending', 'auction_won', 'deposit_required', 'deposit_reminder', 'deposit_paid', 'deposit_expired', 'auction_reopened', 'admin_alert')),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    entity_type TEXT NOT NULL DEFAULT 'auction',
    entity_id UUID NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own notifications" ON public.notifications;
CREATE POLICY "Users view own notifications" 
    ON public.notifications FOR SELECT 
    TO authenticated 
    USING (auth.uid() = user_id);

-- 8. AUDIT LOGS TABLE
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES public.profiles(id),
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins view audit logs" ON public.audit_logs;
CREATE POLICY "Admins view audit logs" 
    ON public.audit_logs FOR SELECT 
    TO authenticated 
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role = 'admin' OR role = 'seller')));

-- 9. AUCTION REMINDER LOGS TABLE
CREATE TABLE IF NOT EXISTS public.auction_reminder_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id UUID NOT NULL REFERENCES public.auction_rounds(id) ON DELETE CASCADE,
    reminder_type TEXT NOT NULL CHECK (reminder_type IN ('initial', '10_minutes_remaining', '5_minutes_remaining', '1_minute_remaining')),
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_round_reminder UNIQUE(round_id, reminder_type)
);

ALTER TABLE public.auction_reminder_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "System views reminder logs" ON public.auction_reminder_logs;
CREATE POLICY "System views reminder logs" 
    ON public.auction_reminder_logs FOR SELECT 
    TO authenticated 
    USING (true);
