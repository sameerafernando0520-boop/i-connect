-- ============================================================
-- Soft-delete (archive) support for service tickets.
--
-- Showing every old service ticket clutters the admin and
-- engineering-admin lists. This migration adds a reversible
-- "archive" flag: archived tickets are hidden from all lists
-- and counts (the app filters `is_deleted = false`) but the row
-- and its chat/activity history are retained and recoverable.
--
-- Only `admin` and `engineering_admin` roles may archive/restore
-- (enforced by a BEFORE UPDATE trigger so a customer can't flip
-- the flag on their own ticket via the existing update policies).
-- ============================================================

ALTER TABLE public.service_tickets
  ADD COLUMN IF NOT EXISTS is_deleted  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at  timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by  uuid REFERENCES public.users(id) ON DELETE SET NULL;

-- Partial index keeps the common "active tickets" queries fast.
CREATE INDEX IF NOT EXISTS idx_service_tickets_active
  ON public.service_tickets (is_deleted)
  WHERE is_deleted = false;

-- ── Guard: only admin / engineering_admin may change is_deleted ──
CREATE OR REPLACE FUNCTION public.enforce_ticket_archive_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_deleted IS DISTINCT FROM OLD.is_deleted THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.users u
       WHERE u.id = auth.uid()
         AND u.role IN ('admin', 'engineering_admin')
    ) THEN
      RAISE EXCEPTION 'Only admins or engineering admins can archive tickets';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_ticket_archive_role ON public.service_tickets;
CREATE TRIGGER trg_enforce_ticket_archive_role
  BEFORE UPDATE ON public.service_tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_ticket_archive_role();
