-- ==============================================================================
-- CONSOLIDATED SCHOOL PROVISIONING, ACADEMIC YEAR & RLS DEPLOYMENT
-- Project: Central Shared School SaaS / Super Admin Panel
-- Target Supabase Project: hnvjenkeimzkdgkuwbeb
-- Target Database: PostgreSQL 15+ Backend
-- Authoritative Master Deployment File
-- ==============================================================================
-- ==============================================================================
-- Summary of Operations:
--   1. Ensures server-controlled school_provisioning_attempts table and RPCs exist.
--   2. Strict Platform-Admin vs School-Owner Security on public.academic_years:
--      - Platform Administrators (role IN ('super_admin', 'platform_admin', 'owner'))
--        can view and manage academic years across all schools.
--      - Ordinary School Owners (school_owner), School Admins, and Principals are
--        STRICTLY confined to their own school (school_id = public.get_user_school_id()).
--      - RLS WITH CHECK ensures academic years cannot be inserted into or moved to another school.
--      - Unauthenticated users receive zero access.
--   3. Universal provision_school_atomic Procedure (Canonical 30-Parameter Contract):
--      - Creates School, Dedicated App, Billing Settings, Subscription,
--        Administrator Profile, and Initial Academic Year in a single atomic transaction.
--      - Replaces legacy 26-parameter and conflicting overloads safely.
--      - Reuses one database-generated canonical UUID (v_school_id) across all 6 architectural components.
--      - Returns canonical identifiers: school_id, app_id, profile_id, subscription_id, billing_settings_id, academic_year_id.
--      - ZERO credentials, passwords, or secrets returned in result JSON, application logs, or audit records.
--   4. Universal Existing School Remediation RPC (onboard_academic_year_for_school):
--      - Allows authorized administrators to onboard or remediate an academic year
--        for any existing school (such as MKC, school 1, KVS, Greenwood) without code patches.
--   5. Safe, Idempotent Backfill for MKC School (4813e425-1eb8-46df-a7d9-2efa208c7a7a):
--      - Validates that MKC school exists before insertion.
--      - Validates that no equivalent '2026-2027' academic year already exists.
--      - Preserves existing rows if present and never overwrites data.
--   6. Automated Post-Deployment Verification Queries.
-- ==============================================================================

BEGIN;

-- ==============================================================================
-- SECTION 1: PROVISIONING ATTEMPTS & IDEMPOTENCY TRACKING
-- ==============================================================================

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

-- Row Level Security for attempts table
ALTER TABLE public.school_provisioning_attempts ENABLE ROW LEVEL SECURITY;

-- Revoke write privileges from client roles
REVOKE ALL ON TABLE public.school_provisioning_attempts FROM anon, authenticated, public;
GRANT SELECT ON TABLE public.school_provisioning_attempts TO authenticated;

-- Platform Super Admin read-only policy
DROP POLICY IF EXISTS "Super Admins view provisioning attempts" ON public.school_provisioning_attempts;
DROP POLICY IF EXISTS "Platform Admins view provisioning attempts" ON public.school_provisioning_attempts;
CREATE POLICY "Platform Admins view provisioning attempts"
ON public.school_provisioning_attempts
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.auth_user_id = auth.uid()
        AND p.role IN ('super_admin', 'platform_admin', 'owner')
        AND p.status = 'active'
    )
);

-- ==============================================================================
-- SECTION 2: TRACK & CLEANUP RPCs
-- ==============================================================================

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
    -- 1. Authoritative caller authorization: platform-level administrative roles only
    SELECT role, status INTO v_caller_role, v_caller_status
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'platform_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an active Platform Administrator';
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

    -- 4. Verify target auth user does NOT already have an active profile
    IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = p_auth_user_id) THEN
        RAISE EXCEPTION 'Target auth user % is already attached to an existing profile', p_auth_user_id USING ERRCODE = '20003';
    END IF;

    -- 5. Strict Server-Enforced Creation Window (15 minutes)
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

    -- 7. Insert or update attempt tracking
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

-- Cleanup procedure for orphaned Auth users
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
    SELECT role, status INTO v_caller_role, v_caller_status
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'platform_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an active Platform Administrator';
    END IF;

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

    IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = p_auth_user_id) THEN
        RAISE EXCEPTION 'Safety check failed: Auth user % has an associated profile and cannot be cleaned up',
            p_auth_user_id USING ERRCODE = '20014';
    END IF;

    DELETE FROM auth.users WHERE id = p_auth_user_id;

    UPDATE public.school_provisioning_attempts
    SET status = 'cleaned_up', updated_at = now()
    WHERE idempotency_key = TRIM(p_idempotency_key);

    RETURN true;
END;
$$;

