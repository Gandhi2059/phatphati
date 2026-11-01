-- Migration 023: Dynamically Drop ALL existing SELECT policies on public.profiles and recreate strict RLS policy

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
END;
$$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Create single non-permissive policy for profiles
CREATE POLICY "profiles_strict_select_policy" ON public.profiles
FOR SELECT
USING (
    (auth.uid() IS NOT NULL AND id = auth.uid()) 
    OR public.is_admin(auth.uid())
);
