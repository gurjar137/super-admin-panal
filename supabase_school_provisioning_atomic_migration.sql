-- ==============================================================================
-- SCHOOL PROVISIONING ATOMICITY & FINAL SECURITY HARDENING MIGRATION
-- Project: Super Admin OS
-- Description:
--   1. school_provisioning_attempts: Server-controlled tracking & locking table
--      - RLS enabled: ZERO client INSERT, UPDATE, or DELETE policies
--      - Explicit REVOKE of all write privileges from anon, authenticated, public
--      - Read-only SELECT policy strictly for active Super Admins/Owners
--   2. track_provisioning_attempt RPC:
--      - Server-controlled entry point for tracking newly created Auth accounts
--      - Validates caller is active Super Admin/Owner
--      - Validates target Auth UUID exists in auth.users
--      - Validates email matches p_admin_email exactly
--      - Validates target Auth user has NO profile in public.profiles
--      - Validates Auth user created_at >= (now() - interval '15 minutes')
--      - Prevents rebinding an existing attempt to a different Auth user
--   3. provision_school_atomic RPC:
--      - Defense-in-depth: enforces creation window <= 15 minutes
--      - Enforces zero existing profile on target Auth user
--      - Enforces exact email matching with auth.users
--      - Row-level locking on attempts table to serialize concurrent requests
--      - Atomically provisions all 5 operational database entities
--   4. cleanup_orphaned_provisioning_auth_user RPC:
--      - Strict ownership check: deletes only Auth user bound to the specific attempt
--      - Strict safety constraint: can NEVER delete an Auth user with a profile
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. PROVISIONING ATTEMPTS & IDEMPOTENCY TABLE (SERVER-CONTROLLED)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.school_provisioning_attempts (
    idempotency_key TEXT PRIMARY KEY,
    auth_user_id UUID NOT NULL,
    admin_email TEXT NOT NULL,
    school_id UUID REFERENCES public.schools(id) ON DELETE CASCADE,
    created_by UUID REFERENCES auth.users(id),
    status TEXT NOT NULL CHECK (status IN ('initiated', 'in_progress', 'completed', 'failed', 'cleaned_up')),
    result_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for performance & auditing
CREATE INDEX IF NOT EXISTS idx_school_provisioning_attempts_auth_user
ON public.school_provisioning_attempts(auth_user_id);

CREATE INDEX IF NOT EXISTS idx_school_provisioning_attempts_status
ON public.school_provisioning_attempts(status);

CREATE INDEX IF NOT EXISTS idx_school_provisioning_attempts_created
ON public.school_provisioning_attempts(created_at);

-- Row Level Security
ALTER TABLE public.school_provisioning_attempts ENABLE ROW LEVEL SECURITY;

-- CRITICAL SECURITY HARDENING:
-- Revoke ALL direct table permissions from anon, authenticated, and public.
-- Clients must NEVER be able to directly INSERT, UPDATE, or DELETE attempt records.
REVOKE ALL ON TABLE public.school_provisioning_attempts FROM anon, authenticated, public;

-- Grant strictly read-only (SELECT) permission to authenticated
GRANT SELECT ON TABLE public.school_provisioning_attempts TO authenticated;

-- Drop any previous broad policies
DROP POLICY IF EXISTS "Super Admins manage provisioning attempts" ON public.school_provisioning_attempts;
DROP POLICY IF EXISTS "Super Admins view provisioning attempts" ON public.school_provisioning_attempts;

-- Read-Only RLS Policy: Authenticated Super Admins can only SELECT attempt records
CREATE POLICY "Super Admins view provisioning attempts"
ON public.school_provisioning_attempts
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.auth_user_id = auth.uid()
        AND p.role IN ('super_admin', 'owner')
        AND p.status = 'active'
    )
);

