-- Migration 046: Purge All User Credentials Except Fixed Master Admin
-- Ensures only the fixed master administrator (admin@gmail.com) is preserved in auth.users and public.profiles

DO $$
BEGIN
    -- 1. Remove references in public tables for non-admin users
    DELETE FROM public.deposit_evidence_submissions 
    WHERE winner_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.deposit_review_logs 
    WHERE reviewed_by IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.deposit_records 
    WHERE winner_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com')
       OR reviewed_by IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.deposit_payments 
    WHERE buyer_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.bids 
    WHERE bidder_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.auction_rounds 
    WHERE highest_bidder_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.business_review_logs 
    WHERE reviewed_by IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.business_profiles 
    WHERE owner_user_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com')
       OR reviewed_by IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.notifications 
    WHERE user_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM public.audit_logs 
    WHERE actor_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    -- 2. Delete non-admin profiles from public.profiles
    DELETE FROM public.profiles 
    WHERE LOWER(email) <> 'admin@gmail.com';

    -- 3. Delete non-admin auth identities and sessions
    DELETE FROM auth.identities 
    WHERE user_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    DELETE FROM auth.refresh_tokens 
    WHERE session_id IN (
        SELECT id FROM auth.sessions 
        WHERE user_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com')
    );

    DELETE FROM auth.sessions 
    WHERE user_id IN (SELECT id FROM auth.users WHERE LOWER(email) <> 'admin@gmail.com');

    -- 4. Delete non-admin users from auth.users
    DELETE FROM auth.users 
    WHERE LOWER(email) <> 'admin@gmail.com';

    RAISE NOTICE 'Successfully purged all non-admin credentials. Only admin@gmail.com remains.';
END $$;
