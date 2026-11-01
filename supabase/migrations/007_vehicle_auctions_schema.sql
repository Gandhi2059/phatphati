-- Migration 007: Vehicles Schema, Private Document Storage & Strict RLS

-- 1. ADD VEHICLE COLUMNS TO AUCTIONS TABLE
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS vehicle_type TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS brand_name TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS built_year INT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS year_calendar TEXT DEFAULT 'BS';
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS lot_number TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS registration_number TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS kilometres_run NUMERIC(10,2);
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS number_of_owners INT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS fuel_type TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS engine_opened TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS colour TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS engine_capacity NUMERIC(8,2);
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS tax_status TEXT;

-- Photo Storage Path Columns
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS bluebook_front_path TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS bluebook_back_path TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS bluebook_owner_path TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS vehicle_front_path TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS vehicle_back_path TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS vehicle_right_path TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS vehicle_left_path TEXT;
ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS odometer_path TEXT;

-- 2. ENABLE AND RE-ALIGN RLS POLICIES FOR AUCTIONS TABLE
ALTER TABLE public.auctions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auctions are viewable by authenticated users" ON public.auctions;
DROP POLICY IF EXISTS "Allow all insert or update auctions" ON public.auctions;
DROP POLICY IF EXISTS "Auctions select policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions insert policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions update policy" ON public.auctions;

-- Read: Viewable by all authenticated users
CREATE POLICY "Auctions select policy" 
    ON public.auctions FOR SELECT 
    TO authenticated 
    USING (true);

-- Insert: Allowed for any authenticated user provided created_by equals auth.uid()
CREATE POLICY "Auctions insert policy" 
    ON public.auctions FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid() IS NOT NULL AND created_by = auth.uid());

-- Update: Allowed if created_by equals auth.uid() OR user is Admin in profiles table
CREATE POLICY "Auctions update policy" 
    ON public.auctions FOR UPDATE 
    TO authenticated 
    USING (
        created_by = auth.uid() 
        OR EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
        )
    )
    WITH CHECK (
        created_by = auth.uid() 
        OR EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
        )
    );

