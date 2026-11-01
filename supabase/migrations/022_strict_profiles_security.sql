-- Migration 022: Ensure Row Level Security is Enabled on Profiles and Drop All Permissive Policies

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Drop all possible previous policies on profiles
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Public profiles select policy" ON public.profiles;
DROP POLICY IF EXISTS "Business profiles select policy" ON public.profiles;
DROP POLICY IF EXISTS "Strict Profiles Select Policy" ON public.profiles;
DROP POLICY IF EXISTS "Profiles select policy" ON public.profiles;

-- Strict select policy: A user can only view their own profile, or admins can view all profiles
CREATE POLICY "profiles_strict_select_policy" ON public.profiles
FOR SELECT
USING (
    id = auth.uid() OR public.is_admin(auth.uid())
);
