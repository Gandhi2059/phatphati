-- Migration 034: Refine repeat winner detection in process_auction_state_transitions & p_bidder_id in place_bid

-- 1. UPDATE PLACE_BID RPC WITH OPTIONAL P_BIDDER_ID FALLBACK
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

    SELECT * INTO v_auction FROM public.auctions WHERE id = p_auction_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction not found.';
    END IF;

    -- Block self-bidding
    IF v_auction.created_by = v_bidder_id THEN
        RAISE EXCEPTION 'Sellers cannot bid on their own vehicle auctions.';
    END IF;

    -- Row Locking FOR UPDATE on round to prevent race conditions
    SELECT * INTO r_round
    FROM public.auction_rounds
    WHERE id = p_round_id AND auction_id = p_auction_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found.';
    END IF;

    -- SERVER-SIDE TIMESTAMP ENFORCEMENT
    IF r_round.status != 'live' OR v_server_now < r_round.start_at OR v_server_now >= r_round.end_at THEN
        RAISE EXCEPTION 'Auction round is not currently live for bidding.';
    END IF;

    -- Calculate Minimum Valid Bid
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

    -- Insert new bid
    INSERT INTO public.bids (round_id, auction_id, bidder_id, amount, created_at)
    VALUES (p_round_id, p_auction_id, v_bidder_id, p_amount, v_server_now)
    RETURNING id INTO v_bid_id;

    -- Anti-sniping: Auto extend by 2 mins if bid placed in last 2 mins
    v_new_end_at := r_round.end_at;
    IF (r_round.end_at - v_server_now) <= INTERVAL '2 minutes' THEN
        v_new_end_at := r_round.end_at + INTERVAL '2 minutes';
    END IF;

    -- Update round highest bidder & price
    UPDATE public.auction_rounds
    SET current_highest_bid = p_amount,
        highest_bidder_id = v_bidder_id,
        end_at = v_new_end_at,
        updated_at = v_server_now
    WHERE id = p_round_id;

    UPDATE public.auctions
    SET end_at = v_new_end_at, updated_at = v_server_now
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
        'amount', p_amount,
        'end_at', v_new_end_at
    );
END;
$$;

-- 2. UPDATE PROCESS_AUCTION_STATE_TRANSITIONS WITH DUAL-LOOKUP REPEAT WINNER CHECK
CREATE OR REPLACE FUNCTION public.process_auction_state_transitions()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_server_now TIMESTAMPTZ := transaction_timestamp();
    r_round RECORD;
    v_deposit_pct NUMERIC(5,2) := 10.00;
    v_deadline_mins INT := 30;
    v_deposit_req NUMERIC(12,2);
    v_processed_count INT := 0;
    v_is_repeat_default_winner BOOLEAN := FALSE;
    v_parent_winner_id UUID;
    v_parent_auc_id UUID;
