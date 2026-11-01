-- Migration 024: Fix Check Constraint on deposit_evidence_submissions to allow payment method types (bank_transfer, qr_payment, etc.)

ALTER TABLE public.deposit_evidence_submissions 
DROP CONSTRAINT IF EXISTS deposit_evidence_submissions_evidence_type_check;

ALTER TABLE public.deposit_evidence_submissions 
ADD CONSTRAINT deposit_evidence_submissions_evidence_type_check 
CHECK (evidence_type IN ('image', 'pdf', 'bank_transfer', 'connect_ips', 'qr_payment', 'receipt_upload', 'Bank Transfer', 'QR Payment'));
