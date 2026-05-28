-- ═══════════════════════════════════════════════════════════════
-- Next Journey Progress System — v1.0
-- Tables: suggestion_batches, machine_suggestions, journey_nudges
-- Run in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- TABLE 1: suggestion_batches
-- Each batch links one machine from catalog with an optional note
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS suggestion_batches (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id   UUID        NOT NULL
               REFERENCES machine_catalog(id) ON DELETE CASCADE,
  note         TEXT,
  suggested_by UUID        REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_suggestion_batches_machine
  ON suggestion_batches(machine_id);
CREATE INDEX IF NOT EXISTS idx_suggestion_batches_created
  ON suggestion_batches(created_at DESC);

ALTER TABLE suggestion_batches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS suggestion_batches_admin ON suggestion_batches;
CREATE POLICY suggestion_batches_admin
  ON suggestion_batches FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid()
        AND role IN ('admin', 'marketing_admin', 'engineering_admin')
    )
  );

-- ═══════════════════════════════════════════════════════════════
-- TABLE 2: machine_suggestions
-- One row per customer per active suggestion.
-- journey_score (0–100) is SET BY ADMIN — not computed.
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS machine_suggestions (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id     UUID        NOT NULL
               REFERENCES suggestion_batches(id) ON DELETE CASCADE,
  customer_id  UUID        NOT NULL
               REFERENCES users(id) ON DELETE CASCADE,
  is_active    BOOLEAN     NOT NULL DEFAULT true,

  -- Engagement tracking (system records silently)
  viewed_at    TIMESTAMPTZ,
  clicked_at   TIMESTAMPTZ,

  -- ADMIN-CONTROLLED JOURNEY SCORE (0–100)
  -- Set manually by marketer via slider — NOT a formula
  journey_score INTEGER     NOT NULL DEFAULT 0
                CHECK (journey_score >= 0 AND journey_score <= 100),

  -- Stage note — admin writes what stage the customer is at
  -- NOT visible to customer
  stage_note   TEXT,

  -- Milestone push flags — set true once sent; never re-sent
  milestone_25_sent  BOOLEAN NOT NULL DEFAULT false,
  milestone_50_sent  BOOLEAN NOT NULL DEFAULT false,
  milestone_75_sent  BOOLEAN NOT NULL DEFAULT false,
  milestone_100_sent BOOLEAN NOT NULL DEFAULT false,

  -- Audit trail
  score_updated_by  UUID        REFERENCES users(id),
  score_updated_at  TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_machine_suggestions_customer
  ON machine_suggestions(customer_id, is_active);
CREATE INDEX IF NOT EXISTS idx_machine_suggestions_batch
  ON machine_suggestions(batch_id);
CREATE INDEX IF NOT EXISTS idx_machine_suggestions_score
  ON machine_suggestions(journey_score);

ALTER TABLE machine_suggestions ENABLE ROW LEVEL SECURITY;

-- Customer reads only their own suggestion
DROP POLICY IF EXISTS machine_suggestions_customer_select ON machine_suggestions;
CREATE POLICY machine_suggestions_customer_select
  ON machine_suggestions FOR SELECT TO authenticated
  USING (customer_id = auth.uid());

-- Customer updates ONLY viewed_at and clicked_at (not journey_score)
DROP POLICY IF EXISTS machine_suggestions_customer_update ON machine_suggestions;
CREATE POLICY machine_suggestions_customer_update
  ON machine_suggestions FOR UPDATE TO authenticated
  USING (customer_id = auth.uid())
  WITH CHECK (customer_id = auth.uid());

-- Admin has full access
DROP POLICY IF EXISTS machine_suggestions_admin ON machine_suggestions;
CREATE POLICY machine_suggestions_admin
  ON machine_suggestions FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid()
        AND role IN ('admin', 'marketing_admin', 'engineering_admin')
    )
  );

-- ═══════════════════════════════════════════════════════════════
-- TABLE 3: journey_nudges
-- Records every nudge message admin sends to customer
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS journey_nudges (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  suggestion_id UUID        NOT NULL
                REFERENCES machine_suggestions(id) ON DELETE CASCADE,
  customer_id   UUID        NOT NULL
                REFERENCES users(id) ON DELETE CASCADE,
  sent_by       UUID        REFERENCES users(id),
  message       TEXT        NOT NULL,
  score_at_send INTEGER,
  sent_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_journey_nudges_suggestion
  ON journey_nudges(suggestion_id);
CREATE INDEX IF NOT EXISTS idx_journey_nudges_customer
  ON journey_nudges(customer_id);

ALTER TABLE journey_nudges ENABLE ROW LEVEL SECURITY;

-- Customer can read nudges sent to them
DROP POLICY IF EXISTS journey_nudges_customer_select ON journey_nudges;
CREATE POLICY journey_nudges_customer_select
  ON journey_nudges FOR SELECT TO authenticated
  USING (customer_id = auth.uid());

-- Admin full access
DROP POLICY IF EXISTS journey_nudges_admin ON journey_nudges;
CREATE POLICY journey_nudges_admin
  ON journey_nudges FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid()
        AND role IN ('admin', 'marketing_admin', 'engineering_admin')
    )
  );

-- ═══════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename IN (
  'suggestion_batches',
  'machine_suggestions',
  'journey_nudges'
)
ORDER BY tablename;
