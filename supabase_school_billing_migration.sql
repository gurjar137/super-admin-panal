-- ==============================================================================
-- PER-STUDENT SCHOOL BILLING, INVOICING & PAYMENT TRACKING MIGRATION
-- Project: Super Admin OS
-- Description: Creates school_billing_settings, school_invoices, and
--              invoice_payments tables with immutable snapshots, human-readable
--              invoice numbers, duplicate prevention, and strict RLS policies.
-- ==============================================================================

-- 1. Create sequence for human-readable invoice numbers
CREATE SEQUENCE IF NOT EXISTS public.school_invoice_number_seq START 1;

-- 2. Create school_billing_settings table (Per-school rate configuration)
CREATE TABLE IF NOT EXISTS public.school_billing_settings (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id        UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    rate_per_student NUMERIC(10, 2) NOT NULL DEFAULT 20.00,
    currency         TEXT NOT NULL DEFAULT 'INR',
    billing_cycle    TEXT NOT NULL DEFAULT 'MONTHLY',
    active           BOOLEAN NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_school_billing_settings_school UNIQUE (school_id)
);

-- 3. Create school_invoices table (Immutable snapshot invoices)
CREATE TABLE IF NOT EXISTS public.school_invoices (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_number       TEXT UNIQUE,
    school_id            UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    academic_year_id     UUID REFERENCES public.academic_years(id) ON DELETE SET NULL,
    billing_period_start DATE NOT NULL,
    billing_period_end   DATE NOT NULL,
    student_count        INTEGER NOT NULL DEFAULT 0,
    rate_per_student     NUMERIC(10, 2) NOT NULL DEFAULT 20.00,
    currency             TEXT NOT NULL DEFAULT 'INR',
    subtotal             NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_amount         NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    status               TEXT NOT NULL DEFAULT 'UNPAID' CHECK (status IN ('DRAFT', 'GENERATED', 'UNPAID', 'PAID', 'OVERDUE', 'CANCELLED')),
    due_date             DATE NOT NULL,
    paid_at              TIMESTAMPTZ,
    paid_by              TEXT,
    cancelled_at         TIMESTAMPTZ,
    cancelled_by         TEXT,
    created_by           TEXT,
    notes                TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_school_invoice_period UNIQUE (school_id, billing_period_start, billing_period_end)
);

-- Function to auto-populate human-readable invoice_number if not provided
CREATE OR REPLACE FUNCTION public.fn_generate_invoice_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.invoice_number IS NULL OR trim(NEW.invoice_number) = '' THEN
        NEW.invoice_number := 'INV-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' || LPAD(nextval('public.school_invoice_number_seq')::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_school_invoices_number ON public.school_invoices;
CREATE TRIGGER trg_school_invoices_number
    BEFORE INSERT ON public.school_invoices
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_generate_invoice_number();

-- 4. Create invoice_payments table (Payment tracking ledger)
CREATE TABLE IF NOT EXISTS public.invoice_payments (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id        UUID NOT NULL REFERENCES public.school_invoices(id) ON DELETE CASCADE,
    amount            NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    payment_date      TIMESTAMPTZ NOT NULL DEFAULT now(),
    payment_method    TEXT NOT NULL CHECK (payment_method IN ('CASH', 'BANK_TRANSFER', 'UPI', 'OTHER')),
    payment_reference TEXT,
    notes             TEXT,
    status            TEXT NOT NULL DEFAULT 'COMPLETED' CHECK (status IN ('COMPLETED', 'VOIDED')),
    created_by        TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Indexes for fast query lookup
CREATE INDEX IF NOT EXISTS idx_school_invoices_school_id ON public.school_invoices(school_id);
CREATE INDEX IF NOT EXISTS idx_school_invoices_status ON public.school_invoices(status);
CREATE INDEX IF NOT EXISTS idx_school_invoices_period ON public.school_invoices(billing_period_start, billing_period_end);
CREATE INDEX IF NOT EXISTS idx_school_invoices_number ON public.school_invoices(invoice_number);
CREATE INDEX IF NOT EXISTS idx_school_billing_settings_school ON public.school_billing_settings(school_id);
CREATE INDEX IF NOT EXISTS idx_invoice_payments_invoice_id ON public.invoice_payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_payments_status ON public.invoice_payments(status);

-- 6. Enable Row-Level Security
ALTER TABLE public.school_billing_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_payments ENABLE ROW LEVEL SECURITY;

-- 7. Super Admin / Owner Full Access Policies
DROP POLICY IF EXISTS "Super Admins full access to school_billing_settings" ON public.school_billing_settings;
CREATE POLICY "Super Admins full access to school_billing_settings"
ON public.school_billing_settings FOR ALL TO authenticated
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

DROP POLICY IF EXISTS "Super Admins full access to school_invoices" ON public.school_invoices;
CREATE POLICY "Super Admins full access to school_invoices"
ON public.school_invoices FOR ALL TO authenticated
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

DROP POLICY IF EXISTS "Super Admins full access to invoice_payments" ON public.invoice_payments;
CREATE POLICY "Super Admins full access to invoice_payments"
ON public.invoice_payments FOR ALL TO authenticated
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

-- 8. School Admin / User Read Access (Scoped strictly to their own school)
DROP POLICY IF EXISTS "School Users read own billing settings" ON public.school_billing_settings;
CREATE POLICY "School Users read own billing settings"
ON public.school_billing_settings FOR SELECT TO authenticated
USING (school_id = public.get_user_school_id());

DROP POLICY IF EXISTS "School Users read own invoices" ON public.school_invoices;
CREATE POLICY "School Users read own invoices"
ON public.school_invoices FOR SELECT TO authenticated
USING (school_id = public.get_user_school_id());

DROP POLICY IF EXISTS "School Users read own payments" ON public.invoice_payments;
CREATE POLICY "School Users read own payments"
ON public.invoice_payments FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.school_invoices inv
        WHERE inv.id = invoice_payments.invoice_id
        AND inv.school_id = public.get_user_school_id()
    )
);

