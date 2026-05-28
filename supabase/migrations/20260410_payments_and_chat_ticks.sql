-- ============================================================
-- Migration: chat delivery ticks + installment receipt uploads
-- ============================================================

-- ── 1. Chat: delivered_at column ─────────────────────────────
ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz;

-- Backfill: any message that was already read is at minimum delivered.
UPDATE chat_messages
   SET delivered_at = COALESCE(read_at, created_at)
 WHERE delivered_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_chat_messages_delivered_at
  ON chat_messages (ticket_id, delivered_at);

-- ── 2. Installment payments: status + audit columns ─────────
ALTER TABLE installment_payments
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'verified',
  ADD COLUMN IF NOT EXISTS submitted_by uuid REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verified_by uuid REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS rejected_reason text;

-- Backfill existing rows as 'verified'
UPDATE installment_payments
   SET status = 'verified'
 WHERE status IS NULL;

CREATE INDEX IF NOT EXISTS idx_installment_payments_status
  ON installment_payments (status);

-- ── 3. payment_receipts table ───────────────────────────────
CREATE TABLE IF NOT EXISTS payment_receipts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id      uuid NOT NULL REFERENCES installment_payments(id) ON DELETE CASCADE,
  file_url        text NOT NULL,
  file_name       text,
  file_size_bytes int,
  mime_type       text,
  uploaded_by     uuid REFERENCES users(id),
  uploaded_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_receipts_payment_id
  ON payment_receipts (payment_id);

ALTER TABLE payment_receipts ENABLE ROW LEVEL SECURITY;

-- ── 4. Storage bucket: payment-receipts (private) ───────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('payment-receipts', 'payment-receipts', false)
ON CONFLICT (id) DO NOTHING;

-- ── 5. RLS policies ──────────────────────────────────────────

-- Helper: can current user access this payment_id?
-- (Customer = owns the plan, or Admin/Engineer.)
DROP POLICY IF EXISTS "payment_receipts_select" ON payment_receipts;
CREATE POLICY "payment_receipts_select"
  ON payment_receipts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
        FROM installment_payments ip
        JOIN installment_plans pl ON pl.id = ip.plan_id
       WHERE ip.id = payment_receipts.payment_id
         AND (
           pl.user_id = auth.uid()
           OR EXISTS (
             SELECT 1 FROM users u
              WHERE u.id = auth.uid()
                AND u.role IN ('admin', 'engineer')
           )
         )
    )
  );

DROP POLICY IF EXISTS "payment_receipts_insert" ON payment_receipts;
CREATE POLICY "payment_receipts_insert"
  ON payment_receipts
  FOR INSERT
  WITH CHECK (
    uploaded_by = auth.uid()
    AND EXISTS (
      SELECT 1
        FROM installment_payments ip
        JOIN installment_plans pl ON pl.id = ip.plan_id
       WHERE ip.id = payment_receipts.payment_id
         AND (
           pl.user_id = auth.uid()
           OR EXISTS (
             SELECT 1 FROM users u
              WHERE u.id = auth.uid()
                AND u.role IN ('admin', 'engineer')
           )
         )
    )
  );

DROP POLICY IF EXISTS "payment_receipts_delete_admin" ON payment_receipts;
CREATE POLICY "payment_receipts_delete_admin"
  ON payment_receipts
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM users u
       WHERE u.id = auth.uid()
         AND u.role IN ('admin')
    )
  );

-- Storage RLS for payment-receipts bucket
DROP POLICY IF EXISTS "payment_receipts_storage_read" ON storage.objects;
CREATE POLICY "payment_receipts_storage_read"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'payment-receipts'
    AND auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "payment_receipts_storage_insert" ON storage.objects;
CREATE POLICY "payment_receipts_storage_insert"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'payment-receipts'
    AND auth.role() = 'authenticated'
  );

-- ── 6. company_bank_accounts table (for Pay Installment sheet) ──
CREATE TABLE IF NOT EXISTS company_bank_accounts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bank_name       text NOT NULL,
  account_name    text NOT NULL,
  account_number  text NOT NULL,
  branch          text,
  swift_code      text,
  notes           text,
  display_order   int NOT NULL DEFAULT 0,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE company_bank_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "company_bank_accounts_read" ON company_bank_accounts;
CREATE POLICY "company_bank_accounts_read"
  ON company_bank_accounts
  FOR SELECT
  USING (auth.role() = 'authenticated' AND is_active = true);

DROP POLICY IF EXISTS "company_bank_accounts_admin_write" ON company_bank_accounts;
CREATE POLICY "company_bank_accounts_admin_write"
  ON company_bank_accounts
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM users u
       WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM users u
       WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );
