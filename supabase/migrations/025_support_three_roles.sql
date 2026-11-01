-- Migration 025: Support Three Distinct Roles (Admin, Seller, Buyer)

-- 1. Drop existing role constraint and add new check constraint
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('admin', 'seller', 'buyer'));

-- 2. Helper function to check seller or admin role without policy recursion
CREATE OR REPLACE FUNCTION public.is_seller_or_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT COALESCE((SELECT role IN ('seller', 'admin') FROM public.profiles WHERE id = p_user_id), false);
$$;

-- 3. Update Auctions RLS Policies to allow Sellers & Admins to create and manage their own auctions
DROP POLICY IF EXISTS "Auctions select policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions insert policy" ON public.auctions;
DROP POLICY IF EXISTS "Auctions update policy" ON public.auctions;
DROP POLICY IF EXISTS "Admins can insert or update auctions" ON public.auctions;

CREATE POLICY "Auctions select policy" 
    ON public.auctions FOR SELECT 
    TO authenticated 
    USING (true);

CREATE POLICY "Auctions insert policy" 
    ON public.auctions FOR INSERT 
    TO authenticated 
    WITH CHECK (
        auth.uid() IS NOT NULL AND 
        created_by = auth.uid() AND 
        public.is_seller_or_admin(auth.uid())
    );

CREATE POLICY "Auctions update policy" 
    ON public.auctions FOR UPDATE 
    TO authenticated 
    USING (
        created_by = auth.uid() OR public.is_admin(auth.uid())
    );

-- 4. Update Vehicles RLS Policies to allow Sellers & Admins to create vehicles
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'vehicles') THEN
        EXECUTE 'DROP POLICY IF EXISTS "Vehicles insert policy" ON public.vehicles';
        EXECUTE 'DROP POLICY IF EXISTS "Vehicles update policy" ON public.vehicles';

        EXECUTE 'CREATE POLICY "Vehicles insert policy" ON public.vehicles FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL AND public.is_seller_or_admin(auth.uid()))';
        EXECUTE 'CREATE POLICY "Vehicles update policy" ON public.vehicles FOR UPDATE TO authenticated USING (public.is_seller_or_admin(auth.uid()))';
    END IF;
END $$;

-- 5. Seed Test Seller Profile if not already existing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES (
    'e5f6a7b8-c9d0-1234-5678-9abcdef01234',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'seller@autobid.com',
    extensions.crypt('seller123', extensions.gen_salt('bf')),
    NOW(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Sam Seller / Auto Dealer","role":"seller"}',
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role)
VALUES (
    'e5f6a7b8-c9d0-1234-5678-9abcdef01234',
    'seller@autobid.com',
    'Sam Seller / Auto Dealer',
    'seller'
) ON CONFLICT (id) DO UPDATE SET role = 'seller';
