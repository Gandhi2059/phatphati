-- Migration 028: Purge All Bids and Reset Round Highest Bid States
-- Creates a SECURITY DEFINER RPC function purge_all_bids() to wipe all bid history and reset round bidding counters.

CREATE OR REPLACE FUNCTION purge_all_bids()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count integer;
BEGIN
    -- 1. Truncate / Delete all records from bids table
    DELETE FROM bids;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    -- 2. Reset highest bid and winner tracking on all auction rounds
    UPDATE auction_rounds
    SET current_highest_bid = 0.0,
        highest_bidder_id = NULL,
        winning_bid = NULL;

    RETURN json_build_object(
        'success', true,
        'deleted_bids_count', deleted_count
    );
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION purge_all_bids() TO anon, authenticated, service_role;

-- Execute RPC immediately upon migration run
SELECT purge_all_bids();
