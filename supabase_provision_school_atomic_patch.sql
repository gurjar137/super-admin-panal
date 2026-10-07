-- ==============================================================================
-- SUPER ADMIN P1 #3 — TARGETED ATOMIC PROVISIONING FUNCTION UPDATE
-- Resolves: 
-- 1. Pre-existing trigger on public.schools auto-creating school_billing_settings
-- 2. Uppercase check constraint compliance for apps and subscriptions status
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.provision_school_atomic(
    p_school_name TEXT,
    p_school_code TEXT,
    p_school_address TEXT DEFAULT NULL,
    p_school_phone TEXT DEFAULT NULL,
    p_school_email TEXT DEFAULT NULL,
    p_school_logo_url TEXT DEFAULT NULL,
    p_school_status TEXT DEFAULT 'ACTIVE',
    p_app_name TEXT DEFAULT NULL,
    p_package_name TEXT DEFAULT NULL,
    p_app_identifier TEXT DEFAULT NULL,
    p_app_version TEXT DEFAULT '1.0.0',
    p_play_store_url TEXT DEFAULT NULL,
    p_app_status TEXT DEFAULT 'ACTIVE',
    p_admin_auth_user_id UUID DEFAULT NULL,
    p_admin_name TEXT DEFAULT NULL,
    p_admin_email TEXT DEFAULT NULL,
    p_admin_phone TEXT DEFAULT NULL,
    p_plan_name TEXT DEFAULT 'Annual School License',
    p_start_date TIMESTAMPTZ DEFAULT now(),
    p_end_date TIMESTAMPTZ DEFAULT (now() + interval '365 days'),
    p_sub_status TEXT DEFAULT 'ACTIVE',
    p_sub_notes TEXT DEFAULT NULL,
    p_billing_rate NUMERIC DEFAULT 20.00,
    p_billing_currency TEXT DEFAULT 'INR',
    p_billing_cycle TEXT DEFAULT 'MONTHLY',
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_role TEXT;
    v_caller_status TEXT;
    v_school_id UUID;
    v_app_id UUID;
    v_billing_id UUID;
    v_sub_id UUID;
    v_profile_id UUID;
    v_norm_code TEXT;
    v_norm_pkg TEXT;
    v_norm_app_id TEXT;
    v_norm_admin_email TEXT;
    v_auth_email TEXT;
    v_norm_idemp_key TEXT;
    v_result JSONB;
    v_existing_payload JSONB;
    v_attempt_auth_id UUID;
BEGIN
    -- 1. Authoritative Super Admin check
    SELECT role, status INTO v_caller_role, v_caller_status
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an active Super Admin or Owner';
    END IF;

    -- 2. Input Validation & Normalization
    v_norm_code := UPPER(TRIM(p_school_code));
    v_norm_pkg := NULLIF(LOWER(TRIM(p_package_name)), '');
    v_norm_app_id := NULLIF(UPPER(TRIM(p_app_identifier)), '');
    v_norm_admin_email := LOWER(TRIM(p_admin_email));
    v_norm_idemp_key := NULLIF(TRIM(p_idempotency_key), '');

    IF TRIM(p_school_name) IS NULL OR TRIM(p_school_name) = '' THEN
        RAISE EXCEPTION 'School name is required';
    END IF;

    IF v_norm_code IS NULL OR v_norm_code = '' THEN
        RAISE EXCEPTION 'School code is required';
    END IF;

    IF p_admin_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Administrator auth_user_id is required';
    END IF;

    -- 3. Idempotency Check
    IF v_norm_idemp_key IS NOT NULL THEN
        SELECT result_payload, auth_user_id INTO v_existing_payload, v_attempt_auth_id
        FROM public.school_provisioning_attempts
        WHERE idempotency_key = v_norm_idemp_key;

        IF v_existing_payload IS NOT NULL THEN
            RETURN jsonb_set(v_existing_payload, '{idempotent_replay}', 'true'::jsonb);
        END IF;

        IF v_attempt_auth_id IS NOT NULL AND v_attempt_auth_id != p_admin_auth_user_id THEN
            RAISE EXCEPTION 'Ownership mismatch: Idempotency key % belongs to auth user % but called with %',
                v_norm_idemp_key, v_attempt_auth_id, p_admin_auth_user_id USING ERRCODE = '20005';
        END IF;
    END IF;

    -- 4. Server-Side Auth Defense-In-Depth Verification
    SELECT email INTO v_auth_email
    FROM auth.users
    WHERE id = p_admin_auth_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target auth user % does not exist in auth.users', p_admin_auth_user_id USING ERRCODE = '20001';
    END IF;

    IF v_norm_admin_email != '' AND LOWER(v_auth_email) != v_norm_admin_email THEN
        RAISE EXCEPTION 'Target auth user email (%) does not match provisioning administrator email (%)',
            v_auth_email, p_admin_email USING ERRCODE = '20002';
    END IF;

    -- If not replaying an already-tracked attempt, verify account has no existing profile
    IF v_attempt_auth_id IS NULL OR v_attempt_auth_id != p_admin_auth_user_id THEN
        IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = p_admin_auth_user_id) THEN
            RAISE EXCEPTION 'Target auth user % is already attached to an existing profile', p_admin_auth_user_id USING ERRCODE = '20003';
        END IF;
    END IF;

    -- 5. Uniqueness Pre-Flight Checks
    IF EXISTS (SELECT 1 FROM public.schools WHERE UPPER(code) = v_norm_code) THEN
        RAISE EXCEPTION 'School code % already exists', v_norm_code USING ERRCODE = '23505';
    END IF;

    IF v_norm_pkg IS NOT NULL AND v_norm_pkg != '' AND EXISTS (SELECT 1 FROM public.school_management_apps WHERE LOWER(package_name) = v_norm_pkg) THEN
        RAISE EXCEPTION 'Package name % is already registered', v_norm_pkg USING ERRCODE = '23505';
    END IF;

    IF v_norm_app_id IS NOT NULL AND v_norm_app_id != '' AND EXISTS (SELECT 1 FROM public.school_management_apps WHERE UPPER(app_identifier) = v_norm_app_id) THEN
        RAISE EXCEPTION 'App identifier % is already registered', v_norm_app_id USING ERRCODE = '23505';
    END IF;

    IF v_norm_admin_email != '' AND EXISTS (SELECT 1 FROM public.profiles WHERE LOWER(email) = v_norm_admin_email) THEN
        RAISE EXCEPTION 'Administrator email % is already registered in profiles', p_admin_email USING ERRCODE = '23505';
    END IF;

    -- 6. ATOMIC STEP 1: Insert School
    INSERT INTO public.schools (
        name,
        code,
        address,
        phone,
        email,
        logo_url,
        status,
        created_at,
        updated_at
    ) VALUES (
        TRIM(p_school_name),
        v_norm_code,
        NULLIF(TRIM(p_school_address), ''),
        NULLIF(TRIM(p_school_phone), ''),
        NULLIF(LOWER(TRIM(p_school_email)), ''),
        NULLIF(TRIM(p_school_logo_url), ''),
        UPPER(COALESCE(NULLIF(TRIM(p_school_status), ''), 'ACTIVE')),
        now(),
        now()
    ) RETURNING id INTO v_school_id;

    -- 7. ATOMIC STEP 2: Insert Dedicated App
    INSERT INTO public.school_management_apps (
        school_id,
        app_name,
        package_name,
        app_identifier,
        current_version,
        play_store_url,
        status,
        created_at,
        updated_at
    ) VALUES (
        v_school_id,
        COALESCE(NULLIF(TRIM(p_app_name), ''), TRIM(p_school_name) || ' App'),
        COALESCE(NULLIF(v_norm_pkg, ''), 'com.school.app.' || LOWER(REPLACE(v_norm_code, '-', '_'))),
        COALESCE(NULLIF(v_norm_app_id, ''), REPLACE(v_norm_code, '-', '_') || '_APP'),
        COALESCE(NULLIF(TRIM(p_app_version), ''), '1.0.0'),
        NULLIF(TRIM(p_play_store_url), ''),
        UPPER(COALESCE(NULLIF(TRIM(p_app_status), ''), 'ACTIVE')),
        now(),
        now()
    ) RETURNING id INTO v_app_id;

    -- 8. ATOMIC STEP 3: Insert or Update Default Billing Settings (₹20/student INR)
    -- Robustly handles database triggers on public.schools that automatically initialize billing settings
    INSERT INTO public.school_billing_settings (
        school_id,
        rate_per_student,
        currency,
        billing_cycle,
        active,
        created_at,
        updated_at
    ) VALUES (
        v_school_id,
        COALESCE(p_billing_rate, 20.00),
        COALESCE(NULLIF(TRIM(p_billing_currency), ''), 'INR'),
        COALESCE(NULLIF(TRIM(p_billing_cycle), ''), 'MONTHLY'),
        true,
        now(),
        now()
    )
    ON CONFLICT (school_id) DO UPDATE
    SET rate_per_student = EXCLUDED.rate_per_student,
        currency = EXCLUDED.currency,
        billing_cycle = EXCLUDED.billing_cycle,
        updated_at = now()
    RETURNING id INTO v_billing_id;

    -- 9. ATOMIC STEP 4: Insert School App Subscription
    INSERT INTO public.school_app_subscriptions (
        school_app_id,
        plan_name,
        start_date,
        end_date,
        status,
        notes,
        created_at,
        updated_at
    ) VALUES (
        v_app_id,
        COALESCE(NULLIF(TRIM(p_plan_name), ''), 'Annual School License'),
        COALESCE(p_start_date, now()),
        COALESCE(p_end_date, now() + interval '365 days'),
        UPPER(COALESCE(NULLIF(TRIM(p_sub_status), ''), 'ACTIVE')),
        NULLIF(TRIM(p_sub_notes), ''),
        now(),
        now()
    ) RETURNING id INTO v_sub_id;

    -- 10. ATOMIC STEP 5: Insert School Administrator Profile
    INSERT INTO public.profiles (
        auth_user_id,
        school_id,
        full_name,
        email,
        phone,
        role,
        status,
        designation,
        created_at,
        updated_at
    ) VALUES (
        p_admin_auth_user_id,
        v_school_id,
        COALESCE(NULLIF(TRIM(p_admin_name), ''), 'School Administrator'),
        v_auth_email,
        NULLIF(TRIM(p_admin_phone), ''),
        'school_admin',
        'active',
        'School Administrator',
        now(),
        now()
    ) RETURNING id INTO v_profile_id;

    -- 11. Build Result Payload
    v_result := jsonb_build_object(
        'success', true,
        'school_id', v_school_id,
        'app_id', v_app_id,
        'school_app_id', v_app_id,
        'billing_settings_id', v_billing_id,
        'subscription_id', v_sub_id,
        'profile_id', v_profile_id,
        'auth_user_id', p_admin_auth_user_id,
        'idempotent_replay', false
    );

    -- 12. Update Idempotency Tracking to Completed
    IF v_norm_idemp_key IS NOT NULL THEN
        UPDATE public.school_provisioning_attempts
        SET status = 'completed',
            school_id = v_school_id,
            result_payload = v_result,
            updated_at = now()
        WHERE idempotency_key = v_norm_idemp_key;
    END IF;

    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.provision_school_atomic FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.provision_school_atomic TO authenticated;
