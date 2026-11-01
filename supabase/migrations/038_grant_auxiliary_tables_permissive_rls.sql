-- Migration 038: Grant permissive RLS for auxiliary logs, payment settings, and deposits
ALTER TABLE IF EXISTS public.business_review_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "business_review_logs all policy" ON public.business_review_logs;
CREATE POLICY "business_review_logs all policy" ON public.business_review_logs FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

ALTER TABLE IF EXISTS public.deposit_review_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "deposit_review_logs all policy" ON public.deposit_review_logs;
CREATE POLICY "deposit_review_logs all policy" ON public.deposit_review_logs FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

ALTER TABLE IF EXISTS public.audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "audit_logs all policy" ON public.audit_logs;
CREATE POLICY "audit_logs all policy" ON public.audit_logs FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

ALTER TABLE IF EXISTS public.platform_payment_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "platform_payment_settings all policy" ON public.platform_payment_settings;
CREATE POLICY "platform_payment_settings all policy" ON public.platform_payment_settings FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

ALTER TABLE IF EXISTS public.deposit_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "deposit_payments all policy" ON public.deposit_payments;
CREATE POLICY "deposit_payments all policy" ON public.deposit_payments FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);

ALTER TABLE IF EXISTS public.auction_reminder_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auction_reminder_logs all policy" ON public.auction_reminder_logs;
CREATE POLICY "auction_reminder_logs all policy" ON public.auction_reminder_logs FOR ALL TO anon, authenticated, public USING (true) WITH CHECK (true);
