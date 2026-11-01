-- Migration 018: Unify Deposit Deadlines (30 minutes) and Enforce Database/API-Level Bidder Privacy

-- 1. UNIFY DEPOSIT BOOKING FUNCTION WITH 30-MINUTE DEADLINE & MATCHING ROUND DEADLINE
CREATE OR REPLACE FUNCTION public.create_deposit_booking(p_auction_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_existing RECORD;
    v_round RECORD;
    v_auction RECORD;
    v_winning_amount NUMERIC(12,2);
    v_deposit_amount NUMERIC(12,2);
    v_remaining_balance NUMERIC(12,2);
    v_booking_ref TEXT;
    v_booking_id UUID;
    v_deadline TIMESTAMPTZ;
BEGIN
    -- Check if booking record already exists (Idempotent: return existing record without modifying deadline)
    SELECT * INTO v_existing FROM public.deposit_records WHERE auction_id = p_auction_id;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'booking_id', v_existing.id,
            'booking_reference', v_existing.booking_reference,
            'winning_amount', v_existing.winning_amount,
            'deposit_amount', v_existing.deposit_amount,
            'remaining_balance', v_existing.remaining_balance,
            'payment_due_at', v_existing.payment_due_at,
            'payment_status', v_existing.payment_status,
            'reservation_status', v_existing.vehicle_reservation_status
        );
    END IF;

    -- Fetch latest round for auction
    SELECT * INTO v_round
    FROM public.auction_rounds
    WHERE auction_id = p_auction_id
    ORDER BY round_number DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found.';
    END IF;

    -- Require valid winner and highest bid
    IF v_round.highest_bidder_id IS NULL OR v_round.current_highest_bid IS NULL OR v_round.current_highest_bid <= 0 THEN
        RAISE EXCEPTION 'Auction ended without a valid winning bid.';
    END IF;

    -- Authoritative 30-minute deadline from round or NOW() + 30 mins
    v_deadline := COALESCE(v_round.deposit_deadline, NOW() + INTERVAL '30 minutes');
    v_winning_amount := v_round.current_highest_bid;
    v_deposit_amount := ROUND(v_winning_amount * 0.10, 2);
    v_remaining_balance := v_winning_amount - v_deposit_amount;
    v_booking_ref := 'BOOK-' || UPPER(SUBSTRING(MD5(p_auction_id::text || NOW()::text) FROM 1 FOR 8));

    INSERT INTO public.deposit_records (
        auction_id,
        winner_id,
        booking_reference,
        winning_amount,
        deposit_amount,
        remaining_balance,
        payment_due_at,
        payment_status,
        vehicle_reservation_status
    ) VALUES (
        p_auction_id,
        v_round.highest_bidder_id,
        v_booking_ref,
        v_winning_amount,
        v_deposit_amount,
        v_remaining_balance,
        v_deadline,
        'awaiting_payment',
        'awaiting_deposit'
    ) RETURNING id INTO v_booking_id;

    RETURN jsonb_build_object(
        'success', true,
        'booking_id', v_booking_id,
        'booking_reference', v_booking_ref,
        'winning_amount', v_winning_amount,
        'deposit_amount', v_deposit_amount,
        'remaining_balance', v_remaining_balance,
        'payment_due_at', v_deadline,
        'payment_status', 'awaiting_payment',
        'reservation_status', 'awaiting_deposit'
    );
END;
$$;

-- 2. UPDATE STATE TRANSITION ENGINE TO AUTOMATICALLY GENERATE BOOKING & NOTIFICATIONS
CREATE OR REPLACE FUNCTION public.process_auction_state_transitions()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_server_now TIMESTAMPTZ := transaction_timestamp();
    r_round RECORD;
    v_deposit_req NUMERIC;
    v_processed_count INT := 0;
