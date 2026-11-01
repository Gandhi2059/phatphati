-- Migration 047: Admin Delete User RPC and Automatic Registration Notification Trigger
-- Allows administrators to permanently delete unlegit users (auth.users + public.profiles)
-- Automatically creates admin notifications whenever a new Buyer or Seller completes Form 1

-- 0. Update notifications check constraint to include form1_registration and user_registration
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check 
  CHECK (type = ANY (ARRAY[
    'auction_started'::text, 'leading_bid'::text, 'outbid'::text, 
    'auction_ending'::text, 'auction_won'::text, 'deposit_required'::text, 
    'deposit_reminder'::text, 'deposit_paid'::text, 'deposit_expired'::text, 
    'auction_reopened'::text, 'admin_alert'::text, 'form1_registration'::text, 'user_registration'::text
  ]));

-- 1. Create admin_delete_user RPC
CREATE OR REPLACE FUNCTION public.admin_delete_user(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_user_email TEXT;
BEGIN
    -- Protect fixed admin
    SELECT email INTO v_user_email FROM auth.users WHERE id = p_user_id;
    IF LOWER(COALESCE(v_user_email, '')) = 'admin@gmail.com' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Fixed administrator account cannot be deleted.');
    END IF;

    -- 1. Remove references from public tables
    DELETE FROM public.deposit_evidence_submissions WHERE winner_id = p_user_id;
    DELETE FROM public.deposit_review_logs WHERE reviewed_by = p_user_id;
    DELETE FROM public.deposit_records WHERE winner_id = p_user_id OR reviewed_by = p_user_id;
    DELETE FROM public.deposit_payments WHERE buyer_id = p_user_id;
    DELETE FROM public.bids WHERE bidder_id = p_user_id;
    DELETE FROM public.auction_rounds WHERE highest_bidder_id = p_user_id;
    DELETE FROM public.business_review_logs WHERE reviewed_by = p_user_id;
    DELETE FROM public.business_profiles WHERE owner_user_id = p_user_id OR reviewed_by = p_user_id;
    DELETE FROM public.notifications WHERE user_id = p_user_id;
    DELETE FROM public.audit_logs WHERE actor_id = p_user_id;
    DELETE FROM public.profiles WHERE id = p_user_id;

    -- 2. Remove auth records
    DELETE FROM auth.identities WHERE user_id = p_user_id;
    DELETE FROM auth.refresh_tokens WHERE session_id IN (SELECT id FROM auth.sessions WHERE user_id = p_user_id);
    DELETE FROM auth.sessions WHERE user_id = p_user_id;
    DELETE FROM auth.users WHERE id = p_user_id;

    -- 3. Also clean any notifications directed to admin referencing this user
    DELETE FROM public.notifications WHERE entity_id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'deleted_user_id', p_user_id,
        'email', v_user_email,
        'message', 'User and credentials permanently deleted.'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_user(UUID) TO anon, authenticated, service_role, public;

-- 2. Trigger function to automatically notify admin when a new user registers (Form 1)
CREATE OR REPLACE FUNCTION public.notify_admin_on_new_profile()
RETURNS TRIGGER AS $$
DECLARE
    v_admin_id UUID;
    v_role_title TEXT;
BEGIN
    IF NEW.role IN ('buyer', 'seller') THEN
        v_role_title := CASE WHEN NEW.role = 'buyer' THEN 'Buyer (Reconditioner)' ELSE 'Seller (Dealer)' END;
        
        -- Insert notification for all admin users
        FOR v_admin_id IN SELECT id FROM public.profiles WHERE role = 'admin' LOOP
            INSERT INTO public.notifications (
                id, user_id, type, title, message, entity_type, entity_id, is_read, created_at
            ) VALUES (
                gen_random_uuid(),
                v_admin_id,
                'form1_registration',
                'New ' || CASE WHEN NEW.role = 'buyer' THEN 'Buyer' ELSE 'Seller' END || ' Registration (Form 1)',
                NEW.full_name || ' registered as ' || v_role_title || ' (' || NEW.email || ', ' || COALESCE(NEW.phone, 'No phone') || '). Completed Form 1, pending second filling.',
                'user_profile',
                NEW.id,
                false,
                NOW()
            );
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_admin_on_new_profile ON public.profiles;
CREATE TRIGGER trg_notify_admin_on_new_profile
    AFTER INSERT ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_admin_on_new_profile();
