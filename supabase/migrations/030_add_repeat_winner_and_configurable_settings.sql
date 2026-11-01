-- Migration 030: Repeat Winner Detection, Configurable Payment Settings, and Automated Expiration

-- 1. EXTEND PLATFORM PAYMENT SETTINGS FOR CONFIGURABLE DEPOSIT % AND DEADLINE MINUTES
ALTER TABLE public.platform_payment_settings 
ADD COLUMN IF NOT EXISTS deposit_percentage NUMERIC(5,2) DEFAULT 10.00 CHECK (deposit_percentage > 0 AND deposit_percentage <= 100.00),
ADD COLUMN IF NOT EXISTS payment_deadline_minutes INT DEFAULT 30 CHECK (payment_deadline_minutes >= 5 AND payment_deadline_minutes <= 1440);

-- Ensure row 1 defaults exist
UPDATE public.platform_payment_settings
SET deposit_percentage = COALESCE(deposit_percentage, 10.00),
    payment_deadline_minutes = COALESCE(payment_deadline_minutes, 30)
WHERE id = 1;

-- 2. EXTEND AUCTIONS & AUCTION_ROUNDS FOR RE-AUCTION & MANUAL REVIEW FLAGS
ALTER TABLE public.auctions
ADD COLUMN IF NOT EXISTS parent_auction_id UUID REFERENCES public.auctions(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS requires_manual_review BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS manual_review_reason TEXT;

ALTER TABLE public.auction_rounds
ADD COLUMN IF NOT EXISTS requires_manual_review BOOLEAN DEFAULT FALSE;

-- 3. DYNAMIC CREATE DEPOSIT BOOKING RPC
CREATE OR REPLACE FUNCTION public.create_deposit_booking(p_auction_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_existing RECORD;
    v_round RECORD;
    v_winning_amount NUMERIC(12,2);
    v_deposit_percentage NUMERIC(5,2) := 10.00;
    v_deadline_minutes INT := 30;
    v_deposit_amount NUMERIC(12,2);
    v_remaining_balance NUMERIC(12,2);
    v_booking_ref TEXT;
    v_booking_id UUID;
    v_deadline TIMESTAMPTZ;
BEGIN
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

    -- Fetch dynamic platform payment settings
    SELECT COALESCE(deposit_percentage, 10.00), COALESCE(payment_deadline_minutes, 30)
    INTO v_deposit_percentage, v_deadline_minutes
    FROM public.platform_payment_settings
    WHERE id = 1;

    SELECT * INTO v_round
    FROM public.auction_rounds
    WHERE auction_id = p_auction_id
    ORDER BY round_number DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found.';
    END IF;

    IF v_round.highest_bidder_id IS NULL OR v_round.current_highest_bid IS NULL OR v_round.current_highest_bid <= 0 THEN
        RAISE EXCEPTION 'Auction ended without a valid winning bid.';
    END IF;

    v_deadline := COALESCE(v_round.deposit_deadline, NOW() + (v_deadline_minutes || ' minutes')::INTERVAL);
    v_winning_amount := v_round.current_highest_bid;
    v_deposit_amount := ROUND(v_winning_amount * (v_deposit_percentage / 100.0), 2);
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

-- 4. AUTHORITATIVE STATE TRANSITION ENGINE (WITH REPEAT WINNER & EXPIRATION AUTOMATION)
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
    -- Get active platform payment settings
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

            -- Check if this is a Re-Auction and if the SAME buyer defaulted on the parent auction
            IF v_parent_auc_id IS NOT NULL THEN
                SELECT winner_id INTO v_parent_winner_id
                FROM public.deposit_records
                WHERE auction_id = v_parent_auc_id AND payment_status IN ('expired', 'rejected');

                IF v_parent_winner_id = r_round.highest_bidder_id THEN
                    v_is_repeat_default_winner := TRUE;
                END IF;
            END IF;

            IF v_is_repeat_default_winner THEN
                -- REPEAT WINNER: Require Admin Manual Review, DO NOT auto-generate deposit booking
                UPDATE public.auction_rounds
                SET status = 'manual_review_required',
                    winning_bid = r_round.current_highest_bid,
                    requires_manual_review = TRUE,
                    updated_at = v_server_now
                WHERE id = r_round.id;

                UPDATE public.auctions
                SET status = 'manual_review_required',
                    requires_manual_review = TRUE,
                    manual_review_reason = 'Winning buyer previously defaulted on parent auction deposit.',
                    updated_at = v_server_now
                WHERE id = r_round.auction_id;

                -- Notify Admin for Manual Review
                INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                SELECT 
                    p.id,
                    'admin_alert',
                    '🚨 REPEAT WINNER MANUAL REVIEW REQUIRED',
                    FORMAT('Buyer won re-auction for %s after defaulting on parent auction. Admin manual approval required.', r_round.auction_title),
                    'auction',
                    r_round.auction_id
                FROM public.profiles p WHERE p.role = 'admin';

                -- Notify Winner
                INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                VALUES (
                    r_round.highest_bidder_id,
                    'auction_won_pending_review',
                    '⚠️ WINNING BID UNDER REVIEW',
                    FORMAT('%s: Your winning bid is under manual Admin review due to previous transaction history.', r_round.auction_title),
                    'auction',
                    r_round.auction_id
                );

                INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
                VALUES (
                    NULL, 'REPEAT_WINNER_FLAGGED', 'auction_round', r_round.id,
                    jsonb_build_object('winner_id', r_round.highest_bidder_id, 'winning_bid', r_round.current_highest_bid, 'parent_auction_id', v_parent_auc_id)
                );

            ELSE
                -- Standard Winner Selection
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

                -- Auto-create deposit booking record
                PERFORM public.create_deposit_booking(r_round.auction_id);

                -- Winner Notification
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

            INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
            VALUES (
                r_round.highest_bidder_id,
                'payment_expired',
                '⏰ PAYMENT DEADLINE EXPIRED',
                FORMAT('The deposit payment deadline for %s has expired.', r_round.auction_title),
                'auction',
                r_round.auction_id
            );

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

-- 5. ADMIN REPEAT WINNER MANUAL RESOLUTION RPC
CREATE OR REPLACE FUNCTION public.resolve_repeat_winner_auction(
    p_auction_id UUID,
    p_decision TEXT, -- 'approve', 'reject_winner', 're_auction'
    p_admin_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_is_admin BOOLEAN := FALSE;
    v_auction RECORD;
    v_round RECORD;
    v_deposit_pct NUMERIC(5,2) := 10.00;
    v_deadline_mins INT := 30;
    v_deposit_req NUMERIC(12,2);
    v_re_auction_id UUID;
    v_re_title TEXT;
BEGIN
    SELECT COALESCE(role = 'admin', false) INTO v_is_admin FROM public.profiles WHERE id = v_admin_id;
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Unauthorized: Only platform Admins can perform manual repeat winner decisions.';
    END IF;

    IF p_admin_reason IS NULL OR TRIM(p_admin_reason) = '' THEN
        RAISE EXCEPTION 'Admin decision reason is mandatory.';
    END IF;

    SELECT * INTO v_auction FROM public.auctions WHERE id = p_auction_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction not found.';
    END IF;

    SELECT * INTO v_round FROM public.auction_rounds WHERE auction_id = p_auction_id ORDER BY round_number DESC LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found.';
    END IF;

    SELECT COALESCE(deposit_percentage, 10.00), COALESCE(payment_deadline_minutes, 30)
    INTO v_deposit_pct, v_deadline_mins
    FROM public.platform_payment_settings WHERE id = 1;

    IF p_decision = 'approve' THEN
        v_deposit_req := ROUND(v_round.current_highest_bid * (v_deposit_pct / 100.0), 2);

        UPDATE public.auction_rounds
        SET status = 'winner_pending_deposit',
            deposit_required = v_deposit_req,
            deposit_deadline = NOW() + (v_deadline_mins || ' minutes')::INTERVAL,
            requires_manual_review = FALSE,
            updated_at = NOW()
        WHERE id = v_round.id;

        UPDATE public.auctions
        SET status = 'secured',
            requires_manual_review = FALSE,
            manual_review_reason = FORMAT('Approved by Admin: %s', p_admin_reason),
            updated_at = NOW()
        WHERE id = p_auction_id;

        PERFORM public.create_deposit_booking(p_auction_id);

        INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
        VALUES (
            v_round.highest_bidder_id,
            'auction_won',
            '✅ WINNING BID APPROVED',
            FORMAT('Admin approved your winning bid for %s. Deposit Required: Rs. %s. Please upload payment proof within %s mins.', v_auction.title, TO_CHAR(v_deposit_req, 'FM999,999,990'), v_deadline_mins::text),
            'auction',
            p_auction_id
        );

    ELSIF p_decision = 'reject_winner' THEN
        UPDATE public.auction_rounds
        SET status = 'ended', requires_manual_review = FALSE, updated_at = NOW()
        WHERE id = v_round.id;

        UPDATE public.auctions
        SET status = 're_auction_eligible',
            requires_manual_review = FALSE,
            manual_review_reason = FORMAT('Rejected by Admin: %s', p_admin_reason),
            updated_at = NOW()
        WHERE id = p_auction_id;

        INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
        VALUES (
            v_round.highest_bidder_id,
            'bid_rejected',
            '❌ WINNING BID CANCELLED',
            FORMAT('Your winning bid for %s was cancelled by Admin. Reason: %s', v_auction.title, p_admin_reason),
            'auction',
            p_auction_id
        );

    ELSIF p_decision = 're_auction' THEN
        v_re_title := v_auction.title || ' (Re-Auction)';

        INSERT INTO public.auctions (
            created_by, business_id, title, description, starting_price, min_increment,
            start_at, end_at, status, parent_auction_id
        ) VALUES (
            v_auction.created_by, v_auction.business_id, v_re_title, v_auction.description,
            v_auction.starting_price, v_auction.min_increment,
            NOW() + INTERVAL '5 minutes', NOW() + INTERVAL '1 hour', 'upcoming', p_auction_id
        ) RETURNING id INTO v_re_auction_id;

        INSERT INTO public.auction_rounds (auction_id, round_number, start_at, end_at, status)
        VALUES (v_re_auction_id, 1, NOW() + INTERVAL '5 minutes', NOW() + INTERVAL '1 hour', 'upcoming');

        UPDATE public.auctions SET status = 're_auctioned', updated_at = NOW() WHERE id = p_auction_id;

    ELSE
        RAISE EXCEPTION 'Invalid decision option. Use approve, reject_winner, or re_auction.';
    END IF;

    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
    VALUES (
        v_admin_id,
        'ADMIN_REPEAT_WINNER_DECISION',
        'auction',
        p_auction_id,
        jsonb_build_object(
            'decision', p_decision,
            'reason', p_admin_reason,
            'winner_id', v_round.highest_bidder_id,
            'winning_bid', v_round.current_highest_bid
        )
    );

    RETURN jsonb_build_object('success', true, 'decision', p_decision);
END;
$$;

-- 6. SERVER TIMESTAMP ENFORCEMENT IN PLACE_BID RPC
CREATE OR REPLACE FUNCTION public.place_bid(
    p_auction_id UUID,
    p_round_id UUID,
    p_amount NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_bidder_id UUID := auth.uid();
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
