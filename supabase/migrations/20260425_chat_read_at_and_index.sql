-- ============================================================
-- Migration: chat_messages.read_at + partial unread index
-- ============================================================
-- Live unread badges in admin/customer bottom navs need a fast
-- count of messages where read_at IS NULL. The repository write
-- path already updates read_at; this migration guarantees the
-- column exists and adds a partial index that makes the badge
-- query O(matches) instead of O(rows).

-- ── 1. Ensure read_at column exists ─────────────────────────
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS read_at timestamptz DEFAULT NULL;

-- ── 2. Backfill: any row already flagged is_read=true gets a
-- read_at if missing, so the partial index correctly excludes
-- legacy rows that the new realtime badges shouldn't surface.
UPDATE public.chat_messages
   SET read_at = COALESCE(read_at, created_at)
 WHERE is_read = true AND read_at IS NULL;

-- ── 3. Partial index for the badge unread-count query.
-- Indexed only on rows where read_at IS NULL — keeps the index
-- small and the count query nearly constant-time as the table
-- grows.
CREATE INDEX IF NOT EXISTS idx_chat_messages_unread
  ON public.chat_messages (ticket_id, sender_id)
  WHERE read_at IS NULL;
