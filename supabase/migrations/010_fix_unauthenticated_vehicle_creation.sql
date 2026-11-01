-- Migration 010: Allow Vehicle Auction Creation RPC and Table Access for Demo/Unauthenticated Sessions

-- 1. UPDATE AUCTIONS RLS POLICIES
DROP POLICY IF EXISTS "Auctions select policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions insert policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions update policy" ON public.auctions;

CREATE POLICY "Auctions select policy" 
    ON public.auctions FOR SELECT 
    TO anon, authenticated, public 
    USING (true);

CREATE POLICY "Auctions insert policy" 
    ON public.auctions FOR INSERT 
    TO anon, authenticated, public 
    WITH CHECK (true);

CREATE POLICY "Auctions update policy" 
    ON public.auctions FOR UPDATE 
    TO anon, authenticated, public 
    USING (true)
    WITH CHECK (true);

-- 2. UPDATE RPC FUNCTION FOR VEHICLE AUCTION CREATION
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
    v_user_id UUID := COALESCE(auth.uid(), '11111111-1111-1111-1111-111111111111'::uuid);
    v_auction_id UUID;
    v_created_auction JSONB;
BEGIN
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

    -- Create Initial Round 1
    INSERT INTO public.auction_rounds (auction_id, round_number, start_at, end_at, status)
    VALUES (v_auction_id, 1, p_start_at, p_end_at, p_status);

    SELECT jsonb_build_object('auction_id', v_auction_id, 'status', 'created') INTO v_created_auction;
    RETURN v_created_auction;
END;
$$;