BEGIN
    -- STEP A: Transition UPCOMING -> LIVE
    FOR r_round IN 
        SELECT r.*, a.title AS auction_title 
        FROM public.auction_rounds r
        JOIN public.auctions a ON a.id = r.auction_id
        WHERE r.status = 'upcoming' AND v_server_now >= r.start_at AND v_server_now < r.end_at
    LOOP
        UPDATE public.auction_rounds
        SET status = 'live', updated_at = v_server_now
        WHERE id = r_round.id;

        UPDATE public.auctions
        SET status = 'live', updated_at = v_server_now
        WHERE id = r_round.auction_id;

        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
        VALUES (NULL, 'ROUND_STARTED', 'auction_round', r_round.id, jsonb_build_object('round_number', r_round.round_number));

        v_processed_count := v_processed_count + 1;
    END LOOP;

    -- STEP B: Transition LIVE -> ENDED / WINNER SELECTION
    FOR r_round IN 
        SELECT r.*, a.title AS auction_title 
        FROM public.auction_rounds r
        JOIN public.auctions a ON a.id = r.auction_id
        WHERE r.status = 'live' AND v_server_now >= r.end_at
    LOOP
        IF r_round.highest_bidder_id IS NOT NULL AND r_round.current_highest_bid > 0 THEN
            v_deposit_req := ROUND(r_round.current_highest_bid * 0.10, 2);

            UPDATE public.auction_rounds
            SET status = 'winner_pending_deposit',
                winning_bid = r_round.current_highest_bid,
                deposit_required = v_deposit_req,
                deposit_deadline = v_server_now + INTERVAL '30 minutes',
                updated_at = v_server_now
            WHERE id = r_round.id;

            UPDATE public.auctions
            SET status = 'secured', updated_at = v_server_now
            WHERE id = r_round.auction_id;

            -- Auto-create deposit booking record
            PERFORM public.create_deposit_booking(r_round.auction_id);

            -- Winner Notification
            INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
            VALUES (
                r_round.highest_bidder_id,
                'auction_won',
                '🎉 YOU WON THE AUCTION',
                FORMAT('%s. Winning Bid: Rs. %s. Required Deposit: Rs. %s. Deadline: 30 minutes.', r_round.auction_title, TO_CHAR(r_round.current_highest_bid, 'FM999,999,990'), TO_CHAR(v_deposit_req, 'FM999,999,990')),
                'auction',
                r_round.auction_id
            );
        ELSE
            UPDATE public.auction_rounds
            SET status = 'ended', updated_at = v_server_now
            WHERE id = r_round.id;

            UPDATE public.auctions
            SET status = 'cancelled', updated_at = v_server_now
            WHERE id = r_round.auction_id;
        END IF;

        v_processed_count := v_processed_count + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'processed_count', v_processed_count);
END;
$$;

-- 3. API & DATABASE-LEVEL BIDDER PRIVACY FUNCTION
CREATE OR REPLACE FUNCTION public.get_round_bids(p_round_id UUID)
RETURNS TABLE (
    id UUID,
    round_id UUID,
    auction_id UUID,
    bidder_id UUID,
    amount NUMERIC,
    created_at TIMESTAMPTZ,
    bidder_name TEXT,
    buyer_id TEXT,
    account_category TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_is_admin BOOLEAN := FALSE;
BEGIN
    IF v_caller_id IS NOT NULL THEN
        SELECT COALESCE(role = 'admin', false) INTO v_is_admin FROM public.profiles WHERE id = v_caller_id;
    END IF;

    RETURN QUERY
    SELECT 
        b.id,
        b.round_id,
        b.auction_id,
        b.bidder_id,
        b.amount,
        b.created_at,
        CASE 
            WHEN v_is_admin THEN COALESCE(p.full_name, 'Buyer')
            WHEN b.bidder_id = v_caller_id THEN COALESCE(p.full_name, 'YOU')
            ELSE 'Verified Bidder'
        END AS bidder_name,
        CASE 
            WHEN v_is_admin THEN p.buyer_id
            WHEN b.bidder_id = v_caller_id THEN p.buyer_id
            ELSE NULL
        END AS buyer_id,
        CASE 
            WHEN v_is_admin OR b.bidder_id = v_caller_id THEN COALESCE(p.account_category, 'individual')
            ELSE 'individual'
        END AS account_category
    FROM public.bids b
    LEFT JOIN public.profiles p ON p.id = b.bidder_id
    WHERE b.round_id = p_round_id
    ORDER BY b.amount DESC, b.created_at ASC;
END;
$$;

-- 4. DEPOSIT RECORD QUERY HELPER FOR SECURE TEST VERIFICATION
CREATE OR REPLACE FUNCTION public.get_deposit_record_by_auction(p_auction_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_record RECORD;
BEGIN
    SELECT * INTO v_record FROM public.deposit_records WHERE auction_id = p_auction_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Deposit record not found');
    END IF;
    RETURN jsonb_build_object(
        'success', true,
        'id', v_record.id,
        'auction_id', v_record.auction_id,
        'winner_id', v_record.winner_id,
        'booking_reference', v_record.booking_reference,
        'winning_amount', v_record.winning_amount,
        'deposit_amount', v_record.deposit_amount,
        'remaining_balance', v_record.remaining_balance,
        'payment_due_at', v_record.payment_due_at,
        'payment_status', v_record.payment_status,
        'vehicle_reservation_status', v_record.vehicle_reservation_status,
        'created_at', v_record.created_at
    );
END;
$$;

