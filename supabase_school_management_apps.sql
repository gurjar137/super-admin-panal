-- ==============================================================================
-- DEDICATED SCHOOL MANAGEMENT APPS & SUPER ADMIN MIGRATION
-- Project: Super Admin OS
-- Description: Creates the school_management_apps table enforcing exactly
--              one dedicated School Management App record per school.
-- ==============================================================================

-- 1. Create school_management_apps table
CREATE TABLE IF NOT EXISTS public.school_management_apps (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id       UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    app_name        TEXT NOT NULL,
    app_identifier  TEXT,
    package_name    TEXT,
    current_version TEXT NOT NULL DEFAULT '1.0.0',
    play_store_url  TEXT,
    status          TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT one_app_per_school UNIQUE (school_id)
);

-- 2. Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_school_mgmt_apps_school_id ON public.school_management_apps(school_id);
CREATE INDEX IF NOT EXISTS idx_school_mgmt_apps_status ON public.school_management_apps(status);
CREATE INDEX IF NOT EXISTS idx_school_mgmt_apps_package ON public.school_management_apps(package_name);

-- 3. Enable RLS
ALTER TABLE public.school_management_apps ENABLE ROW LEVEL SECURITY;

-- 4. Super Admin RLS Policies for school_management_apps
DROP POLICY IF EXISTS "Super Admins full access to school_management_apps" ON public.school_management_apps;
CREATE POLICY "Super Admins full access to school_management_apps"
ON public.school_management_apps
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

-- 5. School Admin read-only access to their own school's app configuration
DROP POLICY IF EXISTS "School Users read own school_management_app" ON public.school_management_apps;
CREATE POLICY "School Users read own school_management_app"
ON public.school_management_apps
FOR SELECT
TO authenticated
USING (
    school_id = public.get_user_school_id()
);

-- 6. Trigger for updated_at timestamp
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS 
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
 LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_school_mgmt_apps_updated_at ON public.school_management_apps;
CREATE TRIGGER trg_school_mgmt_apps_updated_at
    BEFORE UPDATE ON public.school_management_apps
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();
