-- Migration 029: Add delete_auction SECURITY DEFINER RPC and DELETE policies on auctions, rounds, images, bids

-- 1. Create SECURITY DEFINER delete_auction RPC
CREATE OR REPLACE FUNCTION public.delete_auction(p_auction_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_bids_deleted INT := 0;
    v_rounds_deleted INT := 0;
    v_images_deleted INT := 0;
    v_auctions_deleted INT := 0;
BEGIN
    -- Delete bids
    DELETE FROM public.bids WHERE auction_id = p_auction_id;
    GET DIAGNOSTICS v_bids_deleted = ROW_COUNT;

    -- Delete rounds
    DELETE FROM public.auction_rounds WHERE auction_id = p_auction_id;
    GET DIAGNOSTICS v_rounds_deleted = ROW_COUNT;

    -- Delete images
    DELETE FROM public.auction_images WHERE auction_id = p_auction_id;
    GET DIAGNOSTICS v_images_deleted = ROW_COUNT;

    -- Delete deposit payments if any
    DELETE FROM public.deposit_payments WHERE auction_id = p_auction_id;

    -- Delete main auction
    DELETE FROM public.auctions WHERE id = p_auction_id;
    GET DIAGNOSTICS v_auctions_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'auction_id', p_auction_id,
        'auctions_deleted', v_auctions_deleted,
        'bids_deleted', v_bids_deleted,
        'rounds_deleted', v_rounds_deleted,
        'images_deleted', v_images_deleted
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_auction(UUID) TO anon, authenticated, public;

-- 2. Add RLS DELETE policies for public table access
ALTER TABLE public.auctions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Auctions delete policy" ON public.auctions;
CREATE POLICY "Auctions delete policy" ON public.auctions FOR DELETE TO anon, authenticated, public USING (true);

ALTER TABLE public.auction_rounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Auction rounds delete policy" ON public.auction_rounds;
CREATE POLICY "Auction rounds delete policy" ON public.auction_rounds FOR DELETE TO anon, authenticated, public USING (true);

ALTER TABLE public.auction_images ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Auction images delete policy" ON public.auction_images;
CREATE POLICY "Auction images delete policy" ON public.auction_images FOR DELETE TO anon, authenticated, public USING (true);

ALTER TABLE public.bids ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Bids delete policy" ON public.bids;
CREATE POLICY "Bids delete policy" ON public.bids FOR DELETE TO anon, authenticated, public USING (true);
