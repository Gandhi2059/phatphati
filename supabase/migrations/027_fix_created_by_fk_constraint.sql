-- Migration 027: Fix auctions_created_by_fkey Constraint & Auto Profile Sync

-- 1. Drop rigid foreign key constraint on auctions.created_by that blocks auction creation
ALTER TABLE public.auctions DROP CONSTRAINT IF EXISTS auctions_created_by_fkey;

-- 2. Ensure created_by is a UUID column without rigid FK block
-- This allows any logged-in user, seller, admin, or demo user to create auctions seamlessly
ALTER TABLE public.auctions ALTER COLUMN created_by DROP NOT NULL;

-- 3. Create or replace trigger to auto-create profile for any auth user or seller
CREATE OR REPLACE FUNCTION public.sync_profile_on_auth()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.email, 'user@phatphati.com'),
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'PhatPhati User'),
        COALESCE(NEW.raw_user_meta_data->>'role', 'buyer')
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_profile_on_auth ON auth.users;
CREATE TRIGGER trg_sync_profile_on_auth
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.sync_profile_on_auth();

-- 4. Backfill any missing profiles from auth.users
INSERT INTO public.profiles (id, email, full_name, role)
SELECT 
    id, 
    COALESCE(email, 'user@phatphati.com'), 
    COALESCE(raw_user_meta_data->>'full_name', 'PhatPhati User'),
    COALESCE(raw_user_meta_data->>'role', 'buyer')
FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- 5. Backfill demo profiles
INSERT INTO public.profiles (id, email, full_name, role)
VALUES 
    ('11111111-1111-1111-1111-111111111111', 'admin@autobid.com', 'Auction Admin', 'admin'),
    ('e5f6a7b8-c9d0-1234-5678-9abcdef01234', 'seller@autobid.com', 'Sam Seller / Auto Dealer', 'seller'),
    ('22222222-2222-2222-2222-222222222222', 'alice@buyer.com', 'Alice Smith', 'buyer')
ON CONFLICT (id) DO NOTHING;
