-- ==============================================================================
-- PHASE 6: SCHOOL MANAGEMENT APPS CONSTRAINT MIGRATION
-- Project: Super Admin OS
-- Description: Adds unique indexes on app_identifier and package_name
--              for public.school_management_apps.
-- ==============================================================================

-- 1. Ensure unique app_identifier across all school management apps
CREATE UNIQUE INDEX IF NOT EXISTS uq_school_mgmt_apps_app_identifier
ON public.school_management_apps (app_identifier)
WHERE app_identifier IS NOT NULL AND app_identifier != '';

-- 2. Ensure unique android package_name across all school management apps
CREATE UNIQUE INDEX IF NOT EXISTS uq_school_mgmt_apps_package_name
ON public.school_management_apps (package_name)
WHERE package_name IS NOT NULL AND package_name != '';

-- 3. Comment explaining metadata fields
COMMENT ON COLUMN public.school_management_apps.app_identifier IS 
'Unique application identifier used by the dedicated School Management App client (e.g. ABC_SCHOOL_APP)';

COMMENT ON COLUMN public.school_management_apps.package_name IS 
'Android application package ID used for Google Play Store identity (e.g. com.company.abcschool)';
