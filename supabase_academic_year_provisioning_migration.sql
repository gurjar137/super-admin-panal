-- ==============================================================================
-- RECONCILIATION & ACADEMIC YEAR ONBOARDING MIGRATION
-- Project: Super Admin OS
-- Description:
--   1. Ensures Super Admins / Owners have complete management access to public.academic_years.
--   2. Updates provision_school_atomic to onboard an initial academic year for all new schools.
--   3. Safely backfills an active 2026-2027 academic year for MKC school (4813e425-1eb8-46df-a7d9-2efa208c7a7a)
--      verifying that the school record exists.
-- ==============================================================================

-- 1. Academic Years RLS Policy for Super Admins / Owners
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'academic_years' 
        AND policyname = 'Super Admins manage academic years'
    ) THEN
        CREATE POLICY "Super Admins manage academic years"
        ON public.academic_years
        FOR ALL
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM public.profiles p
                WHERE p.auth_user_id = auth.uid()
                AND p.role IN ('super_admin', 'owner')
                AND p.status = 'active'
            )
        )
        WITH CHECK (
            EXISTS (
                SELECT 1 FROM public.profiles p
                WHERE p.auth_user_id = auth.uid()
                AND p.role IN ('super_admin', 'owner')
                AND p.status = 'active'
            )
        );
    END IF;
END $$;

-- 2. Update provision_school_atomic with Academic Year Onboarding
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
    p_academic_year_name TEXT DEFAULT '2026-2027',
    p_ay_start_date DATE DEFAULT '2026-04-01'::date,
    p_ay_end_date DATE DEFAULT '2027-03-31'::date,
    p_ay_status TEXT DEFAULT 'active',
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
    v_ay_id UUID;
    v_profile_id UUID;
    v_norm_code TEXT;
    v_norm_pkg TEXT;
    v_norm_app_id TEXT;
    v_norm_admin_email TEXT;
    v_norm_idemp_key TEXT;
    v_auth_email TEXT;
    v_auth_created_at TIMESTAMPTZ;
    v_attempt_status TEXT;
    v_attempt_school_id UUID;
    v_attempt_payload JSONB;
    v_attempt_auth_id UUID;
    v_result JSONB;
