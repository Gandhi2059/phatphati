-- Migration 042: Update admin_review_business to support moving to 'pending',
-- preserving admin review notes, and synchronizing public.profiles.business_status

CREATE OR REPLACE FUNCTION public.admin_review_business(
    p_business_id UUID,
    p_status TEXT,
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin_id UUID := auth.uid();
    v_old_status TEXT;
    v_owner_user_id UUID;
    v_business_type TEXT;
BEGIN
    SELECT status, owner_user_id, account_type
    INTO v_old_status, v_owner_user_id, v_business_type
    FROM public.business_profiles
    WHERE id = p_business_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Business profile not found');
    END IF;

    -- Update the business profile
    UPDATE public.business_profiles
    SET status = p_status,
        rejection_reason = CASE
            WHEN p_status IN ('rejected', 'pending') THEN COALESCE(p_rejection_reason, rejection_reason)
            WHEN p_status = 'approved' THEN NULL
            ELSE p_rejection_reason
        END,
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_business_id;

    -- Synchronize applicant user's profile
    IF v_owner_user_id IS NOT NULL THEN
        UPDATE public.profiles
        SET business_status = p_status,
            account_category = CASE
                WHEN p_status = 'approved' THEN 'business'
                WHEN p_status = 'pending' THEN 'individual'
                WHEN p_status = 'rejected' THEN 'individual'
                ELSE account_category
            END,
            updated_at = NOW()
        WHERE id = v_owner_user_id;
    END IF;

    -- Log review action
    INSERT INTO public.business_review_logs (business_id, old_status, new_status, rejection_reason, reviewed_by)
    VALUES (p_business_id, v_old_status, p_status, p_rejection_reason, v_admin_id);

    RETURN jsonb_build_object(
        'success', true,
        'business_id', p_business_id,
        'old_status', v_old_status,
        'new_status', p_status,
        'rejection_reason', p_rejection_reason,
        'owner_user_id', v_owner_user_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_review_business TO anon, authenticated, service_role, public;
