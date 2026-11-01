-- Migration 026: Automatic Profile Creation Trigger & FK Safety

-- 1. Function & Trigger to automatically insert a profile when a new auth user is created
CREATE OR REPLACE FUNCTION public.handle_new_user()
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. Backfill profiles for any auth.users missing from public.profiles
INSERT INTO public.profiles (id, email, full_name, role)
SELECT 
    u.id, 
    COALESCE(u.email, 'user@phatphati.com'), 
    COALESCE(u.raw_user_meta_data->>'full_name', 'PhatPhati User'),
    COALESCE(u.raw_user_meta_data->>'role', 'buyer')
FROM auth.users u
ON CONFLICT (id) DO NOTHING;

-- 3. Backfill default demo profiles
INSERT INTO public.profiles (id, email, full_name, role)
VALUES 
    ('11111111-1111-1111-1111-111111111111', 'admin@autobid.com', 'Auction Admin', 'admin'),
    ('e5f6a7b8-c9d0-1234-5678-9abcdef01234', 'seller@autobid.com', 'Sam Seller / Auto Dealer', 'seller'),
    ('22222222-2222-2222-2222-222222222222', 'alice@buyer.com', 'Alice Smith', 'buyer')
ON CONFLICT (id) DO NOTHING;
