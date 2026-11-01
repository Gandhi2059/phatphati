-- Migration 019: Add deposit record helper function for secure test verification and ensure 018 state transitions function
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