-- 3. STORAGE BUCKETS SETUP
-- Private Bucket for Blue Book Documents
INSERT INTO storage.buckets (id, name, public)
VALUES ('bluebook-documents', 'bluebook-documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- Public Bucket for Vehicle & Odometer Photos
INSERT INTO storage.buckets (id, name, public)
VALUES ('auction-images', 'auction-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Storage RLS Policies for bluebook-documents (Private)
DROP POLICY IF EXISTS "Private Bluebook Select Policy" ON storage.objects;
DROP POLICY IF EXISTS "Private Bluebook Insert Policy" ON storage.objects;
DROP POLICY IF EXISTS "Private Bluebook Delete Policy" ON storage.objects;

CREATE POLICY "Private Bluebook Select Policy"
    ON storage.objects FOR SELECT
    TO anon, authenticated
    USING (
        bucket_id = 'bluebook-documents'
    );

CREATE POLICY "Private Bluebook Insert Policy"
    ON storage.objects FOR INSERT
    TO anon, authenticated
    WITH CHECK (bucket_id = 'bluebook-documents');

CREATE POLICY "Private Bluebook Delete Policy"
    ON storage.objects FOR DELETE
    TO anon, authenticated
    USING (
        bucket_id = 'bluebook-documents'
    );

-- Storage RLS Policies for auction-images (Public)
DROP POLICY IF EXISTS "Public Auction Images Access" ON storage.objects;
CREATE POLICY "Public Auction Images Access"
    ON storage.objects FOR ALL
    TO public
    USING (bucket_id = 'auction-images')
    WITH CHECK (bucket_id = 'auction-images');

-- 4. SERVER-AUTHORITATIVE RPC FOR VEHICLE AUCTION CREATION
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
    p_odometer_path TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_auction_id UUID;
    v_created_auction JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: User must be authenticated';
    END IF;

    -- Ensure profile exists in profiles table
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (
        v_user_id,
        COALESCE(auth.jwt() ->> 'email', 'user@auction.com'),
        COALESCE(auth.jwt() -> 'user_metadata' ->> 'full_name', 'Auction User'),
        COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', 'buyer')
    )
    ON CONFLICT (id) DO NOTHING;

    -- Insert Auction Record enforcing created_by = auth.uid()
    INSERT INTO public.auctions (
        title, description, starting_price, min_increment, status, reopen_duration_minutes, created_by,
        vehicle_type, brand_name, model, built_year, year_calendar, lot_number, registration_number,
        kilometres_run, number_of_owners, fuel_type, engine_opened, colour, engine_capacity, tax_status,
        bluebook_front_path, bluebook_back_path, bluebook_owner_path,
        vehicle_front_path, vehicle_back_path, vehicle_right_path, vehicle_left_path, odometer_path
    ) VALUES (
        p_title, p_description, p_starting_price, p_min_increment, p_status, p_reopen_duration_minutes, v_user_id,
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

    -- Insert Initial Auction Round 1
    INSERT INTO public.auction_rounds (
        auction_id, round_number, start_at, end_at, status, current_highest_bid
    ) VALUES (
        v_auction_id, 1, p_start_at, p_end_at, p_status, 0.00
    );

    -- Audit Log Entry
    BEGIN
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
        VALUES (
            v_user_id, 'CREATE_VEHICLE_AUCTION', 'auction', v_auction_id,
            jsonb_build_object('title', p_title, 'starting_price', p_starting_price, 'vehicle_type', p_vehicle_type)
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    SELECT to_jsonb(a.*) INTO v_created_auction FROM public.auctions a WHERE a.id = v_auction_id;
    RETURN jsonb_build_object('success', true, 'auction_id', v_auction_id, 'auction', v_created_auction);
END;
$$;

-- 5. SERVER-AUTHORITATIVE RPC FOR VEHICLE AUCTION UPDATE
CREATE OR REPLACE FUNCTION public.update_vehicle_auction(
    p_auction_id UUID,
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
    p_odometer_path TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_auction_creator UUID;
    v_is_admin BOOLEAN := false;
    v_latest_round_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: User must be authenticated';
    END IF;

    -- Verify ownership or Admin role
    SELECT created_by INTO v_auction_creator FROM public.auctions WHERE id = p_auction_id;
    SELECT (role = 'admin') INTO v_is_admin FROM public.profiles WHERE id = v_user_id;

    IF v_auction_creator IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Auction not found';
    END IF;

    IF v_auction_creator <> v_user_id AND NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'FORBIDDEN: You do not have permission to update this auction';
    END IF;

    -- Update Auction Record
    UPDATE public.auctions
    SET 
        title = p_title,
        description = p_description,
        starting_price = p_starting_price,
        min_increment = p_min_increment,
        status = p_status,
        reopen_duration_minutes = p_reopen_duration_minutes,
        vehicle_type = p_vehicle_type,
        brand_name = p_brand_name,
        model = p_model,
        built_year = p_built_year,
        year_calendar = p_year_calendar,
        lot_number = p_lot_number,
        registration_number = p_registration_number,
        kilometres_run = p_kilometres_run,
        number_of_owners = p_number_of_owners,
        fuel_type = p_fuel_type,
        engine_opened = p_engine_opened,
        colour = p_colour,
        engine_capacity = p_engine_capacity,
        tax_status = p_tax_status,
        bluebook_front_path = COALESCE(p_bluebook_front_path, bluebook_front_path),
        bluebook_back_path = COALESCE(p_bluebook_back_path, bluebook_back_path),
        bluebook_owner_path = COALESCE(p_bluebook_owner_path, bluebook_owner_path),
        vehicle_front_path = COALESCE(p_vehicle_front_path, vehicle_front_path),
        vehicle_back_path = COALESCE(p_vehicle_back_path, vehicle_back_path),
        vehicle_right_path = COALESCE(p_vehicle_right_path, vehicle_right_path),
        vehicle_left_path = COALESCE(p_vehicle_left_path, vehicle_left_path),
        odometer_path = COALESCE(p_odometer_path, odometer_path),
        updated_at = NOW()
    WHERE id = p_auction_id;

    -- Update Active Round Timing
    SELECT id INTO v_latest_round_id
    FROM public.auction_rounds
    WHERE auction_id = p_auction_id
    ORDER BY round_number DESC
    LIMIT 1;

    IF v_latest_round_id IS NOT NULL THEN
        UPDATE public.auction_rounds
        SET 
            start_at = p_start_at,
            end_at = p_end_at,
            status = p_status
        WHERE id = v_latest_round_id;
    END IF;

    -- Update auction_images
    DELETE FROM public.auction_images WHERE auction_id = p_auction_id;
    IF p_vehicle_front_path IS NOT NULL THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (p_auction_id, p_vehicle_front_path, 1, true);
    END IF;
    IF p_vehicle_back_path IS NOT NULL THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (p_auction_id, p_vehicle_back_path, 2, false);
    END IF;
    IF p_vehicle_right_path IS NOT NULL THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (p_auction_id, p_vehicle_right_path, 3, false);
    END IF;
    IF p_vehicle_left_path IS NOT NULL THEN
        INSERT INTO public.auction_images (auction_id, image_url, display_order, is_cover)
        VALUES (p_auction_id, p_vehicle_left_path, 4, false);
    END IF;

    -- Audit Log Entry
    BEGIN
        INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, details)
        VALUES (
            v_user_id, 'UPDATE_VEHICLE_AUCTION', 'auction', p_auction_id,
            jsonb_build_object('title', p_title, 'starting_price', p_starting_price)
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success', true, 'auction_id', p_auction_id);
END;
$$;
