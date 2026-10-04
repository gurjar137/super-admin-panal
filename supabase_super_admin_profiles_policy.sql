-- ==============================================================================
-- SUPER ADMIN PROFILES POLICY: ENABLE CROSS-SCHOOL ADMIN PROVISIONING
-- ==============================================================================
-- Purpose:
-- Allows Super Admins and Owners (with role IN ('super_admin', 'owner'))
-- to view, provision, and manage profiles for all schools in public.profiles.
--
-- Preserves strict tenant isolation for school-level users (teachers, staff,
-- school admins) who remain strictly scoped to their own school_id.
-- ==============================================================================

DROP POLICY IF EXISTS "Super Admins manage all profiles" ON public.profiles;
CREATE POLICY "Super Admins manage all profiles"
ON public.profiles
FOR ALL
TO authenticated
USING (
    public.get_user_role() IN ('super_admin', 'owner')
)
WITH CHECK (
    public.get_user_role() IN ('super_admin', 'owner')
);
