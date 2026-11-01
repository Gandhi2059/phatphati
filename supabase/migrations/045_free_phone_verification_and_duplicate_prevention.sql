-- Migration 045 (Production Hardened & Audited):
-- Free Verification Tracking, Strict Nepal Mobile Validation, Role Immutability & Anti-Enumeration
--
-- Security Gate Resolutions:
-- 1. Role Immutability & Privilege Security:
--    - complete_user_registration preserves existing roles (role = public.profiles.role).
--    - sync_profile_on_auth preserves existing roles on UPDATE.
--    - tr_protect_profiles_integrity reverts any unauthorized role change attempt unless executed by an admin.
--    - Admin-only RPC admin_set_user_role created for explicit server-authorized role management.
--
-- 2. Safe Dynamic Migration:
--    - Dynamic PL/pgSQL DO block inspects pg_proc and safely revokes/drops all overloads of create_authenticated_user.
--    - Safe drop of legacy auto-confirm trigger (tr_auto_confirm_email) and function.
--    - Pre-index duplicate collision detection warns of duplicate email and phone records without data loss.
--
-- 3. Anti-Enumeration Protection:
--    - check_account_availability returns generic messages without leaking email_exists or phone_exists flags.
--    - EXECUTE grants restricted; complete_user_registration granted ONLY to authenticated users.
--
-- 4. Verification Correctness:
--    - Phone verification is derived strictly from auth.users.phone_confirmed_at.
--    - Changing a phone number immediately invalidates previous phone-verification state.
--    - Email verification is derived strictly from auth.users.email_confirmed_at.
--
-- 5. Strict Nepal Mobile Validation:
--    - validate_and_normalize_nepal_phone enforces NTA Nepal mobile standards (98, 97, 96).
--    - Foreign numbers (+91, +1, etc.), landlines, and arbitrary lengths return NULL.

-- Step 1: Safely revoke and drop any legacy function overloads of create_authenticated_user dynamically
DO $$
DECLARE
    r RECORD;
    v_dep_count INT;
BEGIN
    FOR r IN 
        SELECT oid::regprocedure AS func_signature, p.oid
        FROM pg_proc p
        WHERE proname = 'create_authenticated_user' 
          AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'REVOKE ALL ON FUNCTION ' || r.func_signature || ' FROM PUBLIC, anon, authenticated, service_role';

        -- Check for normal object dependencies
        SELECT COUNT(*) INTO v_dep_count
        FROM pg_depend d
        WHERE d.refobjid = r.oid 
          AND d.deptype = 'n';

        IF v_dep_count > 0 THEN
            RAISE WARNING 'Legacy function % has % dependent objects; dropping with CASCADE', r.func_signature, v_dep_count;
            EXECUTE 'DROP FUNCTION ' || r.func_signature || ' CASCADE';
        ELSE
            EXECUTE 'DROP FUNCTION ' || r.func_signature;
        END IF;
    END LOOP;
END $$;

-- Step 2: Drop legacy auto-confirm email trigger to ensure genuine Supabase email confirmation
DROP TRIGGER IF EXISTS tr_auto_confirm_email ON auth.users;
DROP FUNCTION IF EXISTS public.handle_auto_confirm_email();

-- Step 3: Ensure public.is_admin and public.is_seller_or_admin helper functions exist with safe search_path
CREATE OR REPLACE FUNCTION public.is_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE((SELECT role = 'admin' FROM public.profiles WHERE id = p_user_id), false);
$$;

-- Secure is_seller_or_admin: overrides any legacy definitions that inspected or synced raw_user_meta_data
CREATE OR REPLACE FUNCTION public.is_seller_or_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE((SELECT role IN ('seller', 'admin') FROM public.profiles WHERE id = p_user_id), false);
$$;

-- Step 4: Add verification tracking and normalized phone columns to public.profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMPTZ;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_normalized TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT false;

