-- Migration 031: Expand status check constraints on auctions and auction_rounds tables

-- 1. UPDATE AUCTION_ROUNDS STATUS CHECK CONSTRAINT
ALTER TABLE public.auction_rounds DROP CONSTRAINT IF EXISTS auction_rounds_status_check;
ALTER TABLE public.auction_rounds ADD CONSTRAINT auction_rounds_status_check 
CHECK (status IN ('upcoming', 'live', 'ended', 'winner_pending_deposit', 'secured', 'expired', 'payment_expired', 'manual_review_required'));

-- 2. UPDATE AUCTIONS STATUS CHECK CONSTRAINT
ALTER TABLE public.auctions DROP CONSTRAINT IF EXISTS auctions_status_check;
ALTER TABLE public.auctions ADD CONSTRAINT auctions_status_check 
CHECK (status IN ('draft', 'upcoming', 'live', 'secured', 'cancelled', 'manual_review_required', 're_auction_eligible', 're_auctioned', 'closed'));
