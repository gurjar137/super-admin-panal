-- ==============================================================================
-- PERSISTENT ADMINISTRATIVE AUDIT LOGGING MIGRATION
-- Project: Central Super Admin OS
-- Description: Creates the canonical public.super_admin_audit_logs table,
--              server-controlled record_super_admin_audit_event RPC,
--              append-only triggers, strict RLS policies, and performance indexes.
-- ==============================================================================

-- 1. Create canonical audit log table
CREATE TABLE IF NOT EXISTS public.super_admin_audit_logs (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_auth_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    actor_profile_id   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    actor_role         TEXT NOT NULL,
    action             TEXT NOT NULL,
    entity_type        TEXT NOT NULL,
    entity_id          TEXT,
    school_id          UUID REFERENCES public.schools(id) ON DELETE SET NULL,
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2. Performance indexes
CREATE INDEX IF NOT EXISTS idx_super_admin_audit_logs_created_at 
    ON public.super_admin_audit_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_super_admin_audit_logs_actor 
    ON public.super_admin_audit_logs (actor_auth_user_id);

CREATE INDEX IF NOT EXISTS idx_super_admin_audit_logs_school 
    ON public.super_admin_audit_logs (school_id);

CREATE INDEX IF NOT EXISTS idx_super_admin_audit_logs_action 
    ON public.super_admin_audit_logs (action);

CREATE INDEX IF NOT EXISTS idx_super_admin_audit_logs_entity 
    ON public.super_admin_audit_logs (entity_type, entity_id);

-- 3. Engine-level immutability enforcement trigger (UPDATE / DELETE strictly blocked)
CREATE OR REPLACE FUNCTION public.fn_prevent_super_admin_audit_logs_mutation()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Audit logs are immutable and cannot be updated or deleted';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_audit_logs_mutation ON public.super_admin_audit_logs;
CREATE TRIGGER trg_prevent_audit_logs_mutation
BEFORE UPDATE OR DELETE ON public.super_admin_audit_logs
FOR EACH ROW
EXECUTE FUNCTION public.fn_prevent_super_admin_audit_logs_mutation();

-- 4. Enable RLS and configure least-privilege permissions
ALTER TABLE public.super_admin_audit_logs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.super_admin_audit_logs FROM anon, authenticated, public;
GRANT SELECT ON TABLE public.super_admin_audit_logs TO authenticated;

-- Narrow SELECT policy: Only active super_admin or owner can view audit logs
DROP POLICY IF EXISTS "Super Admins view audit logs" ON public.super_admin_audit_logs;
CREATE POLICY "Super Admins view audit logs"
ON public.super_admin_audit_logs
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

-- 5. Central server-controlled audit event writer RPC
CREATE OR REPLACE FUNCTION public.record_super_admin_audit_event(
    p_action TEXT,
    p_entity_type TEXT,
    p_entity_id TEXT DEFAULT NULL,
    p_school_id UUID DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_auth_id UUID;
    v_actor_profile_id UUID;
    v_actor_role TEXT;
    v_log_id UUID;
    v_clean_metadata JSONB;
BEGIN
    -- 1. Authenticated check
    v_actor_auth_id := auth.uid();
    IF v_actor_auth_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not authenticated';
    END IF;

    -- 2. Authoritative server-side identity check from public.profiles
    SELECT p.id, p.role INTO v_actor_profile_id, v_actor_role
    FROM public.profiles p
    WHERE p.auth_user_id = v_actor_auth_id
      AND p.status = 'active'
      AND p.role IN ('super_admin', 'owner')
    LIMIT 1;

    IF v_actor_role IS NULL THEN
        RAISE EXCEPTION 'Forbidden: Only active Super Admin or Owner can record audit logs';
    END IF;

    -- 3. Parameter validation
    IF p_action IS NULL OR trim(p_action) = '' THEN
        RAISE EXCEPTION 'Invalid parameter: action cannot be empty';
    END IF;
    IF p_entity_type IS NULL OR trim(p_entity_type) = '' THEN
        RAISE EXCEPTION 'Invalid parameter: entity_type cannot be empty';
    END IF;

    -- 4. Secret scrubbing: prevent sensitive credentials from persisting in metadata
    v_clean_metadata := COALESCE(p_metadata, '{}'::jsonb);
    v_clean_metadata := v_clean_metadata 
        - 'password' 
        - 'access_token' 
        - 'refresh_token' 
        - 'token' 
        - 'secret' 
        - 'service_role_key' 
        - 'api_key' 
        - 'apikey' 
        - 'private_key';

    -- 5. Insert audit log record
    INSERT INTO public.super_admin_audit_logs (
        actor_auth_user_id,
        actor_profile_id,
        actor_role,
        action,
        entity_type,
        entity_id,
        school_id,
        metadata,
        created_at
    ) VALUES (
        v_actor_auth_id,
        v_actor_profile_id,
        v_actor_role,
        trim(p_action),
        trim(p_entity_type),
        p_entity_id,
        p_school_id,
        v_clean_metadata,
        timezone('utc'::text, now())
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

-- 6. RPC Privileges
REVOKE ALL ON FUNCTION public.record_super_admin_audit_event(TEXT, TEXT, TEXT, UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_super_admin_audit_event(TEXT, TEXT, TEXT, UUID, JSONB) TO authenticated;
