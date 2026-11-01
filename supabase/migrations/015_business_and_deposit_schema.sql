-- Migration 015: Dealer & Recondition Business Registration and Post-Auction Booking Deposit Schema

-- 1. UPDATE PROFILES TABLE FOR ACCOUNT CATEGORIES
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS account_category TEXT NOT NULL DEFAULT 'individual' CHECK (account_category IN ('individual', 'dealer', 'recondition'));
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pending_business_setup BOOLEAN DEFAULT FALSE;

-- 2. BUSINESS PROFILES TABLE & REVIEWS AUDIT
CREATE TABLE IF NOT EXISTS public.business_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID UNIQUE NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    account_type TEXT NOT NULL CHECK (account_type IN ('dealer', 'recondition')),
    company_name TEXT NOT NULL,
    company_pan_number TEXT NOT NULL,
    company_pan_path TEXT NOT NULL,
    company_registration_path TEXT NOT NULL,
    company_bank_name TEXT NOT NULL,
    company_account_number TEXT NOT NULL,
    company_qr_path TEXT NOT NULL,
    company_phone TEXT NOT NULL,
    primary_name TEXT NOT NULL,
    primary_email TEXT NOT NULL,
    primary_phone TEXT NOT NULL,
    secondary_name TEXT,
    secondary_email TEXT,
    secondary_phone TEXT,
    dealership_brand TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'suspended')),
    reviewed_by UUID REFERENCES public.profiles(id),
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.business_review_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES public.business_profiles(id) ON DELETE CASCADE,
    old_status TEXT,
    new_status TEXT NOT NULL,
    rejection_reason TEXT,
    reviewed_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. LINK AUCTIONS TO BUSINESS PROFILES (NULLABLE FOR INDIVIDUAL AUCTIONS)
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.business_profiles(id) ON DELETE SET NULL;

