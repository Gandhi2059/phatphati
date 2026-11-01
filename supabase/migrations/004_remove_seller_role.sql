-- Migration 004: Remove Seller Role & Restrict Roles to Admin and Buyer Only

-- 1. Update any existing seller roles in profiles table to admin
UPDATE public.profiles SET role = 'admin' WHERE role = 'seller';

-- 2. Drop legacy CHECK constraint on profiles.role and add updated CHECK constraint
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('buyer', 'admin'));

-- 3. Replace RLS Policies to remove seller references

-- PROFILES POLICY
DROP POLICY IF EXISTS "Admins can insert or update buyer profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admins or self insert update profiles" ON public.profiles;
CREATE POLICY "Admins can insert or update buyer profiles" 
    ON public.profiles FOR ALL 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
        )
        OR auth.uid() = id
    );

-- AUCTIONS POLICY
DROP POLICY IF EXISTS "Admins and Sellers can insert or update auctions" ON public.auctions;
DROP POLICY IF EXISTS "Admins can insert or update auctions" ON public.auctions;
CREATE POLICY "Admins can insert or update auctions" 
    ON public.auctions FOR ALL 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
        )
    );

-- AUCTION IMAGES POLICY
DROP POLICY IF EXISTS "Admins and Sellers can manage auction images" ON public.auction_images;
DROP POLICY IF EXISTS "Admins can manage auction images" ON public.auction_images;
CREATE POLICY "Admins can manage auction images" 
    ON public.auction_images FOR ALL 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
        )
    );

-- AUCTION ROUNDS POLICY
DROP POLICY IF EXISTS "Admins and Sellers can modify auction rounds" ON public.auction_rounds;
DROP POLICY IF EXISTS "Admins can modify auction rounds" ON public.auction_rounds;
CREATE POLICY "Admins can modify auction rounds" 
    ON public.auction_rounds FOR ALL 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
        )
    );

-- DEPOSIT PAYMENTS POLICY
DROP POLICY IF EXISTS "Users view own payments" ON public.deposit_payments;
CREATE POLICY "Users view own payments" 
    ON public.deposit_payments FOR SELECT 
    TO authenticated 
    USING (
        auth.uid() = buyer_id 
        OR EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- AUDIT LOGS POLICY
DROP POLICY IF EXISTS "Admins view audit logs" ON public.audit_logs;
CREATE POLICY "Admins view audit logs" 
    ON public.audit_logs FOR SELECT 
    TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- 4. OVERLOADED PLACE_BID RPC (Supports p_auction_id and p_round_id)
DROP FUNCTION IF EXISTS public.place_bid(UUID, NUMERIC) CASCADE;
CREATE OR REPLACE FUNCTION public.place_bid(
    p_auction_id UUID,
    p_amount NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_bidder_id UUID := auth.uid();
    v_round RECORD;
    v_auction RECORD;
    v_prev_highest_bidder UUID;
    v_prev_highest_bid NUMERIC;
    v_min_next_bid NUMERIC;
    v_server_now TIMESTAMPTZ := transaction_timestamp();
    v_bid_id UUID;
BEGIN
    IF v_bidder_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to place a bid.';
    END IF;

    -- Lock latest active round for target auction
    SELECT * INTO v_round
    FROM public.auction_rounds
    WHERE auction_id = p_auction_id
    ORDER BY round_number DESC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found for specified auction.';
    END IF;

    -- Fetch parent auction for min_increment and title
    SELECT * INTO v_auction
    FROM public.auctions
    WHERE id = p_auction_id;

    -- Server time check: START TIME
    IF v_server_now < v_round.start_at THEN
        RAISE EXCEPTION 'This auction has not started yet.';
    END IF;

    -- Server time check: END TIME
    IF v_server_now >= v_round.end_at OR v_round.status != 'live' THEN
        RAISE EXCEPTION 'This auction has already ended.';
    END IF;

    -- Minimum next bid logic
    IF v_round.current_highest_bid = 0 OR v_round.current_highest_bid IS NULL THEN
        v_min_next_bid := v_auction.starting_price;
    ELSE
        v_min_next_bid := v_round.current_highest_bid + v_auction.min_increment;
    END IF;

    IF p_amount < v_min_next_bid THEN
        RAISE EXCEPTION 'Bid amount of Rs. % is below the minimum required bid of Rs. %', p_amount, v_min_next_bid;
    END IF;

    -- Track previous highest bidder
    v_prev_highest_bidder := v_round.highest_bidder_id;
    v_prev_highest_bid := v_round.current_highest_bid;

    -- Insert valid bid
    INSERT INTO public.bids (round_id, auction_id, bidder_id, amount, created_at)
    VALUES (v_round.id, p_auction_id, v_bidder_id, p_amount, v_server_now)
    RETURNING id INTO v_bid_id;

    -- Update round current highest bid and leader
    UPDATE public.auction_rounds
    SET current_highest_bid = p_amount,
        highest_bidder_id = v_bidder_id,
        updated_at = v_server_now
    WHERE id = v_round.id;

    -- Notification 1: Leading Bid for Current Bidder
    INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
    VALUES (
        v_bidder_id,
        'leading_bid',
        '🏆 You''re leading!',
        FORMAT('Your bid of Rs. %s is currently the highest bid for %s.', TO_CHAR(p_amount, 'FM999,999,990'), v_auction.title),
        'auction',
        p_auction_id
    );

    -- Notification 2: Instant Outbid Notification for Previous Highest Bidder (if distinct)
    IF v_prev_highest_bidder IS NOT NULL AND v_prev_highest_bidder != v_bidder_id THEN
        INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
        VALUES (
            v_prev_highest_bidder,
            'outbid',
            'You''ve been outbid',
            FORMAT('You''ve been outbid on %s. Current highest bid: Rs. %s.', v_auction.title, TO_CHAR(p_amount, 'FM999,999,990')),
            'auction',
            p_auction_id
        );
    END IF;

    -- Audit Log entry
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
    VALUES (
        v_bidder_id,
        'BID_ACCEPTED',
        'auction_round',
        v_round.id,
        jsonb_build_object(
            'amount', p_amount,
            'auction_id', p_auction_id,
            'round_number', v_round.round_number
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'bid_id', v_bid_id,
        'amount', p_amount,
        'current_highest_bid', p_amount,
        'min_next_bid', p_amount + v_auction.min_increment
    );
END;
$$;