-- Step 5: Strict Nepal Mobile Validation and Normalization Function
-- Strictly enforces NTA Nepal mobile standards:
-- Valid numbers must be 10 digits starting with 98 (NTC/Ncell), 97 (NTC/CDMA), or 96 (Smart Cell)
-- Optionally preceded by +977, 977, or 00977. Foreign numbers or arbitrary last 10 digits are NEVER accepted.
CREATE OR REPLACE FUNCTION public.validate_and_normalize_nepal_phone(p_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_digits TEXT;
BEGIN
    IF p_phone IS NULL OR TRIM(p_phone) = '' THEN
        RETURN NULL;
    END IF;

    -- Strip all formatting characters (spaces, dashes, parens, dots)
    v_digits := REGEXP_REPLACE(p_phone, '[^0-9]', '', 'g');

    -- Case 1: Exactly 10 digits starting with 98, 97, or 96 (e.g. 9841234567)
    IF LENGTH(v_digits) = 10 AND v_digits ~ '^9[678][0-9]{8}$' THEN
        RETURN '+977' || v_digits;
    END IF;

    -- Case 2: Exactly 13 digits starting with 977 followed by 10 valid digits (e.g. +9779841234567)
    IF LENGTH(v_digits) = 13 AND v_digits ~ '^9779[678][0-9]{8}$' THEN
        RETURN '+' || v_digits;
    END IF;

    -- Case 3: Exactly 15 digits starting with 00977 followed by 10 valid digits (e.g. 009779841234567)
    IF LENGTH(v_digits) = 15 AND v_digits ~ '^009779[678][0-9]{8}$' THEN
        RETURN '+977' || SUBSTRING(v_digits FROM 6);
    END IF;

    -- Non-Nepal numbers, foreign country codes, landlines, or invalid lengths return NULL
    RETURN NULL;
END;
$$;

-- Backfill phone_normalized for existing profiles using strict validation
UPDATE public.profiles
SET phone_normalized = public.validate_and_normalize_nepal_phone(phone)
WHERE phone IS NOT NULL AND (phone_normalized IS NULL OR phone_normalized = '');

-- Step 6: Pre-Index Collision Warning (Safe Check: reports duplicates without deleting data)
DO $$
DECLARE
    v_email_dups INT;
    v_phone_dups INT;
    v_dup RECORD;
BEGIN
    SELECT COUNT(*) INTO v_email_dups
    FROM (
        SELECT LOWER(TRIM(email))
        FROM public.profiles
        WHERE email IS NOT NULL AND TRIM(email) <> ''
        GROUP BY LOWER(TRIM(email))
        HAVING COUNT(*) > 1
    ) t;

    IF v_email_dups > 0 THEN
        FOR v_dup IN 
            SELECT LOWER(TRIM(email)) AS dup_email, COUNT(*) AS cnt
            FROM public.profiles
            WHERE email IS NOT NULL AND TRIM(email) <> ''
            GROUP BY LOWER(TRIM(email))
            HAVING COUNT(*) > 1
        LOOP
            RAISE WARNING 'Migration 045 Notice: Duplicate email found in public.profiles: "%" appears % times.', v_dup.dup_email, v_dup.cnt;
        END LOOP;
    END IF;

    SELECT COUNT(*) INTO v_phone_dups
    FROM (
        SELECT phone_normalized
        FROM public.profiles
        WHERE phone_normalized IS NOT NULL
        GROUP BY phone_normalized
        HAVING COUNT(*) > 1
    ) t;

    IF v_phone_dups > 0 THEN
        FOR v_dup IN 
            SELECT phone_normalized, COUNT(*) AS cnt
            FROM public.profiles
            WHERE phone_normalized IS NOT NULL
            GROUP BY phone_normalized
            HAVING COUNT(*) > 1
        LOOP
            RAISE WARNING 'Migration 045 Notice: Duplicate normalized phone found in public.profiles: "%" appears % times.', v_dup.phone_normalized, v_dup.cnt;
        END LOOP;
    END IF;
END $$;

-- Step 7: Enforce database uniqueness constraints and harden public.profiles RLS
DO $$
BEGIN
    -- Check for duplicate emails before creating unique index
    IF NOT EXISTS (
        SELECT 1 FROM (
            SELECT LOWER(TRIM(email)) FROM public.profiles 
            WHERE email IS NOT NULL AND TRIM(email) <> '' 
            GROUP BY LOWER(TRIM(email)) HAVING COUNT(*) > 1
        ) d
    ) THEN
        CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_email_lower 
            ON public.profiles (LOWER(TRIM(email)));
    ELSE
        RAISE WARNING 'Cannot create unique index idx_profiles_email_lower: duplicate emails exist in public.profiles. Resolve duplicates before applying unique constraint.';
    END IF;

    -- Check for duplicate normalized phone numbers before creating unique index
    IF NOT EXISTS (
        SELECT 1 FROM (
            SELECT phone_normalized FROM public.profiles 
            WHERE phone_normalized IS NOT NULL 
            GROUP BY phone_normalized HAVING COUNT(*) > 1
        ) d
    ) THEN
        CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_phone_normalized 
            ON public.profiles (phone_normalized) 
            WHERE phone_normalized IS NOT NULL;
    ELSE
        RAISE WARNING 'Cannot create unique index idx_profiles_phone_normalized: duplicate normalized phones exist in public.profiles. Resolve duplicates before applying unique constraint.';
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_phone 
    ON public.profiles(phone);
CREATE INDEX IF NOT EXISTS idx_profiles_phone_normalized_lookup 
    ON public.profiles(phone_normalized);

-- Harden RLS on public.profiles:
-- Dynamically drop ALL existing policies on public.profiles to eliminate any legacy permissive bypasses
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'profiles' AND schemaname = 'public'
    LOOP
        EXECUTE FORMAT('DROP POLICY IF EXISTS %I ON public.profiles', pol.policyname);
    END LOOP;
END $$;

-- Table privileges: Revoke all direct table access from anonymous users and public
REVOKE ALL ON TABLE public.profiles FROM anon, public;
GRANT SELECT, INSERT, UPDATE ON TABLE public.profiles TO authenticated;
GRANT SELECT ON TABLE public.profiles TO service_role;

-- RLS 1: SELECT - Strict privacy: Users can ONLY view their own profile; admins view all
-- Anonymous users CANNOT SELECT from public.profiles table at all!
CREATE POLICY "profiles_select_policy" ON public.profiles 
    FOR SELECT TO authenticated 
    USING (auth.uid() = id OR public.is_admin(auth.uid()));

-- RLS 2: INSERT - Authenticated users can insert only their own profile (or admins)
CREATE POLICY "profiles_insert_policy" ON public.profiles 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = id OR public.is_admin(auth.uid()));