-- Overload for backwards compatibility
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

-- ==============================================================================
-- SECTION 3: ROW LEVEL SECURITY HARDENING ON public.academic_years
-- ==============================================================================

-- 1. Ensure table has RLS enabled
ALTER TABLE public.academic_years ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing policies to prevent conflicts or permissive cross-school leakage
DROP POLICY IF EXISTS "Super Admins manage academic years" ON public.academic_years;
DROP POLICY IF EXISTS "academic_years_tenant_read" ON public.academic_years;
DROP POLICY IF EXISTS "academic_years_tenant_write" ON public.academic_years;
DROP POLICY IF EXISTS "Users view their school academic years" ON public.academic_years;
DROP POLICY IF EXISTS "School admins manage academic years" ON public.academic_years;
DROP POLICY IF EXISTS "School Admins and Owners manage academic years" ON public.academic_years;
DROP POLICY IF EXISTS "academic_years_tenant_select" ON public.academic_years;
DROP POLICY IF EXISTS "academic_years_tenant_manage" ON public.academic_years;

-- 3. Policy A: SCHOOL TENANT ISOLATION (READ)
-- Authenticated school staff, teachers, students, admins, and school owners can view ONLY their own school's academic years.
-- Platform Administrators (super_admin, platform_admin, owner) can view academic years across all schools.
-- Unauthenticated users receive zero access.
CREATE POLICY "academic_years_tenant_select"
ON public.academic_years
FOR SELECT
TO authenticated
USING (
    school_id = public.get_user_school_id()
    OR
    EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.auth_user_id = auth.uid()
        AND p.role IN ('super_admin', 'platform_admin', 'owner')
        AND p.status = 'active'
    )
);

-- 4. Policy B: STRICT TENANT-SCOPED MUTATION (INSERT, UPDATE, DELETE)
-- Ordinary school owners (role = 'school_owner'), School Admins, and Principals can manage academic years ONLY for their own school.
-- Platform Administrators can manage across all schools.
-- Strict WITH CHECK guarantees that no tenant can create or reassign an academic year to another school.
CREATE POLICY "academic_years_tenant_manage"
ON public.academic_years
FOR ALL
TO authenticated
USING (
    (
        school_id = public.get_user_school_id()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.auth_user_id = auth.uid()
            AND p.role IN ('school_admin', 'admin', 'principal', 'school_owner')
            AND p.status = 'active'
        )
    )
    OR
    EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.auth_user_id = auth.uid()
        AND p.role IN ('super_admin', 'platform_admin', 'owner')
        AND p.status = 'active'
    )
)
WITH CHECK (
    (
        school_id = public.get_user_school_id()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.auth_user_id = auth.uid()
            AND p.role IN ('school_admin', 'admin', 'principal', 'school_owner')
            AND p.status = 'active'
        )
    )
    OR
    EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.auth_user_id = auth.uid()
        AND p.role IN ('super_admin', 'platform_admin', 'owner')
        AND p.status = 'active'
    )
);

-- ==============================================================================
-- SECTION 4: CANONICAL ATOMIC SCHOOL PROVISIONING PROCEDURE (30 PARAMETERS)
-- ==============================================================================

-- Drop legacy 26-parameter overload to ensure single unambiguous canonical contract
DROP FUNCTION IF EXISTS public.provision_school_atomic(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ,
    TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT
);

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
    -- 1. Authoritative caller verification: platform-level administrative roles only
    SELECT role, status INTO v_caller_role, v_caller_status
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'platform_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an active Platform Administrator';
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

    -- 2.1 Academic Year Input Validation
    IF TRIM(COALESCE(p_academic_year_name, '')) = '' THEN
        RAISE EXCEPTION 'Academic Year name cannot be empty';
    END IF;
    IF p_ay_end_date < p_ay_start_date THEN
        RAISE EXCEPTION 'Academic Year end date (%) cannot be earlier than start date (%)',
            p_ay_end_date, p_ay_start_date;
    END IF;

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

    -- 6. ATOMIC STEP 1: Insert School (Canonical UUID Generated)
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

    -- 7. ATOMIC STEP 2: Insert Dedicated App (Linked to Canonical v_school_id)
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

    -- 8. ATOMIC STEP 3: Insert or Update Default Billing Settings (Linked to Canonical v_school_id)
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

    -- 9. ATOMIC STEP 4: Insert School App Subscription (Linked to Dedicated v_app_id)
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

    -- 10. ATOMIC STEP 5: Insert School Administrator Profile (Linked to Canonical v_school_id)
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

    -- 11. ATOMIC STEP 6: Insert Initial Academic Year Session (Linked to Canonical v_school_id)
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
        TRIM(p_academic_year_name),
        p_ay_start_date,
        p_ay_end_date,
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

