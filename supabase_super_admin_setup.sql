-- ==============================================================================
-- SUPER ADMIN BACKEND SETUP & MULTI-TENANT AUTHORIZATION POLICIES
-- Project: School Management OS
-- ==============================================================================

-- 1. Ensure `super_admin` role is permissible in public.profiles table
DO $$ 
BEGIN
    ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check 
        CHECK (role IN ('owner', 'super_admin', 'school_admin', 'staff', 'teacher', 'parent'));
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- 2. Super Admin RLS Policies for public.schools
-- Allows users with role = 'super_admin' or 'owner' in profiles to view and manage all schools
ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super Admins full access to schools" ON public.schools;
CREATE POLICY "Super Admins full access to schools"
ON public.schools
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

-- 3. Super Admin RLS Policies for public.profiles
-- Allows Super Admins to view all profiles across all tenants
DROP POLICY IF EXISTS "Super Admins view all profiles" ON public.profiles;
CREATE POLICY "Super Admins view all profiles"
ON public.profiles
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

-- 4. Atomic School Provisioning RPC (must be run in Supabase SQL Editor)
-- NOTE: This RPC has NOT been deployed yet. Run this SQL manually in Supabase Dashboard.
-- Only verified columns used: name, code, email, phone, address, logo_url, status
CREATE OR REPLACE FUNCTION public.provision_school_tenant(
    p_name TEXT,
    p_code TEXT,
    p_email TEXT,
    p_phone TEXT,
    p_address TEXT,
    p_logo_url TEXT,
    p_admin_name TEXT,
    p_admin_email TEXT,
    p_admin_phone TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_role TEXT;
    v_school_id UUID;
    v_school_code TEXT;
    v_result JSONB;
BEGIN
    -- Check caller is super admin
    SELECT role INTO v_caller_role FROM public.profiles WHERE auth_user_id = auth.uid() LIMIT 1;
    IF v_caller_role NOT IN ('super_admin', 'owner') THEN
        RAISE EXCEPTION 'Access Denied: Super Admin privileges required.';
    END IF;

    v_school_code := UPPER(TRIM(p_code));

    -- Check unique code
    IF EXISTS (SELECT 1 FROM public.schools WHERE UPPER(code) = v_school_code) THEN
        RAISE EXCEPTION 'School code % is already registered.', v_school_code;
    END IF;

    -- Insert school using only verified columns
    INSERT INTO public.schools (
        name,
        code,
        email,
        phone,
        address,
        logo_url,
        status
    )
    VALUES (
        TRIM(p_name),
        v_school_code,
        TRIM(p_email),
        TRIM(p_phone),
        TRIM(p_address),
        p_logo_url,
        'ACTIVE'
    )
    RETURNING id INTO v_school_id;

    -- Return JSON summary
    SELECT json_build_object(
        'success', true,
        'school_id', v_school_id,
        'school_code', v_school_code,
        'name', p_name
    )::JSONB INTO v_result;

    RETURN v_result;
END;
$$;
