-- Migration 017: Fix syntax bug in process_auction_state_transitions RPC

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
            v_deposit_req := ROUND(r_round.current_highest_bid * 0.10, 2);

            UPDATE public.auction_rounds
            SET status = 'winner_pending_deposit',
                winning_bid = r_round.current_highest_bid,
                deposit_required = v_deposit_req,
                deposit_deadline = v_server_now + INTERVAL '30 minutes',
                updated_at = v_server_now
            WHERE id = r_round.id;

            -- Winner Notification
            INSERT INTO public.notifications (user_id, type, title, message, entity_type, entity_id)
            VALUES (
                r_round.highest_bidder_id,
                'auction_won',
                '🎉 YOU WON THE AUCTION',
                FORMAT('%s. Winning Bid: Rs. %s. Required Deposit: Rs. %s. You must pay the 10%% deposit within 30 minutes.', r_round.auction_title, TO_CHAR(r_round.current_highest_bid, 'FM999,999,990'), TO_CHAR(v_deposit_req, 'FM999,999,990')),
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
                FORMAT('Winner selected for %s. Winning Bid: Rs. %s. Deposit Required: Rs. %s. Deadline: %s.', r_round.auction_title, TO_CHAR(r_round.current_highest_bid, 'FM999,999,990'), TO_CHAR(v_deposit_req, 'FM999,999,990'), TO_CHAR(v_server_now + INTERVAL '30 minutes', 'HH12:MI AM')),
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
                    'deposit_deadline', v_server_now + INTERVAL '30 minutes'
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

    RETURN jsonb_build_object('success', true, 'processed_count', v_processed_count);
END;
$$;
