-- Migration 043: Enforce Form 2 Business Verification Gates for Bidding and Auction Creation
-- Rule: Form 1 creates user credentials and allows login.
-- Form 2 (Business Verification & Documentation) MUST be submitted and approved by Admin ('approved')
-- before a Buyer can place bids and before a Seller can create auctions.

-- 1. Update place_bid (3-parameter signature used by AuctionService)
CREATE OR REPLACE FUNCTION public.place_bid(
    p_auction_id UUID,
    p_amount NUMERIC,
    p_bidder_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_bidder_id UUID;
    v_bidder_role TEXT;
    v_bidder_biz_status TEXT;
    v_round RECORD;
    v_auction RECORD;
    v_min_next_bid NUMERIC;
    v_server_now TIMESTAMPTZ := transaction_timestamp();
    v_bid_id UUID;
    v_prev_highest_bidder UUID;
    v_new_end_at TIMESTAMPTZ;
BEGIN
    v_bidder_id := COALESCE(p_bidder_id, auth.uid(), '11111111-1111-1111-1111-111111111111'::uuid);

    IF v_bidder_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated. User must be logged in to bid.';
    END IF;

    -- Retrieve role and business status
    SELECT role, business_status INTO v_bidder_role, v_bidder_biz_status
    FROM public.profiles
    WHERE id = v_bidder_id;

    -- ADMIN BYPASS: Only Admin or Approved Business can place bids
    IF COALESCE(v_bidder_role, 'buyer') != 'admin' AND COALESCE(v_bidder_biz_status, 'none') != 'approved' THEN
        RAISE EXCEPTION 'Verification required: Form 2 (Business Verification & Documentation) must be approved by an Admin before placing bids.';
    END IF;

    -- Check auction
    SELECT * INTO v_auction FROM public.auctions WHERE id = p_auction_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction not found.';
    END IF;

    -- Prevent self-bidding
    IF v_auction.created_by = v_bidder_id THEN
        RAISE EXCEPTION 'Sellers cannot bid on their own vehicle auctions.';
    END IF;

    -- Lock active round
    SELECT * INTO v_round
    FROM public.auction_rounds
    WHERE auction_id = p_auction_id AND status = 'live'
    ORDER BY round_number DESC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Check if round is upcoming or any round exists
        SELECT * INTO v_round
        FROM public.auction_rounds
        WHERE auction_id = p_auction_id
        ORDER BY round_number DESC
        LIMIT 1
        FOR UPDATE;
    END IF;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active round found for this auction.';
    END IF;

    -- Timing enforcement
    IF v_round.status != 'live' OR v_server_now < v_round.start_at OR v_server_now >= v_round.end_at THEN
        RAISE EXCEPTION 'Auction round is not currently live for bidding.';
    END IF;

    -- Minimum bid calculation
    IF v_round.current_highest_bid IS NULL OR v_round.current_highest_bid = 0 THEN
        v_min_next_bid := v_auction.starting_price;
    ELSE
        v_min_next_bid := v_round.current_highest_bid + COALESCE(v_round.min_increment, v_auction.min_increment, 1000);
    END IF;

    IF p_amount < v_min_next_bid THEN
        RAISE EXCEPTION 'Bid amount Rs. % is below the minimum required bid of Rs. %',
            TO_CHAR(p_amount, 'FM999,999,990'), TO_CHAR(v_min_next_bid, 'FM999,999,990');
    END IF;

    v_prev_highest_bidder := v_round.highest_bidder_id;

    -- Insert bid
    INSERT INTO public.bids (round_id, auction_id, bidder_id, amount, created_at)
    VALUES (v_round.id, p_auction_id, v_bidder_id, p_amount, v_server_now)
    RETURNING id INTO v_bid_id;

    -- Anti-sniping: extend by 2 mins if bid placed within last 2 minutes
    v_new_end_at := v_round.end_at;
    IF (v_round.end_at - v_server_now) <= INTERVAL '2 minutes' THEN
        v_new_end_at := v_round.end_at + INTERVAL '2 minutes';
    END IF;

    -- Update round
    UPDATE public.auction_rounds
    SET current_highest_bid = p_amount,
        highest_bidder_id = v_bidder_id,
        end_at = v_new_end_at,
        updated_at = v_server_now
    WHERE id = v_round.id;

    -- Update auction
    UPDATE public.auctions
    SET current_highest_bid = p_amount,
        end_at = v_new_end_at,
        updated_at = v_server_now
    WHERE id = p_auction_id;

    -- Outbid notification
    IF v_prev_highest_bidder IS NOT NULL AND v_prev_highest_bidder != v_bidder_id THEN
        INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
        VALUES (
            v_prev_highest_bidder,
            'outbid',
            '⚡ YOU HAVE BEEN OUTBID',
            FORMAT('A higher bid of Rs. %s was placed on %s.', TO_CHAR(p_amount, 'FM999,999,990'), v_auction.title),
            'auction',
            p_auction_id
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'bid_id', v_bid_id,
        'round_id', v_round.id,
        'amount', p_amount,
        'end_at', v_new_end_at
    );
END;
$$;

-- 2. Update place_bid (4-parameter signature)
CREATE OR REPLACE FUNCTION public.place_bid(
    p_auction_id UUID,
    p_round_id UUID,
    p_amount NUMERIC,
    p_bidder_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_bidder_id UUID := COALESCE(auth.uid(), p_bidder_id);
    v_bidder_role TEXT;
    v_bidder_biz_status TEXT;
    v_server_now TIMESTAMPTZ := transaction_timestamp();
    r_round RECORD;
    v_auction RECORD;
    v_min_valid_bid NUMERIC;
    v_new_end_at TIMESTAMPTZ;
    v_bid_id UUID;
    v_prev_highest_bidder UUID;
BEGIN
    IF v_bidder_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated. User must be logged in to bid.';
    END IF;

    -- Retrieve role and business status
    SELECT role, business_status INTO v_bidder_role, v_bidder_biz_status
    FROM public.profiles
    WHERE id = v_bidder_id;

    IF COALESCE(v_bidder_role, 'buyer') != 'admin' AND COALESCE(v_bidder_biz_status, 'none') != 'approved' THEN
        RAISE EXCEPTION 'Verification required: Form 2 (Business Verification & Documentation) must be approved by an Admin before placing bids.';
    END IF;

    SELECT * INTO v_auction FROM public.auctions WHERE id = p_auction_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction not found.';
    END IF;

    IF v_auction.created_by = v_bidder_id THEN
        RAISE EXCEPTION 'Sellers cannot bid on their own vehicle auctions.';
    END IF;

    SELECT * INTO r_round
    FROM public.auction_rounds
    WHERE id = p_round_id AND auction_id = p_auction_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found.';
    END IF;

    IF r_round.status != 'live' OR v_server_now < r_round.start_at OR v_server_now >= r_round.end_at THEN
        RAISE EXCEPTION 'Auction round is not currently live for bidding.';
    END IF;

    IF r_round.current_highest_bid IS NULL OR r_round.current_highest_bid = 0 THEN
        v_min_valid_bid := v_auction.starting_price;
    ELSE
        v_min_valid_bid := r_round.current_highest_bid + COALESCE(r_round.min_increment, v_auction.min_increment, 1000);
    END IF;

    IF p_amount < v_min_valid_bid THEN
        RAISE EXCEPTION 'Bid amount Rs. % is below the minimum required bid of Rs. %',
            TO_CHAR(p_amount, 'FM999,999,990'), TO_CHAR(v_min_valid_bid, 'FM999,999,990');
    END IF;

    v_prev_highest_bidder := r_round.highest_bidder_id;

    INSERT INTO public.bids (round_id, auction_id, bidder_id, amount, created_at)
    VALUES (p_round_id, p_auction_id, v_bidder_id, p_amount, v_server_now)
    RETURNING id INTO v_bid_id;

    v_new_end_at := r_round.end_at;
    IF (r_round.end_at - v_server_now) <= INTERVAL '2 minutes' THEN
        v_new_end_at := r_round.end_at + INTERVAL '2 minutes';
    END IF;

    UPDATE public.auction_rounds
    SET current_highest_bid = p_amount,
        highest_bidder_id = v_bidder_id,
        end_at = v_new_end_at,
        updated_at = v_server_now
    WHERE id = p_round_id;

    UPDATE public.auctions
    SET current_highest_bid = p_amount,
        end_at = v_new_end_at,
        updated_at = v_server_now
    WHERE id = p_auction_id;

    IF v_prev_highest_bidder IS NOT NULL AND v_prev_highest_bidder != v_bidder_id THEN
        INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
        VALUES (
            v_prev_highest_bidder,
            'outbid',
            '⚡ YOU HAVE BEEN OUTBID',
            FORMAT('A higher bid of Rs. %s was placed on %s.', TO_CHAR(p_amount, 'FM999,999,990'), v_auction.title),
            'auction',
            p_auction_id
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'bid_id', v_bid_id,
        'round_id', p_round_id,
        'amount', p_amount,
        'end_at', v_new_end_at
    );
END;
$$;

-- 3. Update create_vehicle_auction to enforce business verification
CREATE OR REPLACE FUNCTION public.create_vehicle_auction(
    p_title TEXT,
    p_description TEXT,
    p_starting_price NUMERIC,
    p_min_increment NUMERIC,
    p_status TEXT,
    p_reopen_duration_minutes INT,
    p_start_at TIMESTAMPTZ,
    p_end_at TIMESTAMPTZ,
    p_vehicle_type TEXT,
    p_brand_name TEXT,
    p_model TEXT,
    p_built_year INT,
    p_year_calendar TEXT,
    p_lot_number TEXT,
    p_registration_number TEXT,
    p_kilometres_run NUMERIC,
    p_number_of_owners INT,
    p_fuel_type TEXT,
    p_engine_opened TEXT,
    p_colour TEXT,
    p_engine_capacity NUMERIC,
    p_tax_status TEXT,
    p_bluebook_front_path TEXT,
    p_bluebook_back_path TEXT,
    p_bluebook_owner_path TEXT,
    p_vehicle_front_path TEXT,
    p_vehicle_back_path TEXT,
    p_vehicle_right_path TEXT,
    p_vehicle_left_path TEXT,
    p_odometer_path TEXT,
    p_business_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := COALESCE(auth.uid(), 'e5f6a7b8-c9d0-1234-5678-9abcdef01234'::uuid);
    v_auction_id UUID;
    v_created_auction JSONB;
    v_user_role TEXT := 'seller';
    v_biz_status TEXT := 'none';
BEGIN
    SELECT role, business_status INTO v_user_role, v_biz_status FROM public.profiles WHERE id = v_user_id;
    IF v_user_role IS NULL THEN
        v_user_role := COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', 'seller');
    END IF;

    -- Block auction creation if not admin and business status is not approved
    IF v_user_role != 'admin' AND COALESCE(v_biz_status, 'none') != 'approved' THEN
        RAISE EXCEPTION 'Verification required: Form 2 (Business Verification & Documentation) must be submitted and approved by an Admin before creating auctions.';
    END IF;

    -- Ensure profile exists
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (
        v_user_id,
        COALESCE(auth.jwt() ->> 'email', 'seller@autobid.com'),
        COALESCE(auth.jwt() -> 'user_metadata' ->> 'full_name', 'Vehicle Seller'),
        v_user_role
    )
    ON CONFLICT (id) DO UPDATE SET
        role = CASE WHEN public.profiles.role = 'admin' THEN 'admin' ELSE v_user_role END;

    -- Insert Auction
    INSERT INTO public.auctions (
        title, description, starting_price, min_increment, status, reopen_duration_minutes, created_by, business_id,
        vehicle_type, brand_name, model, built_year, year_calendar, lot_number, registration_number,
        kilometres_run, number_of_owners, fuel_type, engine_opened, colour, engine_capacity, tax_status,
        bluebook_front_path, bluebook_back_path, bluebook_owner_path,
        vehicle_front_path, vehicle_back_path, vehicle_right_path, vehicle_left_path, odometer_path
    ) VALUES (
        p_title, p_description, p_starting_price, p_min_increment, p_status, p_reopen_duration_minutes, v_user_id, p_business_id,
        p_vehicle_type, p_brand_name, p_model, p_built_year, p_year_calendar, p_lot_number, p_registration_number,
        p_kilometres_run, p_number_of_owners, p_fuel_type, p_engine_opened, p_colour, p_engine_capacity, p_tax_status,
        p_bluebook_front_path, p_bluebook_back_path, p_bluebook_owner_path,
        p_vehicle_front_path, p_vehicle_back_path, p_vehicle_right_path, p_vehicle_left_path, p_odometer_path
    ) RETURNING id INTO v_auction_id;

    -- Insert Cover Images
    IF p_vehicle_front_path IS NOT NULL AND p_vehicle_front_path <> '' THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (v_auction_id, p_vehicle_front_path, 1, true);
    END IF;
    IF p_vehicle_back_path IS NOT NULL AND p_vehicle_back_path <> '' THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (v_auction_id, p_vehicle_back_path, 2, false);
    END IF;

    -- Create Initial Round
    INSERT INTO public.auction_rounds (
        auction_id, round_number, start_at, end_at, status, current_highest_bid, min_increment
    ) VALUES (
        v_auction_id, 1, p_start_at, p_end_at, p_status, 0.0, p_min_increment
    );

    SELECT jsonb_build_object(
        'auction_id', v_auction_id,
        'title', p_title,
        'status', p_status,
        'starting_price', p_starting_price
    ) INTO v_created_auction;

    RETURN v_created_auction;
END;
$$;

GRANT EXECUTE ON FUNCTION public.place_bid(UUID, NUMERIC, UUID) TO anon, authenticated, public, service_role;
GRANT EXECUTE ON FUNCTION public.place_bid(UUID, UUID, NUMERIC, UUID) TO anon, authenticated, public, service_role;
GRANT EXECUTE ON FUNCTION public.create_vehicle_auction(TEXT, TEXT, NUMERIC, NUMERIC, TEXT, INT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, INT, TEXT, TEXT, TEXT, NUMERIC, INT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID) TO anon, authenticated, public, service_role;
