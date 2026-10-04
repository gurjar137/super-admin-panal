-- ==============================================================================
-- DEDICATED SCHOOL MANAGEMENT APP SUBSCRIPTIONS & ACCESS CONTROL MIGRATION
-- Project: Super Admin OS
-- Description: Creates the school_app_subscriptions table enforcing exactly
--              one subscription record per dedicated School Management App.
-- ==============================================================================

-- 1. Create school_app_subscriptions table
CREATE TABLE IF NOT EXISTS public.school_app_subscriptions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_app_id  UUID NOT NULL REFERENCES public.school_management_apps(id) ON DELETE CASCADE,
    plan_name      TEXT NOT NULL DEFAULT 'Annual School License',
    start_date     DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date       DATE NOT NULL DEFAULT (CURRENT_DATE + INTERVAL '1 year'),
    status         TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'EXPIRED', 'SUSPENDED', 'INACTIVE')),
    notes          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT one_subscription_per_app UNIQUE (school_app_id)
);

-- 2. Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_school_app_subs_app_id ON public.school_app_subscriptions(school_app_id);
CREATE INDEX IF NOT EXISTS idx_school_app_subs_status ON public.school_app_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_school_app_subs_dates ON public.school_app_subscriptions(start_date, end_date);

-- 3. Enable RLS
ALTER TABLE public.school_app_subscriptions ENABLE ROW LEVEL SECURITY;

-- 4. Super Admin RLS Policies for school_app_subscriptions
DROP POLICY IF EXISTS "Super Admins full access to school_app_subscriptions" ON public.school_app_subscriptions;
CREATE POLICY "Super Admins full access to school_app_subscriptions"
ON public.school_app_subscriptions
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

-- 5. School Users read-only access to their own school's app subscription
DROP POLICY IF EXISTS "School Users read own school_app_subscription" ON public.school_app_subscriptions;
CREATE POLICY "School Users read own school_app_subscription"
ON public.school_app_subscriptions
FOR SELECT
TO authenticated
USING (
    school_app_id IN (
        SELECT sma.id FROM public.school_management_apps sma
        WHERE sma.school_id = public.get_user_school_id()
    )
);

-- 6. Trigger for updated_at timestamp
DROP TRIGGER IF EXISTS trg_school_app_subs_updated_at ON public.school_app_subscriptions;
CREATE TRIGGER trg_school_app_subs_updated_at
    BEFORE UPDATE ON public.school_app_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();