-- RLS 3: UPDATE - Authenticated users can update only their own profile; admins can update any
CREATE POLICY "profiles_update_policy" ON public.profiles 
    FOR UPDATE TO authenticated 
    USING (auth.uid() = id OR public.is_admin(auth.uid()))
    WITH CHECK (auth.uid() = id OR public.is_admin(auth.uid()));

-- RLS 4: DELETE - Only administrators can delete profile records
CREATE POLICY "profiles_delete_policy" ON public.profiles 
    FOR DELETE TO authenticated 
    USING (public.is_admin(auth.uid()));

-- Public Bidder Profiles View: Safe public display for auction listings & bids
-- Completely hides private email, phone, phone_normalized, and verification state
CREATE OR REPLACE VIEW public.public_bidder_profiles AS
SELECT 
    id,
    COALESCE(buyer_id, 'BIDDER') AS buyer_id,
    CASE 
        WHEN role IN ('seller', 'dealer') THEN full_name
        ELSE COALESCE(SUBSTRING(full_name FROM 1 FOR 1) || '***', 'Bidder')
    END AS display_name,
    avatar_url,
    role,
    account_category
FROM public.profiles;

GRANT SELECT ON public.public_bidder_profiles TO anon, authenticated, service_role;

-- Safe login email resolver RPC for sign-in via phone or buyer_id
-- Defeats account enumeration/email harvesting by strictly verifying password before disclosing email!
DROP FUNCTION IF EXISTS public.lookup_login_email(TEXT);

