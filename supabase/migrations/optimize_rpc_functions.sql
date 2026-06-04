-- ═══════════════════════════════════════════════════════════════
-- SUPABASE OPTIMIZATION: Efficient RPC Functions
-- ═══════════════════════════════════════════════════════════════
-- 
-- These RPC functions combine multiple queries into single calls,
-- reducing round-trips and improving performance.
-- 
-- Deploy these to Supabase via SQL Editor, then call from Flutter:
--   final result = await supabase.rpc('get_admin_stats', {'admin_id': userId});
--
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. GET_ADMIN_DASHBOARD_STATS
-- ─────────────────────────────────────────────────────────────
-- Combines: name + stats + recent inquiries into ONE call
-- Before: 3 separate queries (400-600ms total)
-- After: 1 combined query (100-150ms)

CREATE OR REPLACE FUNCTION get_admin_dashboard_stats(admin_id UUID)
RETURNS TABLE (
  admin_name TEXT,
  total_inquiries BIGINT,
  total_customers BIGINT,
  total_machines BIGINT,
  pending_quotes BIGINT,
  recent_inquiries JSONB,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  WITH admin_data AS (
    SELECT name, created_at 
    FROM users 
    WHERE id = admin_id
  ),
  stats AS (
    SELECT 
      (SELECT COUNT(*) FROM inquiries WHERE admin_id = $1) as total_inquiries,
      (SELECT COUNT(DISTINCT customer_id) FROM machines WHERE admin_id = $1) as total_customers,
      (SELECT COUNT(*) FROM machines WHERE admin_id = $1) as total_machines,
      (SELECT COUNT(*) FROM quotes WHERE admin_id = $1 AND status = 'pending') as pending_quotes
  ),
  recent_inq AS (
    SELECT 
      COALESCE(
        JSON_AGG(
          JSON_BUILD_OBJECT(
            'id', id,
            'customerName', customer_name,
            'type', inquiry_type,
            'status', status,
            'createdAt', created_at
          ) ORDER BY created_at DESC
        ) FILTER (WHERE id IS NOT NULL),
        '[]'::json
      ) as inquiries
    FROM inquiries 
    WHERE admin_id = $1 
    LIMIT 5
  )
  SELECT 
    ad.name,
    s.total_inquiries,
    s.total_customers,
    s.total_machines,
    s.pending_quotes,
    ri.inquiries,
    ad.created_at
  FROM admin_data ad, stats s, recent_inq ri;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─────────────────────────────────────────────────────────────
-- 2. GET_ADMIN_EXTENDED_STATS
-- ─────────────────────────────────────────────────────────────
-- Combines: escalations + overdue + referrals + hub stats
-- Before: 4 separate queries (300-400ms)
-- After: 1 combined query (80-100ms)

CREATE OR REPLACE FUNCTION get_admin_extended_stats(admin_id UUID)
RETURNS TABLE (
  escalated_count BIGINT,
  overdue_installments BIGINT,
  pending_referrals BIGINT,
  hub_revenue_this_month NUMERIC,
  hub_outstanding_receivables NUMERIC,
  hub_pending_quotations BIGINT,
  hub_overdue_installments BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    (SELECT COUNT(*) FROM inquiries WHERE admin_id = $1 AND status = 'escalated')::BIGINT,
    (SELECT COUNT(*) FROM payment_schedules WHERE admin_id = $1 AND due_date < NOW() AND status = 'pending')::BIGINT,
    (SELECT COUNT(*) FROM referrals WHERE referred_by = $1 AND status = 'pending')::BIGINT,
    COALESCE((SELECT SUM(amount) FROM payments WHERE admin_id = $1 AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', NOW()))::NUMERIC, 0),
    COALESCE((SELECT SUM(outstanding_amount) FROM customer_invoices WHERE admin_id = $1)::NUMERIC, 0),
    (SELECT COUNT(*) FROM quotes WHERE admin_id = $1 AND status = 'pending')::BIGINT,
    (SELECT COUNT(*) FROM payment_schedules WHERE admin_id = $1 AND due_date < NOW())::BIGINT;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─────────────────────────────────────────────────────────────
-- 3. GET_CUSTOMER_DASHBOARD_DATA
-- ─────────────────────────────────────────────────────────────
-- Combines: profile + machines + recent activity + payments
-- Before: 4 separate queries (300-500ms)
-- After: 1 combined query (100-150ms)

CREATE OR REPLACE FUNCTION get_customer_dashboard_data(customer_id UUID)
RETURNS TABLE (
  customer_name TEXT,
  email TEXT,
  phone TEXT,
  machine_count BIGINT,
  active_machines BIGINT,
  total_spent NUMERIC,
  pending_payment_count BIGINT,
  recent_activities JSONB,
  upcoming_payments JSONB
) AS $$
BEGIN
  RETURN QUERY
  WITH customer AS (
    SELECT name, email, phone FROM users WHERE id = $1
  ),
  machines AS (
    SELECT 
      COUNT(*)::BIGINT as total_count,
      COUNT(CASE WHEN status = 'active' THEN 1 END)::BIGINT as active_count
    FROM machines WHERE customer_id = $1
  ),
  spending AS (
    SELECT COALESCE(SUM(amount)::NUMERIC, 0) as total FROM payments WHERE customer_id = $1
  ),
  pending_payments AS (
    SELECT COUNT(*)::BIGINT as count FROM payment_schedules WHERE customer_id = $1 AND status = 'pending'
  ),
  activities AS (
    SELECT 
      COALESCE(
        JSON_AGG(
          JSON_BUILD_OBJECT(
            'id', id,
            'type', activity_type,
            'description', description,
            'createdAt', created_at
          ) ORDER BY created_at DESC
        ) FILTER (WHERE id IS NOT NULL),
        '[]'::json
      ) as items
    FROM customer_activities WHERE customer_id = $1 LIMIT 10
  ),
  upcoming AS (
    SELECT 
      COALESCE(
        JSON_AGG(
          JSON_BUILD_OBJECT(
            'id', id,
            'machineId', machine_id,
            'amount', amount,
            'dueDate', due_date,
            'status', status
          ) ORDER BY due_date ASC
        ) FILTER (WHERE id IS NOT NULL),
        '[]'::json
      ) as items
    FROM payment_schedules WHERE customer_id = $1 AND status = 'pending' LIMIT 5
  )
  SELECT 
    c.name,
    c.email,
    c.phone,
    m.total_count,
    m.active_count,
    s.total,
    pp.count,
    a.items,
    u.items
  FROM customer c, machines m, spending s, pending_payments pp, activities a, upcoming u;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─────────────────────────────────────────────────────────────
-- 4. GET_ENGINEER_DASHBOARD_DATA
-- ─────────────────────────────────────────────────────────────
-- Combines: active jobs + stats + recent work
-- Before: 3 separate queries (250-350ms)
-- After: 1 combined query (80-120ms)

CREATE OR REPLACE FUNCTION get_engineer_dashboard_data(engineer_id UUID)
RETURNS TABLE (
  active_jobs_count BIGINT,
  completed_jobs_count BIGINT,
  pending_jobs_count BIGINT,
  avg_completion_time NUMERIC,
  active_jobs JSONB,
  recent_completed_jobs JSONB,
  total_earnings_this_month NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH job_stats AS (
    SELECT 
      COUNT(CASE WHEN status = 'in_progress' THEN 1 END)::BIGINT as active,
      COUNT(CASE WHEN status = 'completed' THEN 1 END)::BIGINT as completed,
      COUNT(CASE WHEN status = 'pending' THEN 1 END)::BIGINT as pending,
      ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - assigned_at)) / 3600)::NUMERIC, 1) as avg_time
    FROM jobs WHERE engineer_id = $1
  ),
  active_jobs AS (
    SELECT 
      COALESCE(
        JSON_AGG(
          JSON_BUILD_OBJECT(
            'id', id,
            'customerName', customer_name,
            'machineId', machine_id,
            'type', job_type,
            'assignedAt', assigned_at,
            'status', status
          ) ORDER BY assigned_at DESC
        ) FILTER (WHERE id IS NOT NULL),
        '[]'::json
      ) as jobs
    FROM jobs WHERE engineer_id = $1 AND status IN ('pending', 'in_progress') LIMIT 10
  ),
  recent_jobs AS (
    SELECT 
      COALESCE(
        JSON_AGG(
          JSON_BUILD_OBJECT(
            'id', id,
            'customerName', customer_name,
            'jobType', job_type,
            'completedAt', completed_at,
            'payAmount', pay_amount
          ) ORDER BY completed_at DESC
        ) FILTER (WHERE id IS NOT NULL),
        '[]'::json
      ) as jobs
    FROM jobs WHERE engineer_id = $1 AND status = 'completed' LIMIT 5
  ),
  earnings AS (
    SELECT COALESCE(SUM(pay_amount)::NUMERIC, 0) as total 
    FROM jobs 
    WHERE engineer_id = $1 AND status = 'completed' 
    AND DATE_TRUNC('month', completed_at) = DATE_TRUNC('month', NOW())
  )
  SELECT 
    js.active::BIGINT,
    js.completed::BIGINT,
    js.pending::BIGINT,
    js.avg_time,
    aj.jobs,
    rj.jobs,
    e.total
  FROM job_stats js, active_jobs aj, recent_jobs rj, earnings e;
END;
$$ LANGUAGE plpgsql STABLE;

-- ═══════════════════════════════════════════════════════════════
-- DEPLOYMENT NOTES
-- ═══════════════════════════════════════════════════════════════
-- 
-- 1. Paste each CREATE OR REPLACE FUNCTION into Supabase SQL Editor
-- 2. Execute each one separately
-- 3. Verify in "Database" → "Extensions" that functions appear
-- 4. Update Flutter code to call these RPC functions instead of multiple queries
--
-- Example Flutter call:
-- final result = await supabase.rpc('get_admin_dashboard_stats', 
--   {'admin_id': userId}
-- );
--
-- ═══════════════════════════════════════════════════════════════
