-- Migration 039: Make document paths nullable in business_profiles to prevent registration & update failures
ALTER TABLE public.business_profiles ALTER COLUMN company_pan_path DROP NOT NULL;
ALTER TABLE public.business_profiles ALTER COLUMN company_registration_path DROP NOT NULL;
ALTER TABLE public.business_profiles ALTER COLUMN company_qr_path DROP NOT NULL;
