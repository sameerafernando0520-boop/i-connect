-- ============================================================
-- Migration: relax installment_payments.status check constraint
-- ============================================================
-- The customer payment submission path (lib/widgets/customer/
-- submit_payment_sheet.dart) writes status='submitted' so the admin
-- can verify or reject it. The original CHECK constraint only allowed
-- ('pending','paid','overdue') which caused Postgres error 23514:
--   new row for relation "installment_payments" violates check
--   constraint "installment_payments_status_check"
-- and silently broke the entire receipt-upload flow.
--
-- This migration drops and re-creates the constraint with the full
-- status lifecycle: pending -> submitted -> (paid|rejected),
-- overdue as an automated marker, plus reserved values verified/
-- rejected for future explicit-state admin code paths.

ALTER TABLE public.installment_payments
  DROP CONSTRAINT IF EXISTS installment_payments_status_check;

ALTER TABLE public.installment_payments
  ADD CONSTRAINT installment_payments_status_check
  CHECK (status = ANY (ARRAY[
    'pending'::text,
    'submitted'::text,
    'paid'::text,
    'overdue'::text,
    'verified'::text,
    'rejected'::text
  ]));