BEGIN
    SELECT COALESCE(deposit_percentage, 10.00), COALESCE(payment_deadline_minutes, 30)
    INTO v_deposit_pct, v_deadline_mins
    FROM public.platform_payment_settings
    WHERE id = 1;

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

    -- STEP B: Transition LIVE -> ENDED / WINNER SELECTION / REPEAT WINNER MANUAL REVIEW
    FOR r_round IN 
        SELECT r.*, a.title AS auction_title, a.parent_auction_id
        FROM public.auction_rounds r
        JOIN public.auctions a ON a.id = r.auction_id
        WHERE r.status = 'live' AND v_server_now >= r.end_at
    LOOP
        IF r_round.highest_bidder_id IS NOT NULL AND r_round.current_highest_bid > 0 THEN
            v_deposit_req := ROUND(r_round.current_highest_bid * (v_deposit_pct / 100.0), 2);
            v_is_repeat_default_winner := FALSE;
            v_parent_auc_id := r_round.parent_auction_id;

            -- Check if this is a Re-Auction and if the SAME buyer defaulted on parent auction
            IF v_parent_auc_id IS NOT NULL THEN
                v_parent_winner_id := NULL;
                
                -- Check 1: Deposit records
                SELECT winner_id INTO v_parent_winner_id
                FROM public.deposit_records
                WHERE auction_id = v_parent_auc_id AND payment_status IN ('expired', 'rejected');

                -- Check 2: Parent round highest_bidder_id if deposit_records has no row
                IF v_parent_winner_id IS NULL THEN
                    SELECT highest_bidder_id INTO v_parent_winner_id
                    FROM public.auction_rounds
                    WHERE auction_id = v_parent_auc_id AND status IN ('expired', 'payment_expired');
                END IF;

                IF v_parent_winner_id = r_round.highest_bidder_id THEN
                    v_is_repeat_default_winner := TRUE;
                END IF;
            END IF;

            IF v_is_repeat_default_winner THEN
                UPDATE public.auction_rounds
                SET status = 'manual_review_required',
                    winning_bid = r_round.current_highest_bid,
                    requires_manual_review = TRUE,
                    updated_at = v_server_now
                WHERE id = r_round.id;

                UPDATE public.auctions
                SET status = 'manual_review_required',
                    requires_manual_review = TRUE,
                    manual_review_reason = 'Winning buyer previously defaulted on deposit payment for parent vehicle auction.',
                    updated_at = v_server_now
                WHERE id = r_round.auction_id;

                INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                SELECT 
                    p.id,
                    'admin_alert',
                    '🚨 REPEAT WINNER MANUAL REVIEW REQUIRED',
                    FORMAT('Buyer won re-auction for %s after defaulting on parent auction. Admin manual approval required.', r_round.auction_title),
                    'auction',
                    r_round.auction_id
                FROM public.profiles p WHERE p.role = 'admin';

                IF r_round.highest_bidder_id IS NOT NULL THEN
                    INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                    VALUES (
                        r_round.highest_bidder_id,
                        'auction_won_pending_review',
                        '⚠️ WINNING BID UNDER REVIEW',
                        FORMAT('%s: Your winning bid is under manual Admin review due to previous transaction history.', r_round.auction_title),
                        'auction',
                        r_round.auction_id
                    );
                END IF;

                INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
                VALUES (
                    NULL, 'REPEAT_WINNER_FLAGGED', 'auction_round', r_round.id,
                    jsonb_build_object('winner_id', r_round.highest_bidder_id, 'winning_bid', r_round.current_highest_bid, 'parent_auction_id', v_parent_auc_id)
                );

            ELSE
                UPDATE public.auction_rounds
                SET status = 'winner_pending_deposit',
                    winning_bid = r_round.current_highest_bid,
                    deposit_required = v_deposit_req,
                    deposit_deadline = v_server_now + (v_deadline_mins || ' minutes')::INTERVAL,
                    updated_at = v_server_now
                WHERE id = r_round.id;

                UPDATE public.auctions
                SET status = 'secured', updated_at = v_server_now
                WHERE id = r_round.auction_id;

                PERFORM public.create_deposit_booking(r_round.auction_id);

                IF r_round.highest_bidder_id IS NOT NULL THEN
                    INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                    VALUES (
                        r_round.highest_bidder_id,
                        'auction_won',
                        '🎉 YOU WON THE AUCTION',
                        FORMAT('%s. Winning Bid: Rs. %s. Required Deposit (%s%%): Rs. %s. Deadline: %s minutes.', 
                               r_round.auction_title, 
                               TO_CHAR(r_round.current_highest_bid, 'FM999,999,990'),
                               v_deposit_pct::text,
                               TO_CHAR(v_deposit_req, 'FM999,999,990'),
                               v_deadline_mins::text),
                        'auction',
                        r_round.auction_id
                    );
                END IF;
            END IF;
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

    -- STEP C: AUTOMATED PAYMENT EXPIRATION CHECK
    FOR r_round IN
        SELECT r.*, a.title AS auction_title
        FROM public.auction_rounds r
        JOIN public.auctions a ON a.id = r.auction_id
        WHERE r.status = 'winner_pending_deposit' 
          AND r.deposit_deadline IS NOT NULL 
          AND v_server_now > r.deposit_deadline
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.deposit_records d
            WHERE d.auction_id = r_round.auction_id AND d.payment_status IN ('verified', 'under_review')
        ) THEN
            UPDATE public.auction_rounds
            SET status = 'payment_expired', updated_at = v_server_now
            WHERE id = r_round.id;

            UPDATE public.auctions
            SET status = 're_auction_eligible', updated_at = v_server_now
            WHERE id = r_round.auction_id;

            UPDATE public.deposit_records
            SET payment_status = 'expired', updated_at = v_server_now
            WHERE auction_id = r_round.auction_id;

            IF r_round.highest_bidder_id IS NOT NULL THEN
                INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                VALUES (
                    r_round.highest_bidder_id,
                    'payment_expired',
                    '⏰ PAYMENT DEADLINE EXPIRED',
                    FORMAT('The deposit payment deadline for %s has expired.', r_round.auction_title),
                    'auction',
                    r_round.auction_id
                );
            END IF;

            INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
            VALUES (
                NULL, 'PAYMENT_EXPIRED', 'auction_round', r_round.id,
                jsonb_build_object('winner_id', r_round.highest_bidder_id, 'deadline', r_round.deposit_deadline)
            );

            v_processed_count := v_processed_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'processed_count', v_processed_count);
END;
$$;
