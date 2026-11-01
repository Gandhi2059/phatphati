-- Migration 012: Clean up overloaded place_bid functions to resolve PostgREST function choice ambiguity

DROP FUNCTION IF EXISTS public.place_bid(UUID, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS public.place_bid(UUID, NUMERIC, UUID) CASCADE;

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
    v_round RECORD;
    v_auction RECORD;
    v_min_next_bid NUMERIC;
    v_server_now TIMESTAMPTZ := transaction_timestamp();
    v_bid_id UUID;
    v_created_bid JSONB;
BEGIN
    -- Determine active bidder ID
    v_bidder_id := COALESCE(p_bidder_id, auth.uid(), '11111111-1111-1111-1111-111111111111'::uuid);

    -- Ensure profile exists in profiles table
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (
        v_bidder_id,
        COALESCE(auth.jwt() ->> 'email', 'bidder@auction.com'),
        COALESCE(auth.jwt() -> 'user_metadata' ->> 'full_name', 'Auction Bidder'),
        COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', 'buyer')
    )
    ON CONFLICT (id) DO NOTHING;

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

    -- Fetch parent auction for min_increment and starting price
    SELECT * INTO v_auction
    FROM public.auctions
    WHERE id = p_auction_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target auction record not found.';
    END IF;

    -- Auto-transition upcoming round to live if server_now is within timing window
    IF (v_round.status = 'upcoming' OR v_auction.status = 'upcoming') 
       AND v_server_now >= v_round.start_at 
       AND v_server_now < v_round.end_at THEN
        UPDATE public.auction_rounds SET status = 'live' WHERE id = v_round.id;
        UPDATE public.auctions SET status = 'live' WHERE id = p_auction_id;
        v_round.status := 'live';
    END IF;

    -- Server time & status validation
    IF v_server_now < v_round.start_at THEN
        RAISE EXCEPTION 'This auction has not started yet.';
    END IF;

    IF v_server_now >= v_round.end_at OR v_round.status != 'live' THEN
        RAISE EXCEPTION 'This auction has already ended or is not live.';
    END IF;

    -- Calculate required minimum next bid
    IF v_round.current_highest_bid IS NULL OR v_round.current_highest_bid = 0 THEN
        v_min_next_bid := v_auction.starting_price;
    ELSE
        v_min_next_bid := v_round.current_highest_bid + v_auction.min_increment;
    END IF;

    -- Check if amount is valid
    IF p_amount < v_min_next_bid THEN
        RAISE EXCEPTION 'Bid amount of Rs. % is below the minimum required bid of Rs. %', p_amount, v_min_next_bid;
    END IF;

    -- Insert new bid into bids table (tracks history and edit bid increments)
    INSERT INTO public.bids (round_id, bidder_id, amount, created_at)
    VALUES (v_round.id, v_bidder_id, p_amount, NOW())
    RETURNING id INTO v_bid_id;

    -- Update auction round with new highest bid and leader
    UPDATE public.auction_rounds
    SET current_highest_bid = p_amount,
        highest_bidder_id = v_bidder_id,
        updated_at = NOW()
    WHERE id = v_round.id;

    -- Update parent auction timestamp for realtime sync
    UPDATE public.auctions
    SET updated_at = NOW()
    WHERE id = p_auction_id;

    SELECT jsonb_build_object(
        'success', true,
        'bid_id', v_bid_id,
        'amount', p_amount,
        'bidder_id', v_bidder_id,
        'round_id', v_round.id,
        'message', 'Bid placed successfully!'
    ) INTO v_created_bid;

    RETURN v_created_bid;
END;
$$;