-- ------------------------------------------------------------------------------
-- 2. TRACK PROVISIONING ATTEMPT RPC (BOUND TO IDEMPOTENCY KEY & NEW ACCOUNT CHECK)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.track_provisioning_attempt(
    p_idempotency_key TEXT,
    p_auth_user_id UUID,
    p_admin_email TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_role TEXT;
    v_caller_status TEXT;
    v_target_email TEXT;
    v_target_created_at TIMESTAMPTZ;
    v_norm_key TEXT;
    v_norm_email TEXT;
    v_existing_auth_id UUID;
    v_existing_status TEXT;
BEGIN
    -- 1. Authoritative caller authorization
    SELECT role, status INTO v_caller_role, v_caller_status
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an active Super Admin or Owner';
    END IF;

    v_norm_key := TRIM(COALESCE(p_idempotency_key, ''));
    v_norm_email := LOWER(TRIM(COALESCE(p_admin_email, '')));

    IF v_norm_key = '' THEN
        RAISE EXCEPTION 'Idempotency key is required';
    END IF;

    IF p_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Auth user ID is required';
    END IF;

    -- 2. Verify target auth user exists in auth.users
    SELECT email, created_at INTO v_target_email, v_target_created_at
    FROM auth.users
    WHERE id = p_auth_user_id;

    IF v_target_email IS NULL THEN
        RAISE EXCEPTION 'Target auth user % does not exist in auth.users', p_auth_user_id USING ERRCODE = '20001';
    END IF;

    -- 3. Verify target auth user email matches provisioning administrator email
    IF LOWER(TRIM(v_target_email)) != v_norm_email THEN
        RAISE EXCEPTION 'Target auth user email (%) does not match provisioning administrator email (%)',
            v_target_email, v_norm_email USING ERRCODE = '20002';
    END IF;

    -- 4. Verify target auth user does NOT already have an active/existing profile
    IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = p_auth_user_id) THEN
        RAISE EXCEPTION 'Target auth user % is already attached to an existing profile', p_auth_user_id USING ERRCODE = '20003';
    END IF;

    -- 5. Strict Server-Enforced Creation Window:
    -- Target account MUST have been created within the last 15 minutes.
    -- Older unprofiled accounts cannot be claimed or bound by track_provisioning_attempt.
    IF v_target_created_at < (now() - interval '15 minutes') THEN
        RAISE EXCEPTION 'Pre-existing auth account % created at % (older than 15 minutes) cannot be registered for school provisioning',
            p_auth_user_id, v_target_created_at USING ERRCODE = '20004';
    END IF;

    -- 6. Check existing attempt: cannot rebind an idempotency key to a different Auth user
    SELECT auth_user_id, status INTO v_existing_auth_id, v_existing_status
    FROM public.school_provisioning_attempts
    WHERE idempotency_key = v_norm_key;

    IF FOUND THEN
        IF v_existing_auth_id != p_auth_user_id THEN
            RAISE EXCEPTION 'Idempotency conflict: Key % is already bound to a different Auth user %',
                v_norm_key, v_existing_auth_id USING ERRCODE = '23505';
        END IF;
        IF v_existing_status = 'completed' THEN
            RAISE EXCEPTION 'Provisioning attempt % is already completed and cannot be re-tracked',
                v_norm_key USING ERRCODE = '20013';
        END IF;
    END IF;

    -- 7. Insert or update attempt tracking (binds idempotency_key -> auth_user_id -> admin_email -> created_by)
    INSERT INTO public.school_provisioning_attempts (
        idempotency_key,
        auth_user_id,
        admin_email,
        created_by,
        status,
        created_at,
        updated_at
    ) VALUES (
        v_norm_key,
        p_auth_user_id,
        v_norm_email,
        auth.uid(),
        'initiated',
        now(),
        now()
    )
    ON CONFLICT (idempotency_key) DO UPDATE
    SET updated_at = now()
    WHERE public.school_provisioning_attempts.status != 'completed';

    RETURN jsonb_build_object(
        'success', true,
        'idempotency_key', v_norm_key,
        'auth_user_id', p_auth_user_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.track_provisioning_attempt(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.track_provisioning_attempt(TEXT, UUID, TEXT) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. ATOMIC SCHOOL PROVISIONING PROCEDURE (HARDENED DEFENSE-IN-DEPTH)
-- ------------------------------------------------------------------------------
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
        -- Lock or insert attempt row atomically
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

        -- Handle completed replay
        IF v_attempt_status = 'completed' AND v_attempt_payload IS NOT NULL THEN
            -- Idempotent replay: return identical result payload with replay flag
            RETURN jsonb_set(v_attempt_payload, '{idempotent_replay}', 'true'::jsonb);
        END IF;

        -- Verify that idempotency key was not registered to a different auth user
        IF v_attempt_auth_id IS NOT NULL AND v_attempt_auth_id != p_admin_auth_user_id THEN
            RAISE EXCEPTION 'Idempotency conflict: Key % is already assigned to a different Auth user',
                v_norm_idemp_key USING ERRCODE = '23505';
        END IF;

        -- Update status to in_progress
        UPDATE public.school_provisioning_attempts
        SET status = 'in_progress', updated_at = now()
        WHERE idempotency_key = v_norm_idemp_key;
    END IF;

    -- 4. HARDENED VALIDATION OF p_admin_auth_user_id (DEFENSE IN DEPTH)
    IF p_admin_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Administrator Auth User ID is required';
    END IF;

    -- Query auth.users
    SELECT email, created_at INTO v_auth_email, v_auth_created_at
    FROM auth.users
    WHERE id = p_admin_auth_user_id;

    IF v_auth_email IS NULL THEN
        RAISE EXCEPTION 'Administrator account % does not exist in auth.users',
            p_admin_auth_user_id USING ERRCODE = '20001';
    END IF;

    -- Email matching
    IF v_norm_admin_email != '' AND LOWER(TRIM(v_auth_email)) != v_norm_admin_email THEN
        RAISE EXCEPTION 'Administrator auth user email (%) does not match requested email (%)',
            v_auth_email, v_norm_admin_email USING ERRCODE = '20002';
    END IF;

    -- Ensure auth user does NOT already have an attached profile
    IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = p_admin_auth_user_id) THEN
        RAISE EXCEPTION 'Administrator auth user % is already associated with an existing profile',
            p_admin_auth_user_id USING ERRCODE = '20003';
    END IF;

    -- Ensure pre-existing accounts older than 15 minutes cannot be silently attached
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

-- ------------------------------------------------------------------------------
-- 4. HARDENED COMPENSATING CLEANUP FOR ORPHANED AUTH USERS
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleanup_orphaned_provisioning_auth_user(
    p_idempotency_key TEXT,
    p_auth_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_role TEXT;
    v_caller_status TEXT;
    v_attempt_auth_id UUID;
    v_attempt_status TEXT;
BEGIN
    -- 1. Authoritative Super Admin check
    SELECT role, status INTO v_caller_role, v_caller_status
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an active Super Admin or Owner';
    END IF;

    -- 2. Verify tracking attempt exists and strictly owns this auth user
    SELECT auth_user_id, status INTO v_attempt_auth_id, v_attempt_status
    FROM public.school_provisioning_attempts
    WHERE idempotency_key = TRIM(p_idempotency_key);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid provisioning reference: No attempt found for idempotency key %', p_idempotency_key
            USING ERRCODE = '20011';
    END IF;

    IF v_attempt_auth_id != p_auth_user_id THEN
        RAISE EXCEPTION 'Ownership mismatch: Auth user % does not belong to provisioning attempt %',
            p_auth_user_id, p_idempotency_key USING ERRCODE = '20012';
    END IF;

    IF v_attempt_status = 'completed' THEN
        RAISE EXCEPTION 'Cannot cleanup auth user of a successfully completed school provisioning'
            USING ERRCODE = '20013';
    END IF;

    -- 3. Strict Safety Constraint: CANNOT delete auth user that has an associated profile
    IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = p_auth_user_id) THEN
        RAISE EXCEPTION 'Safety check failed: Auth user % has an associated profile and cannot be cleaned up',
            p_auth_user_id USING ERRCODE = '20014';
    END IF;

    -- 4. Delete the verified orphaned auth user
    DELETE FROM auth.users WHERE id = p_auth_user_id;

    -- 5. Mark attempt as cleaned up
    UPDATE public.school_provisioning_attempts
    SET status = 'cleaned_up', updated_at = now()
    WHERE idempotency_key = TRIM(p_idempotency_key);

    RETURN true;
END;
$$;

-- Overload for backwards compatibility: enforces server-side attempt ownership lookup
CREATE OR REPLACE FUNCTION public.cleanup_orphaned_provisioning_auth_user(
    p_auth_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_idempotency_key TEXT;
BEGIN
    SELECT idempotency_key INTO v_idempotency_key
    FROM public.school_provisioning_attempts
    WHERE auth_user_id = p_auth_user_id
    AND status IN ('initiated', 'in_progress', 'failed')
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_idempotency_key IS NULL THEN
        RAISE EXCEPTION 'Cleanup rejected: Auth user % is not tracked by any active/pending provisioning attempt',
            p_auth_user_id USING ERRCODE = '20012';
    END IF;

    RETURN public.cleanup_orphaned_provisioning_auth_user(v_idempotency_key, p_auth_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.cleanup_orphaned_provisioning_auth_user(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_orphaned_provisioning_auth_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_orphaned_provisioning_auth_user(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_orphaned_provisioning_auth_user(UUID) TO authenticated;

-- ------------------------------------------------------------------------------
-- 5. ACADEMIC YEARS RLS HARDENING FOR SUPER ADMIN OS
-- ------------------------------------------------------------------------------
-- Ensure Super Admins and Owners can view, insert, update, and manage academic years across any school
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