REVOKE ALL ON FUNCTION public.provision_school_atomic(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ,
    TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, DATE, TEXT, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.provision_school_atomic(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ,
    TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, DATE, DATE, TEXT, TEXT
) TO authenticated;

-- ==============================================================================
-- SECTION 5: UNIVERSAL EXISTING-SCHOOL ACADEMIC-YEAR ONBOARDING RPC
-- ==============================================================================

-- General purpose function to onboard or remediate an academic year for any existing school
CREATE OR REPLACE FUNCTION public.onboard_academic_year_for_school(
    p_school_id UUID,
    p_academic_year_name TEXT,
    p_start_date DATE,
    p_end_date DATE,
    p_status TEXT DEFAULT 'active'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_role TEXT;
    v_caller_status TEXT;
    v_existing_id UUID;
    v_new_id UUID;
BEGIN
    -- 1. Authoritative caller verification
    SELECT role, status INTO v_caller_role, v_caller_status
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'platform_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        -- If not platform admin, verify caller is school admin, principal, or school owner of this exact school
        IF NOT (
            p_school_id = public.get_user_school_id()
            AND v_caller_role IN ('school_admin', 'admin', 'principal', 'school_owner')
            AND LOWER(v_caller_status) = 'active'
        ) THEN
            RAISE EXCEPTION 'Unauthorized: Caller cannot manage academic years for school %', p_school_id;
        END IF;
    END IF;

    -- 2. Verify school exists
    IF NOT EXISTS (SELECT 1 FROM public.schools WHERE id = p_school_id) THEN
        RAISE EXCEPTION 'School with ID % does not exist in public.schools', p_school_id USING ERRCODE = '20001';
    END IF;

    -- 3. Date validation
    IF p_end_date < p_start_date THEN
        RAISE EXCEPTION 'End date (%) cannot be earlier than start date (%)', p_end_date, p_start_date;
    END IF;

    -- 4. Check for duplicate session name in same school
    SELECT id INTO v_existing_id
    FROM public.academic_years
    WHERE school_id = p_school_id
    AND name = TRIM(p_academic_year_name);

    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'school_id', p_school_id,
            'academic_year_id', v_existing_id,
            'action', 'already_exists'
        );
    END IF;

    -- 5. Insert new academic year
    INSERT INTO public.academic_years (
        school_id,
        name,
        start_date,
        end_date,
        status,
        created_at,
        updated_at
    ) VALUES (
        p_school_id,
        TRIM(p_academic_year_name),
        p_start_date,
        p_end_date,
        LOWER(COALESCE(NULLIF(TRIM(p_status), ''), 'active')),
        now(),
        now()
    ) RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'success', true,
        'school_id', p_school_id,
        'academic_year_id', v_new_id,
        'action', 'created'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.onboard_academic_year_for_school(UUID, TEXT, DATE, DATE, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.onboard_academic_year_for_school(UUID, TEXT, DATE, DATE, TEXT) TO authenticated;

-- ==============================================================================
-- SECTION 6: SAFE, IDEMPOTENT BACKFILL FOR MKC SCHOOL
-- ==============================================================================

-- Safely backfills an active 2026-2027 academic year for MKC school
-- (UUID: 4813e425-1eb8-46df-a7d9-2efa208c7a7a) ONLY if:
--   1. The school record exists in public.schools
--   2. No academic year with name '2026-2027' exists for this school
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
    AND ay.name = '2026-2027'
);

COMMIT;

-- ==============================================================================
-- SECTION 7: AUTOMATED POST-DEPLOYMENT VERIFICATION SCRIPT
-- ==============================================================================
-- Run these read-only statements to verify deployment state:

-- 1. Check provision_school_atomic RPC function definition & arguments
SELECT routine_name, routine_type, security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'provision_school_atomic';

-- 2. Check onboard_academic_year_for_school RPC function definition
SELECT routine_name, routine_type, security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'onboard_academic_year_for_school';

-- 3. Check academic_years RLS is enabled and policies exist
SELECT policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
AND tablename = 'academic_years';

-- 4. Confirm MKC school record exists
SELECT id, name, code, status
FROM public.schools
WHERE id = '4813e425-1eb8-46df-a7d9-2efa208c7a7a';

-- 5. Confirm MKC active academic year exists after migration
SELECT id, school_id, name, start_date, end_date, status
FROM public.academic_years
WHERE school_id = '4813e425-1eb8-46df-a7d9-2efa208c7a7a';

-- 6. Confirm no permissive policies allow cross-tenant leak for ordinary school owners
SELECT policyname, qual
FROM pg_policies
WHERE schemaname = 'public'
AND tablename = 'academic_years'
AND qual LIKE '%true%';
