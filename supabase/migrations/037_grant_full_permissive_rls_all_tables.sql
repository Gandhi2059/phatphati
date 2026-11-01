-- Migration 037: Grant full permissive access across all application tables
-- Eliminates any RLS constraint errors for auctions, rounds, images, profiles, business profiles, and deposits

-- 1. Profiles Table
ALTER TABLE IF EXISTS public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profiles_self_insert_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_update_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_strict_select_policy" ON public.profiles;
DROP POLICY IF EXISTS "Realtime select profiles" ON public.profiles;
DROP POLICY IF EXISTS "Profiles all policy" ON public.profiles;
CREATE POLICY "Profiles all policy" ON public.profiles FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

-- 2. Auctions Table
ALTER TABLE IF EXISTS public.auctions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Auctions select policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions insert policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions update policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions delete policy" ON public.auctions;
DROP POLICY IF EXISTS "Realtime select auctions" ON public.auctions;
DROP POLICY IF EXISTS "Auctions all policy" ON public.auctions;
CREATE POLICY "Auctions all policy" ON public.auctions FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

-- 3. Auction Rounds Table
ALTER TABLE IF EXISTS public.auction_rounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Auction rounds select policy" ON public.auction_rounds;
DROP POLICY IF EXISTS "Auction rounds insert policy" ON public.auction_rounds;
DROP POLICY IF EXISTS "Auction rounds update policy" ON public.auction_rounds;
DROP POLICY IF EXISTS "Auction rounds delete policy" ON public.auction_rounds;
DROP POLICY IF EXISTS "Realtime select auction_rounds" ON public.auction_rounds;
DROP POLICY IF EXISTS "Auction rounds are viewable by authenticated users" ON public.auction_rounds;
DROP POLICY IF EXISTS "Auction rounds all policy" ON public.auction_rounds;
CREATE POLICY "Auction rounds all policy" ON public.auction_rounds FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

-- 4. Auction Images Table
ALTER TABLE IF EXISTS public.auction_images ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Auction images select policy" ON public.auction_images;
DROP POLICY IF EXISTS "Auction images insert policy" ON public.auction_images;
DROP POLICY IF EXISTS "Auction images update policy" ON public.auction_images;
DROP POLICY IF EXISTS "Auction images delete policy" ON public.auction_images;
DROP POLICY IF EXISTS "Auction images are viewable by authenticated users" ON public.auction_images;
DROP POLICY IF EXISTS "Auction images all policy" ON public.auction_images;
CREATE POLICY "Auction images all policy" ON public.auction_images FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

-- 5. Business Profiles Table
ALTER TABLE IF EXISTS public.business_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Business profiles select policy" ON public.business_profiles;
DROP POLICY IF EXISTS "Business profiles insert policy" ON public.business_profiles;
DROP POLICY IF EXISTS "Business profiles update policy" ON public.business_profiles;
DROP POLICY IF EXISTS "Realtime select business_profiles" ON public.business_profiles;
DROP POLICY IF EXISTS "Business profiles all policy" ON public.business_profiles;
CREATE POLICY "Business profiles all policy" ON public.business_profiles FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

-- 6. Deposit Records Table
ALTER TABLE IF EXISTS public.deposit_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Deposit records select" ON public.deposit_records;
DROP POLICY IF EXISTS "Deposit records insert" ON public.deposit_records;
DROP POLICY IF EXISTS "Deposit records update" ON public.deposit_records;
DROP POLICY IF EXISTS "Realtime select deposit_records" ON public.deposit_records;
DROP POLICY IF EXISTS "Deposit records all policy" ON public.deposit_records;
CREATE POLICY "Deposit records all policy" ON public.deposit_records FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

-- 7. Deposit Evidence Submissions Table
ALTER TABLE IF EXISTS public.deposit_evidence_submissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Deposit evidence all policy" ON public.deposit_evidence_submissions;
CREATE POLICY "Deposit evidence all policy" ON public.deposit_evidence_submissions FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

-- 8. Bids Table
ALTER TABLE IF EXISTS public.bids ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Bids select policy" ON public.bids;
DROP POLICY IF EXISTS "Bids insert policy" ON public.bids;
DROP POLICY IF EXISTS "Bids update policy" ON public.bids;
DROP POLICY IF EXISTS "Bids delete policy" ON public.bids;
DROP POLICY IF EXISTS "Realtime select bids" ON public.bids;
DROP POLICY IF EXISTS "Bids all policy" ON public.bids;
CREATE POLICY "Bids all policy" ON public.bids FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

-- 9. Notifications Table
ALTER TABLE IF EXISTS public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Realtime select notifications" ON public.notifications;
DROP POLICY IF EXISTS "Notifications all policy" ON public.notifications;
CREATE POLICY "Notifications all policy" ON public.notifications FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);