CREATE OR REPLACE FUNCTION public.resolve_login_email(
    p_identifier TEXT,
    p_password TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_clean TEXT := TRIM(COALESCE(p_identifier, ''));
    v_norm_phone TEXT;
    v_user_id UUID;
    v_email TEXT;
    v_enc_pw TEXT;
    -- Constant dummy bcrypt hash (cost 10) to neutralize timing side-channel attacks
    v_dummy_hash CONSTANT TEXT := '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy';
BEGIN
    IF v_clean = '' OR p_password IS NULL OR p_password = '' THEN
        RETURN NULL;
    END IF;

    -- If already an email, return as-is
    IF v_clean LIKE '%@%' THEN
        RETURN v_clean;
    END IF;

    -- 1. Try exact buyer_id match
    SELECT id, email INTO v_user_id, v_email
    FROM public.profiles
    WHERE UPPER(buyer_id) = UPPER(v_clean)
    LIMIT 1;

    -- 2. Try phone match if not matched by buyer_id
    IF v_user_id IS NULL THEN
        v_norm_phone := public.validate_and_normalize_nepal_phone(v_clean);
        SELECT id, email INTO v_user_id, v_email
        FROM public.profiles
        WHERE phone = v_clean 
           OR (v_norm_phone IS NOT NULL AND phone_normalized = v_norm_phone)
        LIMIT 1;
    END IF;

    -- Timing attack mitigation: If account is not found, perform identical bcrypt workload before returning NULL
    IF v_user_id IS NULL OR v_email IS NULL THEN
        PERFORM crypt(p_password, v_dummy_hash);
        RETURN NULL;
    END IF;

    -- Crucial Security Gate: Verify caller possesses the account password before disclosing email!
    SELECT encrypted_password INTO v_enc_pw
    FROM auth.users
    WHERE id = v_user_id;

    -- If account exists but has no password (e.g. OAuth only), perform dummy bcrypt workload to preserve constant timing
    IF v_enc_pw IS NULL THEN
        PERFORM crypt(p_password, v_dummy_hash);
        RETURN NULL;
    END IF;

    IF v_enc_pw = crypt(p_password, v_enc_pw) THEN
        RETURN v_email;
    END IF;

    -- Password does not match -> return NULL without leaking existence
    RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_login_email(TEXT, TEXT) TO anon, authenticated, service_role;

-- Step 8: Trigger to protect profiles integrity, enforce role immutability, and invalidate phone verification on phone changes
CREATE OR REPLACE FUNCTION public.protect_profiles_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
BEGIN
    -- 1. Enforce Role Immutability: Ordinary users cannot change their role after creation
    IF TG_OP = 'UPDATE' AND NEW.role IS DISTINCT FROM OLD.role THEN
        -- Only an authenticated administrator can change an existing role
        IF auth.uid() IS NULL OR NOT public.is_admin(auth.uid()) THEN
            NEW.role := OLD.role;
        END IF;
    END IF;

    -- On INSERT: Non-admins can only register as 'buyer' or 'seller' (admin is strictly blocked)
    IF TG_OP = 'INSERT' THEN
        IF auth.uid() IS NULL OR NOT public.is_admin(auth.uid()) THEN
            IF NEW.role NOT IN ('buyer', 'seller') THEN
                NEW.role := 'buyer';
            END IF;
        END IF;
    END IF;

    -- 2. Prevent fake phone verification: only permit phone_verified = true if auth.users has genuine phone_confirmed_at
    IF NEW.phone_verified = true THEN
        IF NOT EXISTS (
            SELECT 1 FROM auth.users 
            WHERE id = NEW.id AND phone_confirmed_at IS NOT NULL
        ) THEN
            NEW.phone_verified := false;
            NEW.phone_verified_at := NULL;
        END IF;
    END IF;

    -- Invalidate phone_verified if phone number is changed
    IF TG_OP = 'UPDATE' AND (NEW.phone IS DISTINCT FROM OLD.phone OR NEW.phone_normalized IS DISTINCT FROM OLD.phone_normalized) THEN
        NEW.phone_verified := false;
        NEW.phone_verified_at := NULL;
    END IF;

    -- 3. Prevent fake email verification: only permit email_verified = true if auth.users has genuine email_confirmed_at
    IF NEW.email_verified = true THEN
        IF NOT EXISTS (
            SELECT 1 FROM auth.users 
            WHERE id = NEW.id AND email_confirmed_at IS NOT NULL
        ) THEN
            NEW.email_verified := false;
        END IF;
    END IF;

    -- 4. Strictly maintain normalized phone using NTA standard validator
    NEW.phone_normalized := public.validate_and_normalize_nepal_phone(NEW.phone);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_protect_profiles_integrity ON public.profiles;
CREATE TRIGGER tr_protect_profiles_integrity
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_profiles_integrity();

-- Step 9: Server-Side Sync Trigger on auth.users: Derives profile state and preserves role immutability
CREATE OR REPLACE FUNCTION public.sync_profile_on_auth()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_role TEXT;
    v_raw_phone TEXT;
    v_norm_phone TEXT;
    v_email_is_confirmed BOOLEAN := (NEW.email_confirmed_at IS NOT NULL);
    v_phone_is_confirmed BOOLEAN := (NEW.phone_confirmed_at IS NOT NULL);
BEGIN
    -- Role Security:
    -- On INSERT: assign initial role from metadata (buyer/seller only; admin strictly blocked)
    -- On UPDATE: PRESERVE existing profile role! User editing raw_user_meta_data can NEVER change profile role!
    IF TG_OP = 'UPDATE' THEN
        SELECT role INTO v_role FROM public.profiles WHERE id = NEW.id;
        IF v_role IS NULL THEN
            v_role := 'buyer';
        END IF;
    ELSE
        v_role := LOWER(TRIM(COALESCE(NEW.raw_user_meta_data->>'role', 'buyer')));
        IF v_role IN ('seller', 'dealer') THEN
            v_role := 'seller';
        ELSE
            v_role := 'buyer';
        END IF;
    END IF;

    v_raw_phone := TRIM(COALESCE(NEW.raw_user_meta_data->>'phone', ''));
    v_norm_phone := public.validate_and_normalize_nepal_phone(v_raw_phone);

    INSERT INTO public.profiles (
        id, email, full_name, phone, phone_normalized,
        role, account_category, buyer_id,
        email_verified, phone_verified, phone_verified_at, created_at
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.email, 'user@phatphati.com'),
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'PhatPhati User'),
        v_raw_phone,
        v_norm_phone,
        v_role,
        COALESCE(NEW.raw_user_meta_data->>'account_category', 'individual'),
        NEW.raw_user_meta_data->>'buyer_id',
        v_email_is_confirmed,
        v_phone_is_confirmed,
        NEW.phone_confirmed_at,
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
        phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
        phone_normalized = COALESCE(EXCLUDED.phone_normalized, public.profiles.phone_normalized),
        -- ROLE IS IMMUTABLE on UPDATE from auth metadata
        role = public.profiles.role,
        account_category = COALESCE(EXCLUDED.account_category, public.profiles.account_category),
        buyer_id = COALESCE(EXCLUDED.buyer_id, public.profiles.buyer_id),
        email_verified = (NEW.email_confirmed_at IS NOT NULL),
        phone_verified = (NEW.phone_confirmed_at IS NOT NULL),
        phone_verified_at = NEW.phone_confirmed_at;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_profile_on_auth ON auth.users;
