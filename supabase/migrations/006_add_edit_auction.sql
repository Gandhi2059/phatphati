-- Migration 006: Add Atomic Admin Update Auction RPC

CREATE OR REPLACE FUNCTION public.update_auction_by_admin(
    p_auction_id UUID,
    p_title TEXT,
    p_description TEXT,
    p_starting_price NUMERIC,
    p_min_increment NUMERIC,
    p_status TEXT,
    p_reopen_duration_minutes INT,
    p_start_at TIMESTAMPTZ,
    p_end_at TIMESTAMPTZ,
    p_image_urls TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_latest_round_id UUID;
    v_img_url TEXT;
    v_order INT := 1;
BEGIN
    IF v_user_id IS NULL THEN
        v_user_id := '11111111-1111-1111-1111-111111111111'::uuid;
    END IF;

    -- 1. Update Auction
    UPDATE public.auctions
    SET 
        title = p_title,
        description = p_description,
        starting_price = p_starting_price,
        min_increment = p_min_increment,
        status = p_status,
        reopen_duration_minutes = p_reopen_duration_minutes,
        updated_at = NOW()
    WHERE id = p_auction_id;

    -- 2. Update Latest Auction Round timing
    SELECT id INTO v_latest_round_id
    FROM public.auction_rounds
    WHERE auction_id = p_auction_id
    ORDER BY round_number DESC
    LIMIT 1;

    IF v_latest_round_id IS NOT NULL THEN
        UPDATE public.auction_rounds
        SET 
            start_at = p_start_at,
            end_at = p_end_at,
            status = p_status
        WHERE id = v_latest_round_id;
    END IF;

    -- 3. Update Images if provided
    IF p_image_urls IS NOT NULL AND array_length(p_image_urls, 1) > 0 THEN
        DELETE FROM public.auction_images WHERE auction_id = p_auction_id;
        FOREACH v_img_url IN ARRAY p_image_urls LOOP
            IF v_img_url IS NOT NULL AND length(trim(v_img_url)) > 0 THEN
                INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
                VALUES (p_auction_id, trim(v_img_url), v_order, (v_order = 1));
                v_order := v_order + 1;
            END IF;
        END LOOP;
    END IF;

    -- 4. Audit Log Entry
    BEGIN
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
        VALUES (
            v_user_id, 'UPDATE_AUCTION', 'auction', p_auction_id,
            jsonb_build_object('title', p_title, 'starting_price', p_starting_price, 'status', p_status)
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success', true, 'auction_id', p_auction_id);
END;
$$;