-- 4. PLATFORM PAYMENT SETTINGS TABLE (ADMIN MANAGED BANK DETAILS & QR)
CREATE TABLE IF NOT EXISTS public.platform_payment_settings (
    id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    bank_name TEXT NOT NULL DEFAULT 'Global IME Bank',
    account_name TEXT NOT NULL DEFAULT 'AutoBid Platform Pvt Ltd',
    account_number TEXT NOT NULL DEFAULT '0123456789012345',
    platform_qr_path TEXT,
    payment_instructions TEXT DEFAULT 'Please deposit the 10% booking amount to our platform account and upload your payment receipt/screenshot with your booking reference.',
    updated_by UUID REFERENCES public.profiles(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.platform_payment_settings (id, bank_name, account_name, account_number, payment_instructions)
VALUES (1, 'Global IME Bank', 'AutoBid Platform Pvt Ltd', '0123456789012345', 'Please deposit the 10% booking amount to our platform account and upload your payment receipt/screenshot with your booking reference.')
ON CONFLICT (id) DO NOTHING;

-- 5. DEPOSIT RECORDS & IMMUTABLE EVIDENCE SUBMISSIONS TABLE
CREATE TABLE IF NOT EXISTS public.deposit_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auction_id UUID UNIQUE REFERENCES public.auctions(id) ON DELETE SET NULL, -- Retain record if auction is deleted
    winner_id UUID NOT NULL REFERENCES public.profiles(id),
    booking_reference TEXT UNIQUE NOT NULL,
    winning_amount NUMERIC(12,2) NOT NULL CHECK (winning_amount > 0),
    deposit_amount NUMERIC(12,2) NOT NULL CHECK (deposit_amount > 0),
    remaining_balance NUMERIC(12,2) NOT NULL CHECK (remaining_balance >= 0),
    payment_due_at TIMESTAMPTZ NOT NULL,
    payment_status TEXT NOT NULL DEFAULT 'awaiting_payment' CHECK (payment_status IN ('awaiting_payment', 'under_review', 'verified', 'rejected')),
    vehicle_reservation_status TEXT NOT NULL DEFAULT 'awaiting_deposit' CHECK (vehicle_reservation_status IN ('awaiting_deposit', 'reserved')),
    current_evidence_id UUID,
    reviewed_by UUID REFERENCES public.profiles(id),
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    admin_instructions TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.deposit_evidence_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES public.deposit_records(id) ON DELETE CASCADE,
    winner_id UUID NOT NULL REFERENCES public.profiles(id),
    evidence_path TEXT NOT NULL,
    evidence_type TEXT NOT NULL CHECK (evidence_type IN ('image', 'pdf')),
    transaction_reference TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.deposit_review_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES public.deposit_records(id) ON DELETE CASCADE,
    old_payment_status TEXT,
    new_payment_status TEXT NOT NULL,
    rejection_reason TEXT,
    reviewed_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. STORAGE BUCKETS SETUP FOR BUSINESS & DEPOSIT EVIDENCE
INSERT INTO storage.buckets (id, name, public)
VALUES ('business-documents', 'business-documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

INSERT INTO storage.buckets (id, name, public)
VALUES ('deposit-evidence', 'deposit-evidence', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- STORAGE RLS FOR BUSINESS DOCUMENTS
DROP POLICY IF EXISTS "Business Documents Access" ON storage.objects;
CREATE POLICY "Business Documents Access"
    ON storage.objects FOR ALL
    TO anon, authenticated, public
    USING (
        bucket_id = 'business-documents'
        AND (
            (storage.foldername(name))[1] = auth.uid()::text
            OR EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
        )
    )
    WITH CHECK (
        bucket_id = 'business-documents'
        AND (
            (storage.foldername(name))[1] = auth.uid()::text
            OR EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
        )
    );

-- STORAGE RLS FOR DEPOSIT EVIDENCE (CLIENT CANNOT DELETE SUBMITTED EVIDENCE)
DROP POLICY IF EXISTS "Deposit Evidence Select" ON storage.objects;
DROP POLICY IF EXISTS "Deposit Evidence Insert" ON storage.objects;

CREATE POLICY "Deposit Evidence Select"
    ON storage.objects FOR SELECT
    TO anon, authenticated, public
    USING (
        bucket_id = 'deposit-evidence'
        AND (
            (storage.foldername(name))[1] = auth.uid()::text
            OR EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
        )
    );

CREATE POLICY "Deposit Evidence Insert"
    ON storage.objects FOR INSERT
    TO anon, authenticated, public
    WITH CHECK (
        bucket_id = 'deposit-evidence'
        AND (
            (storage.foldername(name))[1] = auth.uid()::text
            OR EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
        )
    );

-- 7. TABLE RLS POLICIES
ALTER TABLE public.business_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_payment_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_evidence_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Business profiles select policy" ON public.business_profiles;
DROP POLICY IF EXISTS "Business profiles insert policy" ON public.business_profiles;
DROP POLICY IF EXISTS "Business profiles update policy" ON public.business_profiles;

CREATE POLICY "Business profiles select policy"
    ON public.business_profiles FOR SELECT TO anon, authenticated, public
    USING (owner_user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "Business profiles insert policy"
    ON public.business_profiles FOR INSERT TO anon, authenticated, public
    WITH CHECK (owner_user_id = auth.uid() OR auth.uid() IS NULL);

CREATE POLICY "Business profiles update policy"
    ON public.business_profiles FOR UPDATE TO anon, authenticated, public
    USING (owner_user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- PLATFORM PAYMENT SETTINGS RLS
DROP POLICY IF EXISTS "Platform payment settings select" ON public.platform_payment_settings;
DROP POLICY IF EXISTS "Platform payment settings update" ON public.platform_payment_settings;

CREATE POLICY "Platform payment settings select"
    ON public.platform_payment_settings FOR SELECT TO anon, authenticated, public USING (true);

CREATE POLICY "Platform payment settings update"
    ON public.platform_payment_settings FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- DEPOSIT RECORDS RLS
DROP POLICY IF EXISTS "Deposit records select" ON public.deposit_records;
CREATE POLICY "Deposit records select"
    ON public.deposit_records FOR SELECT TO anon, authenticated, public
    USING (winner_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- DEPOSIT EVIDENCE SUBMISSIONS RLS
DROP POLICY IF EXISTS "Deposit evidence submissions select" ON public.deposit_evidence_submissions;
DROP POLICY IF EXISTS "Deposit evidence submissions insert" ON public.deposit_evidence_submissions;

CREATE POLICY "Deposit evidence submissions select"
    ON public.deposit_evidence_submissions FOR SELECT TO anon, authenticated, public
    USING (winner_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "Deposit evidence submissions insert"
    ON public.deposit_evidence_submissions FOR INSERT TO anon, authenticated, public
    WITH CHECK (winner_id = auth.uid() OR auth.uid() IS NULL);

-- 8. TRIGGER: BUSINESS PROFILES COLUMN WRITE PROTECTION & RE-REVIEW
CREATE OR REPLACE FUNCTION public.fn_business_profiles_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_is_admin BOOLEAN := FALSE;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
        ) INTO v_is_admin;
    END IF;

    -- If non-admin user is updating
    IF NOT v_is_admin THEN
        -- Prevent owner from changing owner_user_id
        IF NEW.owner_user_id <> OLD.owner_user_id THEN
            RAISE EXCEPTION 'Unauthorized: You cannot change the owner user of a business.';
        END IF;

        -- If suspended, enforce suspension lock (owner edits cannot clear suspension)
        IF OLD.status = 'suspended' THEN
            NEW.status := 'suspended';
            NEW.reviewed_by := OLD.reviewed_by;
            NEW.reviewed_at := OLD.reviewed_at;
            NEW.rejection_reason := OLD.rejection_reason;
        -- If approved, any registration/banking/contact edit resets status to pending
        ELSIF OLD.status = 'approved' AND (
            NEW.company_name <> OLD.company_name OR
            NEW.company_pan_number <> OLD.company_pan_number OR
            NEW.company_pan_path <> OLD.company_pan_path OR
            NEW.company_registration_path <> OLD.company_registration_path OR
            NEW.company_bank_name <> OLD.company_bank_name OR
            NEW.company_account_number <> OLD.company_account_number OR
            NEW.company_qr_path <> OLD.company_qr_path OR
            NEW.company_phone <> OLD.company_phone OR
            NEW.primary_name <> OLD.primary_name OR
            NEW.primary_email <> OLD.primary_email OR
            NEW.primary_phone <> OLD.primary_phone OR
            COALESCE(NEW.dealership_brand, '') <> COALESCE(OLD.dealership_brand, '')
        ) THEN
            NEW.status := 'pending';
            NEW.reviewed_by := NULL;
            NEW.reviewed_at := NULL;
            NEW.rejection_reason := NULL;

            INSERT INTO public.business_review_logs (business_id, old_status, new_status, rejection_reason, reviewed_by)
            VALUES (OLD.id, OLD.status, 'pending', 'Automatic reset due to details update', NULL);
        ELSIF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
            RAISE EXCEPTION 'Unauthorized: Only an administrator can approve a business profile.';
        END IF;
    END IF;

    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_business_profiles_guard ON public.business_profiles;
CREATE TRIGGER trg_business_profiles_guard
    BEFORE UPDATE ON public.business_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_business_profiles_guard();

-- 9. PUBLIC BUSINESS INFO RPC
CREATE OR REPLACE FUNCTION public.get_public_business_info(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rec RECORD;
BEGIN
    SELECT id, company_name, account_type, dealership_brand, status, owner_user_id
    INTO v_rec
    FROM public.business_profiles
    WHERE id = p_business_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    RETURN jsonb_build_object(
        'id', v_rec.id,
        'company_name', v_rec.company_name,
        'account_type', v_rec.account_type,
        'dealership_brand', v_rec.dealership_brand,
        'status', v_rec.status,
        'owner_user_id', v_rec.owner_user_id
    );
END;
$$;

-- 10. RPC: ADMIN REVIEW BUSINESS APPLICATION
CREATE OR REPLACE FUNCTION public.admin_review_business(
    p_business_id UUID,
    p_status TEXT,
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_old_status TEXT;
BEGIN
    IF v_admin_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_admin_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can review business applications.';
    END IF;

    SELECT status INTO v_old_status FROM public.business_profiles WHERE id = p_business_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Business profile not found.';
    END IF;

    UPDATE public.business_profiles
    SET status = p_status,
        rejection_reason = CASE WHEN p_status = 'rejected' THEN p_rejection_reason ELSE NULL END,
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_business_id;

    INSERT INTO public.business_review_logs (business_id, old_status, new_status, rejection_reason, reviewed_by)
    VALUES (p_business_id, v_old_status, p_status, p_rejection_reason, v_admin_id);

    RETURN jsonb_build_object('success', true, 'status', p_status);
END;
$$;

-- 11. RPC: CREATE DEPOSIT BOOKING (IDEMPOTENT & ROUNDED 10%)
CREATE OR REPLACE FUNCTION public.create_deposit_booking(p_auction_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_existing RECORD;
    v_round RECORD;
    v_auction RECORD;
    v_winning_amount NUMERIC(12,2);
    v_deposit_amount NUMERIC(12,2);
    v_remaining_balance NUMERIC(12,2);
    v_booking_ref TEXT;
    v_booking_id UUID;
BEGIN
    -- Check if booking record already exists
    SELECT * INTO v_existing FROM public.deposit_records WHERE auction_id = p_auction_id;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'booking_id', v_existing.id,
            'booking_reference', v_existing.booking_reference,
            'winning_amount', v_existing.winning_amount,
            'deposit_amount', v_existing.deposit_amount,
            'remaining_balance', v_existing.remaining_balance,
            'payment_status', v_existing.payment_status,
            'reservation_status', v_existing.vehicle_reservation_status
        );
    END IF;

    -- Fetch latest round for auction
    SELECT * INTO v_round
    FROM public.auction_rounds
    WHERE auction_id = p_auction_id
    ORDER BY round_number DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found.';
    END IF;

    -- Require valid winner and highest bid
    IF v_round.highest_bidder_id IS NULL OR v_round.current_highest_bid IS NULL OR v_round.current_highest_bid <= 0 THEN
        RAISE EXCEPTION 'Auction ended without a valid winning bid.';
    END IF;

    v_winning_amount := v_round.current_highest_bid;
    -- Calculate rounded 10% deposit first, then remaining balance = winning_amount - deposit_amount
    v_deposit_amount := ROUND(v_winning_amount * 0.10, 2);
    v_remaining_balance := v_winning_amount - v_deposit_amount;
    v_booking_ref := 'BOOK-' || UPPER(SUBSTRING(MD5(p_auction_id::text || NOW()::text) FROM 1 FOR 8));

    INSERT INTO public.deposit_records (
        auction_id,
        winner_id,
        booking_reference,
        winning_amount,
        deposit_amount,
        remaining_balance,
        payment_due_at,
        payment_status,
        vehicle_reservation_status
    ) VALUES (
        p_auction_id,
        v_round.highest_bidder_id,
        v_booking_ref,
        v_winning_amount,
        v_deposit_amount,
        v_remaining_balance,
        NOW() + INTERVAL '24 hours',
        'awaiting_payment',
        'awaiting_deposit'
    ) RETURNING id INTO v_booking_id;

    RETURN jsonb_build_object(
        'success', true,
        'booking_id', v_booking_id,
        'booking_reference', v_booking_ref,
        'winning_amount', v_winning_amount,
        'deposit_amount', v_deposit_amount,
        'remaining_balance', v_remaining_balance,
        'payment_status', 'awaiting_payment',
        'reservation_status', 'awaiting_deposit'
    );
END;
$$;

-- 12. RPC: SUBMIT DEPOSIT EVIDENCE (VALIDATES BOOKING & WINNER OWNERSHIP)
CREATE OR REPLACE FUNCTION public.submit_deposit_evidence(
    p_booking_id UUID,
    p_evidence_path TEXT,
    p_evidence_type TEXT,
    p_transaction_reference TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_booking RECORD;
    v_caller_id UUID := auth.uid();
    v_submission_id UUID;
BEGIN
    SELECT * INTO v_booking FROM public.deposit_records WHERE id = p_booking_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking record not found.';
    END IF;

    -- Validate that caller is the winner of this booking
    IF v_caller_id IS NOT NULL AND v_caller_id <> v_booking.winner_id THEN
        RAISE EXCEPTION 'Unauthorized: Only the winner of this booking can submit payment evidence.';
    END IF;

    -- Lock submission if already verified
    IF v_booking.payment_status = 'verified' THEN
        RAISE EXCEPTION 'Forbidden: Verified deposit records cannot be resubmitted or modified.';
    END IF;

    -- Record immutable submission entry
    INSERT INTO public.deposit_evidence_submissions (
        booking_id, winner_id, evidence_path, evidence_type, transaction_reference, submitted_at
    ) VALUES (
        p_booking_id, v_booking.winner_id, p_evidence_path, p_evidence_type, p_transaction_reference, NOW()
    ) RETURNING id INTO v_submission_id;

    -- Update booking status to under_review
    UPDATE public.deposit_records
    SET payment_status = 'under_review',
        current_evidence_id = v_submission_id,
        rejection_reason = NULL,
        updated_at = NOW()
    WHERE id = p_booking_id;

    RETURN jsonb_build_object(
        'success', true,
        'submission_id', v_submission_id,
        'payment_status', 'under_review'
    );
END;
$$;

-- 13. RPC: ADMIN VERIFY DEPOSIT & UPDATE INSTRUCTIONS
CREATE OR REPLACE FUNCTION public.admin_verify_deposit(
    p_booking_id UUID,
    p_status TEXT,
    p_rejection_reason TEXT DEFAULT NULL,
    p_instructions TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_booking RECORD;
BEGIN
    IF v_admin_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_admin_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can verify deposits.';
    END IF;

    SELECT * INTO v_booking FROM public.deposit_records WHERE id = p_booking_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking record not found.';
    END IF;

    -- Prevent modifying or rejecting an already verified deposit
    IF v_booking.payment_status = 'verified' AND p_status <> 'verified' THEN
        RAISE EXCEPTION 'Forbidden: Verified deposits cannot be rejected or un-verified.';
    END IF;

    UPDATE public.deposit_records
    SET payment_status = p_status,
        vehicle_reservation_status = CASE WHEN p_status = 'verified' THEN 'reserved' ELSE v_booking.vehicle_reservation_status END,
        rejection_reason = CASE WHEN p_status = 'rejected' THEN p_rejection_reason ELSE NULL END,
        admin_instructions = COALESCE(p_instructions, v_booking.admin_instructions),
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_booking_id;

    INSERT INTO public.deposit_review_logs (booking_id, old_payment_status, new_payment_status, rejection_reason, reviewed_by)
    VALUES (p_booking_id, v_booking.payment_status, p_status, p_rejection_reason, v_admin_id);

    RETURN jsonb_build_object('success', true, 'payment_status', p_status, 'reservation_status', CASE WHEN p_status = 'verified' THEN 'reserved' ELSE v_booking.vehicle_reservation_status END);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_deposit_instructions(
    p_booking_id UUID,
    p_instructions TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
BEGIN
    IF v_admin_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_admin_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can update next-step instructions.';
    END IF;

    UPDATE public.deposit_records
    SET admin_instructions = p_instructions,
        updated_at = NOW()
    WHERE id = p_booking_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 14. UPDATED CREATE VEHICLE AUCTION WITH BUSINESS OWNERSHIP & APPROVAL CHECK
CREATE OR REPLACE FUNCTION public.create_vehicle_auction(
    p_title TEXT,
    p_description TEXT,
    p_starting_price NUMERIC,
    p_min_increment NUMERIC,
    p_status TEXT,
    p_reopen_duration_minutes INT,
    p_start_at TIMESTAMPTZ,
    p_end_at TIMESTAMPTZ,
    p_vehicle_type TEXT,
    p_brand_name TEXT,
    p_model TEXT,
    p_built_year INT,
    p_year_calendar TEXT,
    p_lot_number TEXT,
    p_registration_number TEXT,
    p_kilometres_run NUMERIC,
    p_number_of_owners INT,
    p_fuel_type TEXT,
    p_engine_opened TEXT,
    p_colour TEXT,
    p_engine_capacity NUMERIC,
    p_tax_status TEXT,
    p_bluebook_front_path TEXT,
    p_bluebook_back_path TEXT,
    p_bluebook_owner_path TEXT,
    p_vehicle_front_path TEXT,
    p_vehicle_back_path TEXT,
    p_vehicle_right_path TEXT,
    p_vehicle_left_path TEXT,
    p_odometer_path TEXT,
    p_business_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := COALESCE(auth.uid(), '11111111-1111-1111-1111-111111111111'::uuid);
    v_auction_id UUID;
    v_created_auction JSONB;
    v_biz RECORD;
BEGIN
    -- If p_business_id is provided, validate that caller owns the business AND it is APPROVED
    IF p_business_id IS NOT NULL THEN
        SELECT * INTO v_biz FROM public.business_profiles WHERE id = p_business_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid Business ID.';
        END IF;
        IF v_biz.owner_user_id <> v_user_id AND v_user_id <> '11111111-1111-1111-1111-111111111111'::uuid THEN
            RAISE EXCEPTION 'Unauthorized: You do not own this business profile.';
        END IF;
        IF v_biz.status <> 'approved' THEN
            RAISE EXCEPTION 'Forbidden: Only approved business accounts can publish business auctions.';
        END IF;
    END IF;

    -- Ensure profile exists in profiles table
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (
        v_user_id,
        COALESCE(auth.jwt() ->> 'email', 'admin@auction.com'),
        COALESCE(auth.jwt() -> 'user_metadata' ->> 'full_name', 'Auction Admin'),
        COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', 'admin')
    )
    ON CONFLICT (id) DO NOTHING;

    -- Insert Auction Record
    INSERT INTO public.auctions (
        title, description, starting_price, min_increment, status, reopen_duration_minutes, created_by, business_id,
        vehicle_type, brand_name, model, built_year, year_calendar, lot_number, registration_number,
        kilometres_run, number_of_owners, fuel_type, engine_opened, colour, engine_capacity, tax_status,
        bluebook_front_path, bluebook_back_path, bluebook_owner_path,
        vehicle_front_path, vehicle_back_path, vehicle_right_path, vehicle_left_path, odometer_path
    ) VALUES (
        p_title, p_description, p_starting_price, p_min_increment, p_status, p_reopen_duration_minutes, v_user_id, p_business_id,
        p_vehicle_type, p_brand_name, p_model, p_built_year, p_year_calendar, p_lot_number, p_registration_number,
        p_kilometres_run, p_number_of_owners, p_fuel_type, p_engine_opened, p_colour, p_engine_capacity, p_tax_status,
        p_bluebook_front_path, p_bluebook_back_path, p_bluebook_owner_path,
        p_vehicle_front_path, p_vehicle_back_path, p_vehicle_right_path, p_vehicle_left_path, p_odometer_path
    ) RETURNING id INTO v_auction_id;

    -- Insert Initial Cover & Vehicle Images into auction_images
    IF p_vehicle_front_path IS NOT NULL THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (v_auction_id, p_vehicle_front_path, 1, true);
    END IF;
    IF p_vehicle_back_path IS NOT NULL THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (v_auction_id, p_vehicle_back_path, 2, false);
    END IF;
    IF p_vehicle_right_path IS NOT NULL THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (v_auction_id, p_vehicle_right_path, 3, false);
    END IF;
    IF p_vehicle_left_path IS NOT NULL THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (v_auction_id, p_vehicle_left_path, 4, false);
    END IF;

    -- Create Initial Round 1
    INSERT INTO public.auction_rounds (auction_id, round_number, start_at, end_at, status)
    VALUES (v_auction_id, 1, p_start_at, p_end_at, p_status);

    SELECT jsonb_build_object('auction_id', v_auction_id, 'status', 'created') INTO v_created_auction;
    RETURN v_created_auction;
END;
$$;

-- 15. UPDATED PLACE_BID RPC WITH SELF-BIDDING PREVENTION
CREATE OR REPLACE FUNCTION public.place_bid(
    p_auction_id UUID,
    p_amount NUMERIC,
    p_bidder_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_bidder_id UUID;
    v_round RECORD;
    v_auction RECORD;
    v_min_next_bid NUMERIC;
    v_server_now TIMESTAMPTZ := transaction_timestamp();
    v_bid_id UUID;
    v_created_bid JSONB;
    v_biz_owner_id UUID;
BEGIN
    -- Determine active bidder ID
    v_bidder_id := COALESCE(p_bidder_id, auth.uid(), '11111111-1111-1111-1111-111111111111'::uuid);

    -- Fetch parent auction
    SELECT * INTO v_auction FROM public.auctions WHERE id = p_auction_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target auction record not found.';
    END IF;

    -- PREVENT SELF-BIDDING (Creator ID or Linked Business Owner ID)
    IF v_bidder_id = v_auction.created_by THEN
        RAISE EXCEPTION 'Forbidden: You cannot bid on your own auction.';
    END IF;

    IF v_auction.business_id IS NOT NULL THEN
        SELECT owner_user_id INTO v_biz_owner_id FROM public.business_profiles WHERE id = v_auction.business_id;
        IF v_bidder_id = v_biz_owner_id THEN
            RAISE EXCEPTION 'Forbidden: You cannot bid on an auction belonging to your business.';
        END IF;
    END IF;

    -- Lock latest active round for target auction
    SELECT * INTO v_round
    FROM public.auction_rounds
    WHERE auction_id = p_auction_id
    ORDER BY round_number DESC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auction round not found for specified auction.';
    END IF;

    -- Auto-transition upcoming round to live if server_now is within timing window
    IF (v_round.status = 'upcoming' OR v_auction.status = 'upcoming') 
       AND v_server_now >= v_round.start_at 
       AND v_server_now < v_round.end_at THEN
        UPDATE public.auction_rounds SET status = 'live' WHERE id = v_round.id;
        UPDATE public.auctions SET status = 'live' WHERE id = p_auction_id;
        v_round.status := 'live';
    END IF;

    -- Server time & status validation
    IF v_server_now < v_round.start_at THEN
        RAISE EXCEPTION 'This auction has not started yet.';
    END IF;

    IF v_server_now >= v_round.end_at OR v_round.status != 'live' THEN
        RAISE EXCEPTION 'This auction has already ended or is not live.';
    END IF;

    -- Calculate required minimum next bid
    IF v_round.current_highest_bid IS NULL OR v_round.current_highest_bid = 0 THEN
        v_min_next_bid := v_auction.starting_price;
    ELSE
        v_min_next_bid := v_round.current_highest_bid + v_auction.min_increment;
    END IF;

    -- Check if amount is valid
    IF p_amount < v_min_next_bid THEN
        RAISE EXCEPTION 'Bid amount of Rs. % is below the minimum required bid of Rs. %', p_amount, v_min_next_bid;
    END IF;

    -- Insert new bid into bids table
    INSERT INTO public.bids (auction_id, round_id, bidder_id, amount, created_at)
    VALUES (p_auction_id, v_round.id, v_bidder_id, p_amount, NOW())
    RETURNING id INTO v_bid_id;

    -- Update auction round with new highest bid and leader
    UPDATE public.auction_rounds
    SET current_highest_bid = p_amount,
        highest_bidder_id = v_bidder_id,
        updated_at = NOW()
    WHERE id = v_round.id;

    -- Update parent auction timestamp for realtime sync
    UPDATE public.auctions
    SET updated_at = NOW()
    WHERE id = p_auction_id;

    SELECT jsonb_build_object(
        'success', true,
        'bid_id', v_bid_id,
        'amount', p_amount,
        'bidder_id', v_bidder_id,
        'round_id', v_round.id,
        'message', 'Bid placed successfully!'
    ) INTO v_created_bid;

    RETURN v_created_bid;
END;
$$;
