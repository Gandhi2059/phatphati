-- Migration 040: Auto confirm email trigger and create_authenticated_user RPC
-- Eliminates "Email not confirmed" and ensures passwords work reliably in auth.users

-- 1. Auto-confirm all unconfirmed users in auth.users
UPDATE auth.users
SET email_confirmed_at = COALESCE(email_confirmed_at, NOW())
WHERE email_confirmed_at IS NULL;

-- 2. Trigger on auth.users to auto-confirm new registrations
CREATE OR REPLACE FUNCTION public.handle_auto_confirm_email()
RETURNS TRIGGER AS $$
BEGIN
    NEW.email_confirmed_at := COALESCE(NEW.email_confirmed_at, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_auto_confirm_email ON auth.users;
CREATE TRIGGER tr_auto_confirm_email
    BEFORE INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_auto_confirm_email();

-- 3. Atomic user registration RPC creating authenticated auth.users and public.profiles
CREATE OR REPLACE FUNCTION public.create_authenticated_user(
    p_email TEXT,
    p_password TEXT,
    p_full_name TEXT,
    p_phone TEXT,
    p_role TEXT,
    p_account_category TEXT,
    p_buyer_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_existing_id UUID;
    v_encrypted_pw TEXT;
    v_meta JSONB;
BEGIN
    SELECT id INTO v_existing_id FROM auth.users WHERE LOWER(email) = LOWER(p_email);
    v_encrypted_pw := crypt(p_password, gen_salt('bf'));

    IF v_existing_id IS NOT NULL THEN
        v_user_id := v_existing_id;
        UPDATE auth.users
        SET encrypted_password = v_encrypted_pw,
            email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
            raw_user_meta_data = jsonb_build_object(
                'sub', v_user_id::text,
                'email', LOWER(p_email),
                'full_name', p_full_name,
                'phone', p_phone,
                'role', p_role,
                'account_category', p_account_category,
                'buyer_id', p_buyer_id
            ),
            updated_at = NOW()
        WHERE id = v_user_id;

        INSERT INTO auth.identities (
            provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
        ) VALUES (
            v_user_id::text, v_user_id,
            jsonb_build_object('sub', v_user_id::text, 'email', LOWER(p_email), 'full_name', p_full_name, 'role', p_role),
            'email', NOW(), NOW(), NOW(), gen_random_uuid()
        )
        ON CONFLICT (provider_id, provider) DO UPDATE SET
            identity_data = EXCLUDED.identity_data,
            updated_at = NOW();
    ELSE
        v_user_id := gen_random_uuid();
        v_meta := jsonb_build_object(
            'sub', v_user_id::text,
            'email', LOWER(p_email),
            'full_name', p_full_name,
            'phone', p_phone,
            'role', p_role,
            'account_category', p_account_category,
            'buyer_id', p_buyer_id
        );

        INSERT INTO auth.users (
            id, instance_id, aud, role, email, encrypted_password,
            email_confirmed_at, recovery_token, confirmation_token,
            email_change_token_new, email_change, created_at, updated_at,
            raw_app_meta_data, raw_user_meta_data, is_super_admin
        ) VALUES (
            v_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            LOWER(p_email), v_encrypted_pw, NOW(), '', '', '', '', NOW(), NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb, v_meta, false
        );

        INSERT INTO auth.identities (
            provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
        ) VALUES (
            v_user_id::text, v_user_id,
            v_meta, 'email', NOW(), NOW(), NOW(), gen_random_uuid()
        )
        ON CONFLICT (provider_id, provider) DO UPDATE SET
            identity_data = EXCLUDED.identity_data,
            updated_at = NOW();
    END IF;

    -- Upsert public.profiles
    INSERT INTO public.profiles (
        id, buyer_id, email, full_name, phone, role, account_category, created_at
    ) VALUES (
        v_user_id, p_buyer_id, LOWER(p_email), p_full_name, p_phone, p_role, p_account_category, NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        phone = EXCLUDED.phone,
        role = EXCLUDED.role,
        account_category = EXCLUDED.account_category,
        buyer_id = COALESCE(EXCLUDED.buyer_id, public.profiles.buyer_id);

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_user_id,
        'email', LOWER(p_email),
        'role', p_role
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_authenticated_user TO anon, authenticated, service_role, public;
