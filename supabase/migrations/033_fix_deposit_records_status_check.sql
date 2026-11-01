-- Migration 033: Expand payment_status check constraint on deposit_records table to include 'expired'

ALTER TABLE public.deposit_records DROP CONSTRAINT IF EXISTS deposit_records_payment_status_check;
ALTER TABLE public.deposit_records ADD CONSTRAINT deposit_records_payment_status_check 
CHECK (payment_status IN ('awaiting_payment', 'under_review', 'verified', 'rejected', 'expired'));