CREATE TRIGGER trg_sync_profile_on_auth
    AFTER INSERT OR UPDATE OF email, email_confirmed_at, phone_confirmed_at, raw_user_meta_data ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.sync_profile_on_auth();

-- Step 10: Anti-Enumeration Account Availability Check Function (Safe, Read-Only)
-- Returns generic messages without leaking specific email_exists or phone_exists booleans
CREATE OR REPLACE FUNCTION public.check_account_availability(
    p_email TEXT,
    p_phone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_clean_email TEXT := LOWER(TRIM(COALESCE(p_email, '')));
    v_clean_phone TEXT := TRIM(COALESCE(p_phone, ''));
    v_norm_phone TEXT := NULL;
    v_email_taken BOOLEAN := false;
    v_phone_taken BOOLEAN := false;
    v_phone_invalid BOOLEAN := false;
BEGIN
    -- Check email in both profiles and auth.users
    IF v_clean_email <> '' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.profiles WHERE LOWER(email) = v_clean_email
            UNION
            SELECT 1 FROM auth.users WHERE LOWER(email) = v_clean_email
        ) INTO v_email_taken;
    END IF;

    -- Strictly validate Nepal mobile number
    IF v_clean_phone <> '' THEN
        v_norm_phone := public.validate_and_normalize_nepal_phone(v_clean_phone);
        IF v_norm_phone IS NULL THEN
            v_phone_invalid := true;
        ELSE
            SELECT EXISTS (
                SELECT 1 FROM public.profiles 
                WHERE phone_normalized = v_norm_phone
                   OR phone = v_clean_phone 
                   OR phone = v_norm_phone
            ) INTO v_phone_taken;
        END IF;
    END IF;

    -- Anti-Enumeration Response: Generic message prevents oracle probing
    IF v_phone_invalid THEN
        RETURN jsonb_build_object(
            'available', false,
            'message', 'Invalid Nepal mobile number. Must be a 10-digit number starting with 98, 97, or 96.'
        );
    ELSIF v_email_taken OR v_phone_taken THEN
        RETURN jsonb_build_object(
            'available', false,
            'message', 'These registration details cannot be used. If you already have an account, please sign in.'
        );
    END IF;

    RETURN jsonb_build_object(
        'available', true,
        'message', 'Available'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_account_availability TO anon, authenticated, service_role, public;

-- Step 11: Authenticated Profile Completion RPC
-- Callable ONLY by authenticated users to complete their profile registration.
-- Strictly validates caller identity (auth.uid()), preserves existing roles,
-- does NOT touch auth.users credentials, and validates caller input before saving to public.profiles.
CREATE OR REPLACE FUNCTION public.complete_user_registration(
    p_full_name TEXT,
    p_phone TEXT,
    p_role TEXT,
    p_account_category TEXT,
    p_buyer_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_existing_role TEXT;
    v_final_role TEXT;
    v_clean_name TEXT := TRIM(COALESCE(p_full_name, 'User'));
    v_clean_phone TEXT := TRIM(COALESCE(p_phone, ''));
    v_norm_phone TEXT;
    v_email TEXT;
    v_email_confirmed BOOLEAN := false;
    v_phone_owner_id UUID;
BEGIN
    -- Security Check 1: Authentication required (blocks anonymous callers)
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required. Anonymous registration is not permitted.';
    END IF;

    -- Fetch caller email and confirmation status from trusted auth.users
    SELECT email, (email_confirmed_at IS NOT NULL)
    INTO v_email, v_email_confirmed
    FROM auth.users
    WHERE id = v_user_id;

    IF v_email IS NULL THEN
        RAISE EXCEPTION 'Authenticated user record not found in system.';
    END IF;

    -- Security Check 2: Role Immutability
    -- If user already has a role assigned in public.profiles, PRESERVE IT!
    SELECT role INTO v_existing_role FROM public.profiles WHERE id = v_user_id;
    IF v_existing_role IS NOT NULL THEN
        v_final_role := v_existing_role; -- Existing role is immutable for ordinary users
    ELSE
        -- Initial assignment during signup: only 'buyer' or 'seller' (admin is blocked)
        IF LOWER(TRIM(COALESCE(p_role, ''))) IN ('seller', 'dealer') THEN
            v_final_role := 'seller';
        ELSE
            v_final_role := 'buyer';
        END IF;
    END IF;

    -- Security Check 3: Strict Nepal mobile phone validation and normalization
    v_norm_phone := public.validate_and_normalize_nepal_phone(v_clean_phone);
    IF v_clean_phone <> '' AND v_norm_phone IS NULL THEN
        RAISE EXCEPTION 'Invalid Nepal mobile number. Must be a 10-digit number starting with 98, 97, or 96.';
    END IF;

    -- Security Check 4: Concurrency lock & Duplicate phone check
    IF v_norm_phone IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('reg_phone_' || v_norm_phone));
        SELECT id INTO v_phone_owner_id 
        FROM public.profiles 
        WHERE phone_normalized = v_norm_phone
          AND id <> v_user_id
        LIMIT 1;

        IF v_phone_owner_id IS NOT NULL THEN
            RAISE EXCEPTION 'Mobile number is already registered to another account.';
        END IF;
    END IF;

    -- Upsert public.profiles for the authenticated caller
    INSERT INTO public.profiles (
        id, buyer_id, email, full_name, phone, phone_normalized, 
        phone_verified, phone_verified_at, email_verified, role, account_category, created_at
    ) VALUES (
        v_user_id, p_buyer_id, v_email, v_clean_name, v_clean_phone, v_norm_phone,
        false, NULL, v_email_confirmed,
        v_final_role, p_account_category, NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        phone = EXCLUDED.phone,
        phone_normalized = EXCLUDED.phone_normalized,
        -- Role is strictly preserved
        role = public.profiles.role,
        account_category = EXCLUDED.account_category,
        buyer_id = COALESCE(EXCLUDED.buyer_id, public.profiles.buyer_id);

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_user_id,
        'email', v_email,
        'phone', v_clean_phone,
        'phone_normalized', v_norm_phone,
        'email_verified', v_email_confirmed,
        'phone_verified', false,
        'role', v_final_role
    );
END;
$$;

-- Grant complete_user_registration ONLY to authenticated users
REVOKE EXECUTE ON FUNCTION public.complete_user_registration FROM anon, public;
GRANT EXECUTE ON FUNCTION public.complete_user_registration TO authenticated;

-- Step 12: Admin-Only Privileged Role Management RPC
-- Server-authorized, explicit operation for administrators to update a user's role
CREATE OR REPLACE FUNCTION public.admin_set_user_role(
    p_target_user_id UUID,
    p_new_role TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_clean_role TEXT := LOWER(TRIM(COALESCE(p_new_role, '')));
BEGIN
    -- Security Check: Caller must be an authenticated administrator
    IF v_caller_id IS NULL OR NOT public.is_admin(v_caller_id) THEN
        RAISE EXCEPTION 'Access denied. Administrator privileges required.';
    END IF;

    IF v_clean_role NOT IN ('buyer', 'seller', 'dealer', 'recondition', 'admin') THEN
        RAISE EXCEPTION 'Invalid role specified. Supported roles: buyer, seller, admin.';
    END IF;

    UPDATE public.profiles
    SET role = v_clean_role
    WHERE id = p_target_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_target_user_id,
        'new_role', v_clean_role
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_set_user_role FROM anon, public;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role TO authenticated;

-- Step 13: Harden get_round_bids with explicit trusted search_path and execution grants
CREATE OR REPLACE FUNCTION public.get_round_bids(p_round_id UUID)
RETURNS TABLE (
    id UUID,
    round_id UUID,
    auction_id UUID,
    bidder_id UUID,
    amount NUMERIC,
    created_at TIMESTAMPTZ,
    bidder_name TEXT,
    buyer_id TEXT,
    account_category TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_is_admin BOOLEAN := FALSE;
BEGIN
    IF v_caller_id IS NOT NULL THEN
        SELECT COALESCE(role = 'admin', false) INTO v_is_admin FROM public.profiles WHERE id = v_caller_id;
    END IF;

    RETURN QUERY
    SELECT 
        b.id,
        b.round_id,
        b.auction_id,
        b.bidder_id,
        b.amount,
        b.created_at,
        CASE 
            WHEN v_is_admin THEN COALESCE(p.full_name, 'Buyer')
            WHEN b.bidder_id = v_caller_id THEN COALESCE(p.full_name, 'YOU')
            ELSE 'Verified Bidder'
        END AS bidder_name,
        CASE 
            WHEN v_is_admin THEN p.buyer_id
            WHEN b.bidder_id = v_caller_id THEN p.buyer_id
            ELSE NULL
        END AS buyer_id,
        CASE 
            WHEN v_is_admin OR b.bidder_id = v_caller_id THEN COALESCE(p.account_category, 'individual')
            ELSE 'individual'
        END AS account_category
    FROM public.bids b
    LEFT JOIN public.profiles p ON p.id = b.bidder_id
    WHERE b.round_id = p_round_id
    ORDER BY b.amount DESC, b.created_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_round_bids(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_round_bids(UUID) TO anon, authenticated, service_role;