-- 9. Triggers for updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_school_billing_settings_updated_at ON public.school_billing_settings;
CREATE TRIGGER trg_school_billing_settings_updated_at
    BEFORE UPDATE ON public.school_billing_settings
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_school_invoices_updated_at ON public.school_invoices;
CREATE TRIGGER trg_school_invoices_updated_at
    BEFORE UPDATE ON public.school_invoices
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- 10. Atomic Payment Recording Procedure (Financial Integrity)
-- Guarantees atomic insertion into public.invoice_payments and update to public.school_invoices
-- Prevents orphaned payments and phantom PAID invoices.
CREATE OR REPLACE FUNCTION public.record_invoice_payment_atomic(
    p_invoice_id UUID,
    p_amount NUMERIC,
    p_payment_method TEXT,
    p_payment_reference TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_payment_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_role TEXT;
    v_caller_status TEXT;
    v_caller_email TEXT;
    v_invoice RECORD;
    v_payment_id UUID;
    v_effective_date TIMESTAMPTZ;
    v_result JSONB;
BEGIN
    -- 1. Authoritative caller verification from server-side public.profiles
    SELECT role, status, email INTO v_caller_role, v_caller_status, v_caller_email
    FROM public.profiles
    WHERE auth_user_id = auth.uid()
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('super_admin', 'owner') OR LOWER(v_caller_status) != 'active' THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an active Super Admin or Owner';
    END IF;

    -- 2. Lock invoice row to prevent race conditions & double payments
    SELECT * INTO v_invoice
    FROM public.school_invoices
    WHERE id = p_invoice_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice not found: %', p_invoice_id;
    END IF;

    IF v_invoice.status = 'PAID' THEN
        RAISE EXCEPTION 'Invoice is already paid';
    END IF;

    IF v_invoice.status = 'CANCELLED' THEN
        RAISE EXCEPTION 'Cannot record payment for a cancelled invoice';
    END IF;

    -- 3. Validate payment amounts & inputs
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero';
    END IF;

    IF ABS(p_amount - v_invoice.total_amount) > 0.01 THEN
        RAISE EXCEPTION 'Full payment only: Payment amount (₹%) must match invoice total (₹%)', p_amount, v_invoice.total_amount;
    END IF;

    IF p_payment_method NOT IN ('CASH', 'BANK_TRANSFER', 'UPI', 'OTHER') THEN
        RAISE EXCEPTION 'Invalid payment method: %', p_payment_method;
    END IF;

    v_effective_date := COALESCE(p_payment_date, clock_timestamp());

    -- 4. Atomic step 1: Insert payment ledger row
    INSERT INTO public.invoice_payments (
        invoice_id,
        amount,
        payment_date,
        payment_method,
        payment_reference,
        notes,
        status,
        created_by
    ) VALUES (
        p_invoice_id,
        p_amount,
        v_effective_date,
        p_payment_method,
        NULLIF(TRIM(p_payment_reference), ''),
        NULLIF(TRIM(p_notes), ''),
        'COMPLETED',
        COALESCE(v_caller_email, auth.uid()::text)
    ) RETURNING id INTO v_payment_id;

    -- 5. Atomic step 2: Update invoice status to PAID
    UPDATE public.school_invoices
    SET
        status = 'PAID',
        paid_at = v_effective_date,
        paid_by = COALESCE(v_caller_email, auth.uid()::text),
        updated_at = clock_timestamp()
    WHERE id = p_invoice_id;

    -- 6. Query and return updated invoice representation
    SELECT to_jsonb(inv) INTO v_result
    FROM public.school_invoices inv
    WHERE inv.id = p_invoice_id;

    RETURN v_result;
END;
$$;

-- Explicitly revoke all privileges from PUBLIC (anon / unauthenticated)
REVOKE ALL ON FUNCTION public.record_invoice_payment_atomic(
    UUID,
    NUMERIC,
    TEXT,
    TEXT,
    TEXT,
    TIMESTAMPTZ
) FROM PUBLIC;

-- Grant execution only to authenticated callers (function internally enforces active super_admin/owner role)
GRANT EXECUTE ON FUNCTION public.record_invoice_payment_atomic(
    UUID,
    NUMERIC,
    TEXT,
    TEXT,
    TEXT,
    TIMESTAMPTZ
) TO authenticated;

