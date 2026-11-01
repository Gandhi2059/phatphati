-- Migration 035: Make All Database Tables Realtime with Full Replica Identity

-- 1. Set REPLICA IDENTITY FULL for all public tables to enable complete CDC payload streams
ALTER TABLE IF EXISTS public.profiles REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.business_profiles REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.vehicles REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.auctions REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.auction_rounds REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.auction_images REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.bids REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.deposit_records REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.deposit_evidence_submissions REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.system_audit_logs REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.audit_logs REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.notifications REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.platform_payment_settings REPLICA IDENTITY FULL;

-- 2. Ensure supabase_realtime publication exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

-- 3. Add all public tables to supabase_realtime publication safely
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.business_profiles; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.vehicles; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.auctions; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.auction_rounds; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.auction_images; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.bids; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.deposit_records; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.deposit_evidence_submissions; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.system_audit_logs; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.audit_logs; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.platform_payment_settings; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- 4. Enable Permissive Realtime RLS Policies for Realtime Subscriptions
DROP POLICY IF EXISTS "Realtime select profiles" ON public.profiles;
CREATE POLICY "Realtime select profiles" ON public.profiles FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "Realtime select business_profiles" ON public.business_profiles;
CREATE POLICY "Realtime select business_profiles" ON public.business_profiles FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "Realtime select auctions" ON public.auctions;
CREATE POLICY "Realtime select auctions" ON public.auctions FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "Realtime select auction_rounds" ON public.auction_rounds;
CREATE POLICY "Realtime select auction_rounds" ON public.auction_rounds FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "Realtime select bids" ON public.bids;
CREATE POLICY "Realtime select bids" ON public.bids FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "Realtime select deposit_records" ON public.deposit_records;
CREATE POLICY "Realtime select deposit_records" ON public.deposit_records FOR SELECT TO public USING (true);

DROP POLICY IF EXISTS "Realtime select notifications" ON public.notifications;
CREATE POLICY "Realtime select notifications" ON public.notifications FOR SELECT TO public USING (true);
