-- Migration 041: Add admin_delete_business_profile RPC
-- Allows administrators to permanently delete business registrations and reset applicant business status

CREATE OR REPLACE FUNCTION public.admin_delete_business_profile(p_business_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_owner_user_id UUID;
    v_company_name TEXT;
BEGIN
    SELECT owner_user_id, company_name INTO v_owner_user_id, v_company_name
    FROM public.business_profiles
    WHERE id = p_business_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Business profile not found');
    END IF;

    -- Delete review logs
    DELETE FROM public.business_review_logs WHERE business_id = p_business_id;

    -- Delete business profile
    DELETE FROM public.business_profiles WHERE id = p_business_id;

    -- Reset user profile business status
    IF v_owner_user_id IS NOT NULL THEN
        UPDATE public.profiles
        SET business_status = 'none',
            account_category = 'individual'
        WHERE id = v_owner_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'deleted_business_id', p_business_id,
        'owner_user_id', v_owner_user_id,
        'company_name', v_company_name
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_business_profile TO anon, authenticated, service_role, public;
