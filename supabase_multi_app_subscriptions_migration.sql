-- ==============================================================================
-- SUPER ADMIN: MULTI-PRODUCT, DEDICATED SCHOOL APPS & SUBSCRIPTION SCHEMA
-- Authoritative Tenant Identifier: public.schools.id (UUID)
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. PRODUCTS / APPLICATIONS TABLE
-- Represents the core SaaS product offerings managed from Super Admin
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code TEXT UNIQUE NOT NULL, -- e.g. 'school_management', 'finance_management'
    display_name TEXT NOT NULL,
    description TEXT,
    platform TEXT NOT NULL DEFAULT 'android',
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed Initial Products
INSERT INTO public.products (product_code, display_name, description, platform, status)
VALUES 
    ('school_management', 'School Management OS', 'Core multi-tenant school administration, attendance, exams, and staff portal', 'android', 'ACTIVE'),
    ('finance_management', 'School Finance OS', 'Fee collection, ledgers, component invoicing, and payment processing', 'android', 'ACTIVE'),
    ('transport_management', 'Transport OS', 'Bus route tracking, driver assignments, and vehicle telematics', 'android', 'ACTIVE'),
    ('library_management', 'Library OS', 'Book inventory, circulation, barcode checkouts, and late fee tracking', 'android', 'ACTIVE')
ON CONFLICT (product_code) DO NOTHING;

-- 2. DEDICATED SCHOOL APPS TABLE
-- Represents individual branded mobile applications built by developers for specific schools
CREATE TABLE IF NOT EXISTS public.school_apps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    app_name TEXT NOT NULL,
    package_name TEXT, -- e.g. 'com.company.abcschool'
    app_identifier TEXT UNIQUE, -- e.g. 'ABC_APP_SCH001'
    platform TEXT NOT NULL DEFAULT 'android',
    current_version TEXT NOT NULL DEFAULT '1.0.0',
    play_store_url TEXT,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')), -- Access active/inactive
    release_status TEXT NOT NULL DEFAULT 'PUBLISHED' CHECK (release_status IN ('DEVELOPMENT', 'TESTING', 'PUBLISHED', 'MAINTENANCE')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_school_product_app UNIQUE (school_id, product_id)
);

-- 3. SUBSCRIPTIONS TABLE
-- Controls independent tenant subscription lifecycles per School/Product
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    school_app_id UUID REFERENCES public.school_apps(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'EXPIRED', 'SUSPENDED')),
    start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date DATE NOT NULL DEFAULT (CURRENT_DATE + INTERVAL '1 year'),
    plan_type TEXT NOT NULL DEFAULT 'ANNUAL' CHECK (plan_type IN ('TRIAL', 'MONTHLY', 'ANNUAL', 'ENTERPRISE')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_school_product_subscription UNIQUE (school_id, product_id)
);

-- 4. RLS POLICIES FOR SUPER ADMIN FULL ACCESS
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_apps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- Products: Super Admin full CRUD, authenticated read-only
DROP POLICY IF EXISTS "Super Admin full CRUD products" ON public.products;
CREATE POLICY "Super Admin full CRUD products"
ON public.products FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles p 
        WHERE p.auth_user_id = auth.uid() 
        AND p.role IN ('super_admin', 'owner') 
        AND p.status = 'active'
    )
);

DROP POLICY IF EXISTS "Authenticated read products" ON public.products;
CREATE POLICY "Authenticated read products"
ON public.products FOR SELECT TO authenticated
USING (true);

-- School Apps: Super Admin full CRUD, Tenant users read own school app
DROP POLICY IF EXISTS "Super Admin full CRUD school_apps" ON public.school_apps;
CREATE POLICY "Super Admin full CRUD school_apps"
ON public.school_apps FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles p 
        WHERE p.auth_user_id = auth.uid() 
        AND p.role IN ('super_admin', 'owner') 
        AND p.status = 'active'
    )
);

DROP POLICY IF EXISTS "Tenant users read own school apps" ON public.school_apps;
CREATE POLICY "Tenant users read own school apps"
ON public.school_apps FOR SELECT TO authenticated
USING (
    school_id IN (
        SELECT p.school_id FROM public.profiles p WHERE p.auth_user_id = auth.uid()
    )
);

-- Subscriptions: Super Admin full CRUD, Tenant users read own school subscription
DROP POLICY IF EXISTS "Super Admin full CRUD subscriptions" ON public.subscriptions;
CREATE POLICY "Super Admin full CRUD subscriptions"
ON public.subscriptions FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles p 
        WHERE p.auth_user_id = auth.uid() 
        AND p.role IN ('super_admin', 'owner') 
        AND p.status = 'active'
    )
);

DROP POLICY IF EXISTS "Tenant users read own subscriptions" ON public.subscriptions;
CREATE POLICY "Tenant users read own subscriptions"
ON public.subscriptions FOR SELECT TO authenticated
USING (
    school_id IN (
        SELECT p.school_id FROM public.profiles p WHERE p.auth_user_id = auth.uid()
    )
);
