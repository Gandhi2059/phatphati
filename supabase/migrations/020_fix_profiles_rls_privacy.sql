-- Migration 020: Enforce Strict RLS on public.profiles to Prevent Direct API Table Privacy Leaks

-- 1. Helper function to check admin role without policy recursion
CREATE OR REPLACE FUNCTION public.is_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT COALESCE((SELECT role = 'admin' FROM public.profiles WHERE id = p_user_id), false);
$$;

-- 2. Drop old policies on profiles
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Strict Profiles Select Policy" ON public.profiles;

-- 3. Create non-recursive secure policy: Users see own profile, admins see all profiles, business category visible
CREATE POLICY "Strict Profiles Select Policy"
ON public.profiles
FOR SELECT
USING (
    id = auth.uid()
    OR public.is_admin(auth.uid())
    OR account_category = 'business'
);