BEGIN
    -- 1. Authoritative caller verification from server-side public.profiles
    SELECT role, status INTO v_caller_role, v_caller_status
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an active Super Admin or Owner';
    END IF;

    -- 2. Input Normalization
    v_norm_code := UPPER(TRIM(p_school_code));
    IF v_norm_code = '' OR LENGTH(v_norm_code) < 3 THEN
        RAISE EXCEPTION 'Invalid school code: must be at least 3 characters';
    END IF;

    v_norm_pkg := LOWER(TRIM(p_package_name));
    v_norm_app_id := UPPER(TRIM(p_app_identifier));
    v_norm_admin_email := LOWER(TRIM(COALESCE(p_admin_email, '')));
    v_norm_idemp_key := NULLIF(TRIM(COALESCE(p_idempotency_key, '')), '');

    -- 3. Concurrency Lock & Idempotency Protection
    IF v_norm_idemp_key IS NOT NULL THEN
        INSERT INTO public.school_provisioning_attempts (
            idempotency_key,
            auth_user_id,
            admin_email,
            created_by,
            status,
            created_at,
            updated_at
        ) VALUES (
            v_norm_idemp_key,
            p_admin_auth_user_id,
            v_norm_admin_email,
            auth.uid(),
            'in_progress',
            now(),
            now()
        )
        ON CONFLICT (idempotency_key) DO UPDATE
        SET updated_at = now()
        RETURNING status, school_id, result_payload, auth_user_id
        INTO v_attempt_status, v_attempt_school_id, v_attempt_payload, v_attempt_auth_id;

        IF v_attempt_status = 'completed' AND v_attempt_payload IS NOT NULL THEN
            RETURN jsonb_set(v_attempt_payload, '{idempotent_replay}', 'true'::jsonb);
        END IF;

        IF v_attempt_auth_id IS NOT NULL AND v_attempt_auth_id != p_admin_auth_user_id THEN
            RAISE EXCEPTION 'Idempotency conflict: Key % is already assigned to a different Auth user',
                v_norm_idemp_key USING ERRCODE = '23505';
        END IF;

        UPDATE public.school_provisioning_attempts
        SET status = 'in_progress', updated_at = now()
        WHERE idempotency_key = v_norm_idemp_key;
    END IF;

    -- 4. Validation of p_admin_auth_user_id
    IF p_admin_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Administrator Auth User ID is required';
    END IF;

    SELECT email, created_at INTO v_auth_email, v_auth_created_at
    FROM auth.users
    WHERE id = p_admin_auth_user_id;

    IF v_auth_email IS NULL THEN
        RAISE EXCEPTION 'Administrator account % does not exist in auth.users',
            p_admin_auth_user_id USING ERRCODE = '20001';
    END IF;

    IF v_norm_admin_email != '' AND LOWER(TRIM(v_auth_email)) != v_norm_admin_email THEN
        RAISE EXCEPTION 'Administrator auth user email (%) does not match requested email (%)',
            v_auth_email, v_norm_admin_email USING ERRCODE = '20002';
    END IF;

    IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = p_admin_auth_user_id) THEN
        RAISE EXCEPTION 'Administrator auth user % is already associated with an existing profile',
            p_admin_auth_user_id USING ERRCODE = '20003';
    END IF;

    IF v_auth_created_at < (now() - interval '15 minutes') THEN
        RAISE EXCEPTION 'Pre-existing auth user % created at % (older than 15 minutes) cannot be attached to a new school',
            p_admin_auth_user_id, v_auth_created_at USING ERRCODE = '20004';
    END IF;

    -- 5. Pre-insert Uniqueness Checks
    IF EXISTS (SELECT 1 FROM public.schools WHERE UPPER(code) = v_norm_code) THEN
        RAISE EXCEPTION 'School code % is already in use', v_norm_code USING ERRCODE = '23505';
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

    -- 11. ATOMIC STEP 6: Insert Initial Academic Year Session
    INSERT INTO public.academic_years (
        school_id,
        name,
        start_date,
        end_date,
        status,
        created_at,
        updated_at
    ) VALUES (
        v_school_id,
        COALESCE(NULLIF(TRIM(p_academic_year_name), ''), '2026-2027'),
        COALESCE(p_ay_start_date, '2026-04-01'::date),
        COALESCE(p_ay_end_date, '2027-03-31'::date),
        LOWER(COALESCE(NULLIF(TRIM(p_ay_status), ''), 'active')),
        now(),
        now()
    ) RETURNING id INTO v_ay_id;

    -- 12. Build Result Payload
    v_result := jsonb_build_object(
        'success', true,
        'school_id', v_school_id,
        'app_id', v_app_id,
        'school_app_id', v_app_id,
        'billing_settings_id', v_billing_id,
        'subscription_id', v_sub_id,
        'profile_id', v_profile_id,
        'academic_year_id', v_ay_id,
        'auth_user_id', p_admin_auth_user_id,
        'idempotent_replay', false
    );

    -- 13. Update Idempotency Tracking to Completed
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

-- 3. Safe Backfill for MKC School (4813e425-1eb8-46df-a7d9-2efa208c7a7a)
-- Only inserts if the school record exists and no academic year already exists for it
INSERT INTO public.academic_years (
    school_id,
    name,
    start_date,
    end_date,
    status,
    created_at,
    updated_at
)
SELECT 
    s.id,
    '2026-2027',
    '2026-04-01'::date,
    '2027-03-31'::date,
    'active',
    now(),
    now()
FROM public.schools s
WHERE s.id = '4813e425-1eb8-46df-a7d9-2efa208c7a7a'
AND NOT EXISTS (
    SELECT 1 FROM public.academic_years ay
    WHERE ay.school_id = '4813e425-1eb8-46df-a7d9-2efa208c7a7a'
);
