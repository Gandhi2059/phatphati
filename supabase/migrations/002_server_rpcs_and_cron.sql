-- Migration 002: Server-Side RPC Functions, State Machine & Cron Processing

-- DROP EXISTING FUNCTIONS TO PREVENT PARAMETER RENAME CONFLICTS (42P13)
DROP FUNCTION IF EXISTS public.place_bid(UUID, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS public.place_bid(UUID, UUID, NUMERIC) CASCADE;
DROP FUNCTION IF EXISTS public.get_server_time() CASCADE;
DROP FUNCTION IF EXISTS public.process_auction_state_transitions() CASCADE;

-- 1. SERVER TIME RPC SOURCE OF TRUTH
CREATE OR REPLACE FUNCTION public.get_server_time()
RETURNS TIMESTAMPTZ
LANGUAGE sql
STABLE
AS $$
    SELECT transaction_timestamp();
$$;

-- 2. ATOMIC PLACE_BID RPC
CREATE OR REPLACE FUNCTION public.place_bid(
    p_round_id UUID,
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

    -- Lock round record for atomic update
    SELECT * INTO v_round
    FROM public.auction_rounds
    WHERE id = p_round_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found.';
    END IF;

    -- Fetch parent auction for min_increment and title
    SELECT * INTO v_auction
    FROM public.auctions
    WHERE id = v_round.auction_id;

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
    VALUES (p_round_id, v_round.auction_id, v_bidder_id, p_amount, v_server_now)
    RETURNING id INTO v_bid_id;

    -- Update round current highest bid and leader
    UPDATE public.auction_rounds
    SET current_highest_bid = p_amount,
        highest_bidder_id = v_bidder_id,
        updated_at = v_server_now
    WHERE id = p_round_id;

    -- Notification 1: Leading Bid for Current Bidder
    INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
    VALUES (
        v_bidder_id,
        'leading_bid',
        '🏆 You''re leading!',
        FORMAT('Your bid of Rs. %s is currently the highest bid for %s.', TO_CHAR(p_amount, 'FM999,999,990'), v_auction.title),
        'auction',
        v_round.auction_id
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
            v_round.auction_id
        );
    END IF;

    -- Audit Log entry
    INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
    VALUES (
        v_bidder_id,
        'BID_ACCEPTED',
        'auction_round',
        p_round_id,
        jsonb_build_object(
            'amount', p_amount,
            'auction_id', v_round.auction_id,
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

-- 3. MANDATORY STATE TRANSITION PROCESSOR (Cron Engine)
CREATE OR REPLACE FUNCTION public.process_auction_state_transitions()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_server_now TIMESTAMPTZ := transaction_timestamp();
    r_round RECORD;
    r_auction RECORD;
    v_deposit_req NUMERIC;
    v_new_round_id UUID;
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

        -- Audit Log
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
        VALUES (
            NULL,
            'ROUND_STARTED',
            'auction_round',
            r_round.id,
            jsonb_build_object('round_number', r_round.round_number, 'start_at', r_round.start_at)
        );

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
            v_deposit_req := r_round.current_highest_bid * 0.10;

            UPDATE public.auction_rounds
            SET status = 'winner_pending_deposit',
                winning_bid = r_round.current_highest_bid,
                deposit_required = v_deposit_req,
                deposit_deadline = v_server_now + INTERVAL '20 minutes',
                updated_at = v_server_now
            WHERE id = r_round.id;

            -- Winner Notification
            INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
            VALUES (
                r_round.highest_bidder_id,
                'auction_won',
                '🎉 YOU WON THE AUCTION',
                FORMAT('%s. Winning Bid: Rs. %s. Required Deposit: Rs. %s. You must pay the 10%% deposit within 20 minutes.', r_round.auction_title, TO_CHAR(r_round.current_highest_bid, 'FM999,999,990'), TO_CHAR(v_deposit_req, 'FM999,999,990')),
                'auction',
                r_round.auction_id
            );

            -- Initial Deposit Reminder Log
            INSERT INTO public.auction_reminder_logs (round_id, reminder_type, sent_at)
            VALUES (r_round.id, 'initial', v_server_now)
            ON CONFLICT DO NOTHING;

            -- Admin Notification
            INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
            SELECT 
                p.id,
                'admin_alert',
                'Winner Selected',
                FORMAT('Winner selected for %s. Winning Bid: Rs. %s. Deposit Required: Rs. %s. Deadline: %s.', r_round.auction_title, TO_CHAR(r_round.current_highest_bid, 'FM999,999,990'), TO_CHAR(v_deposit_req, 'FM999,999,990'), TO_CHAR(v_server_now + INTERVAL '20 minutes', 'HH12:MI AM')),
                'auction',
                r_round.auction_id
            FROM public.profiles p WHERE p.role = 'admin';

            -- Audit Log
            INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
            VALUES (
                NULL,
                'WINNER_SELECTED',
                'auction_round',
                r_round.id,
                jsonb_build_object(
                    'winner_id', r_round.highest_bidder_id,
                    'winning_bid', r_round.current_highest_bid,
                    'deposit_required', v_deposit_req,
                    'deposit_deadline', v_server_now + INTERVAL '20 minutes'
                )
            );
        ELSE
            -- No bids placed
            UPDATE public.auction_rounds
            SET status = 'ended', updated_at = v_server_now
            WHERE id = r_round.id;
        END IF;

        v_processed_count := v_processed_count + 1;
    END LOOP;

    -- STEP C: DEPOSIT REMINDER NOTIFICATIONS (10m, 5m, 1m)
    FOR r_round IN 
        SELECT r.*, a.title AS auction_title 
        FROM public.auction_rounds r
        JOIN public.auctions a ON a.id = r.auction_id
        WHERE r.status = 'winner_pending_deposit' AND r.deposit_deadline > v_server_now
    LOOP
        -- 10 Minutes Remaining Reminder
        IF r.deposit_deadline - v_server_now <= INTERVAL '10 minutes' AND r.deposit_deadline - v_server_now > INTERVAL '5 minutes' THEN
            IF NOT EXISTS (SELECT 1 FROM public.auction_reminder_logs WHERE round_id = r.id AND reminder_type = '10_minutes_remaining') THEN
                INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                VALUES (
                    r.highest_bidder_id,
                    'deposit_reminder',
                    '⚠️ Deposit Reminder',
                    FORMAT('10 minutes remaining to secure your winning bid of Rs. %s for %s.', TO_CHAR(r.winning_bid, 'FM999,999,990'), r.auction_title),
                    'auction',
                    r.auction_id
                );
                INSERT INTO public.auction_reminder_logs (round_id, reminder_type, sent_at)
                VALUES (r.id, '10_minutes_remaining', v_server_now);
            END IF;
        END IF;

        -- 5 Minutes Remaining Reminder
        IF r.deposit_deadline - v_server_now <= INTERVAL '5 minutes' AND r.deposit_deadline - v_server_now > INTERVAL '1 minute' THEN
            IF NOT EXISTS (SELECT 1 FROM public.auction_reminder_logs WHERE round_id = r.id AND reminder_type = '5_minutes_remaining') THEN
                INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                VALUES (
                    r.highest_bidder_id,
                    'deposit_reminder',
                    '⏰ 5 Minutes Remaining',
                    FORMAT('Only 5 minutes remaining to pay your deposit of Rs. %s for %s.', TO_CHAR(r.deposit_required, 'FM999,999,990'), r.auction_title),
                    'auction',
                    r.auction_id
                );
                INSERT INTO public.auction_reminder_logs (round_id, reminder_type, sent_at)
                VALUES (r.id, '5_minutes_remaining', v_server_now);
            END IF;
        END IF;

        -- 1 Minute Remaining Reminder
        IF r.deposit_deadline - v_server_now <= INTERVAL '1 minute' THEN
            IF NOT EXISTS (SELECT 1 FROM public.auction_reminder_logs WHERE round_id = r.id AND reminder_type = '1_minute_remaining') THEN
                INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
                VALUES (
                    r.highest_bidder_id,
                    'deposit_reminder',
                    '🚨 1 Minute Left!',
                    FORMAT('1 minute left to pay your deposit of Rs. %s for %s.', TO_CHAR(r.deposit_required, 'FM999,999,990'), r.auction_title),
                    'auction',
                    r.auction_id
                );
                INSERT INTO public.auction_reminder_logs (round_id, reminder_type, sent_at)
                VALUES (r.id, '1_minute_remaining', v_server_now);
            END IF;
        END IF;
    END LOOP;

    -- STEP D: DEPOSIT TIMEOUT & AUTO-REOPEN (20-MIN EXPIRATION)
    FOR r_round IN 
        SELECT r.*, a.title AS auction_title, a.reopen_duration_minutes, a.starting_price
        FROM public.auction_rounds r
        JOIN public.auctions a ON a.id = r.auction_id
        WHERE r.status = 'winner_pending_deposit' AND v_server_now >= r.deposit_deadline
    LOOP
        -- Expire current round
        UPDATE public.auction_rounds
        SET status = 'expired', updated_at = v_server_now
        WHERE id = r_round.id;

        -- Notification to defaulting winner
        INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
        VALUES (
            r_round.highest_bidder_id,
            'deposit_expired',
            '⚠️ PAYMENT TIME EXPIRED',
            FORMAT('The required deposit for %s was not received within 20 minutes. Your winning position has expired.', r_round.auction_title),
            'auction',
            r_round.auction_id
        );

        -- Create Round N+1 (Auto Reopen)
        INSERT INTO public.auction_rounds (
            auction_id,
            round_number,
            start_at,
            end_at,
            status,
            current_highest_bid
        ) VALUES (
            r_round.auction_id,
            r_round.round_number + 1,
            v_server_now,
            v_server_now + (r_round.reopen_duration_minutes || ' minutes')::INTERVAL,
            'live',
            0.00
        ) RETURNING id INTO v_new_round_id;

        UPDATE public.auctions
        SET status = 'live', updated_at = v_server_now
        WHERE id = r_round.auction_id;

        -- Notify eligible buyers (all buyers except defaulting winner)
        INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
        SELECT 
            p.id,
            'auction_reopened',
            '🔄 AUCTION REOPENED',
            FORMAT('%s is open for bidding again. New End Time: %s.', r_round.auction_title, TO_CHAR(v_server_now + (r_round.reopen_duration_minutes || ' minutes')::INTERVAL, 'HH12:MI AM')),
            'auction',
            r_round.auction_id
        FROM public.profiles p 
        WHERE p.role = 'buyer' AND p.id != r_round.highest_bidder_id;

        -- Audit Log
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
        VALUES (
            NULL,
            'AUCTION_REOPENED',
            'auction_round',
            v_new_round_id,
            jsonb_build_object(
                'previous_round_id', r_round.id,
                'defaulted_winner_id', r_round.highest_bidder_id,
                'new_round_number', r_round.round_number + 1,
                'new_end_at', v_server_now + (r_round.reopen_duration_minutes || ' minutes')::INTERVAL
            )
        );

        v_processed_count := v_processed_count + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'processed_count', v_processed_count, 'server_time', v_server_now);
END;
$$;
