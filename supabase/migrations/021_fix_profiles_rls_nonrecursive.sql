-- Migration 021: Non-recursive RLS policy on public.profiles using is_admin helper

CREATE OR REPLACE FUNCTION public.is_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT COALESCE((SELECT role = 'admin' FROM public.profiles WHERE id = p_user_id), false);
$$;

DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Strict Profiles Select Policy" ON public.profiles;

CREATE POLICY "Strict Profiles Select Policy"
ON public.profiles
FOR SELECT
USING (
    id = auth.uid()
    OR public.is_admin(auth.uid())
    OR account_category = 'business'
);
