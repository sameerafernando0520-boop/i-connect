-- ═══════════════════════════════════════════════════════════════
-- SUPABASE OPTIMIZATION: Database Indexes
-- ═══════════════════════════════════════════════════════════════
-- 
-- Indexes dramatically speed up the queries used by the app.
-- Without indexes, queries scan entire tables (O(n) performance).
-- With indexes, queries use index lookups (O(log n) performance).
--
-- Expected improvement: 50-200ms per query → 10-30ms per query
--
-- ═══════════════════════════════════════════════════════════════

-- User & Auth Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get user by ID"
CREATE INDEX IF NOT EXISTS idx_users_id ON users(id);

-- Speed up: "Get user by email"
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ─────────────────────────────────────────────────────────────
-- Service Tickets & Support Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get tickets by user/admin"
CREATE INDEX IF NOT EXISTS idx_service_tickets_user_created_at 
ON service_tickets(user_id, created_at DESC);

-- Speed up: "Get open tickets"
CREATE INDEX IF NOT EXISTS idx_service_tickets_status 
ON service_tickets(status) WHERE status != 'closed';

-- Speed up: "Get recent tickets"
CREATE INDEX IF NOT EXISTS idx_service_tickets_created_at 
ON service_tickets(created_at DESC);

-- ─────────────────────────────────────────────────────────────
-- Customer Machine Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get machines by customer"
CREATE INDEX IF NOT EXISTS idx_customer_machines_user_id 
ON customer_machines(user_id);

-- Speed up: "Get active machines"
CREATE INDEX IF NOT EXISTS idx_customer_machines_status 
ON customer_machines(status) WHERE status = 'active';

-- Speed up: "Get recent machine additions"
CREATE INDEX IF NOT EXISTS idx_customer_machines_created_at 
ON customer_machines(created_at DESC);

-- ─────────────────────────────────────────────────────────────
-- Activity Log Indexes

-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get user activity history"
CREATE INDEX IF NOT EXISTS idx_activity_log_user_created_at 
ON activity_log(user_id, created_at DESC);

-- Speed up: "Get recent activities"
CREATE INDEX IF NOT EXISTS idx_activity_log_created_at 
ON activity_log(created_at DESC);

-- ─────────────────────────────────────────────────────────────
-- Financial/Payment Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get customer payments"
CREATE INDEX IF NOT EXISTS idx_payments_user_id_created_at 
ON payments(user_id, created_at DESC);

-- Speed up: "Get pending invoices"
CREATE INDEX IF NOT EXISTS idx_invoices_status 
ON invoices(status) WHERE status = 'pending';

-- Speed up: "Get invoices by customer"
CREATE INDEX IF NOT EXISTS idx_invoices_user_id 
ON invoices(user_id);

-- Speed up: "Get installment plans for customer"
CREATE INDEX IF NOT EXISTS idx_installment_plans_user_id 
ON installment_plans(user_id);

-- Speed up: "Get installment payments"
CREATE INDEX IF NOT EXISTS idx_installment_payments_plan_id 
ON installment_payments(installment_plan_id);

-- ─────────────────────────────────────────────────────────────
-- Quotation Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get pending quotations"
CREATE INDEX IF NOT EXISTS idx_quotations_status 
ON quotations(status) WHERE status = 'pending';

-- Speed up: "Get quotations by customer"
CREATE INDEX IF NOT EXISTS idx_quotations_user_id 
ON quotations(user_id);

-- ─────────────────────────────────────────────────────────────
-- Referral Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get referrals by status"
CREATE INDEX IF NOT EXISTS idx_referrals_status 
ON referrals(status) WHERE status IN ('pending', 'active');

-- Speed up: "Get referrals by referrer"
CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id 
ON referrals(referrer_id);

-- ─────────────────────────────────────────────────────────────
-- Notification Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get user notifications"
CREATE INDEX IF NOT EXISTS idx_notifications_user_created_at 
ON notifications(user_id, created_at DESC);

-- Speed up: "Get unread notifications"
CREATE INDEX IF NOT EXISTS idx_notifications_read_status 
ON notifications(user_id, is_read) WHERE is_read = false;

-- ─────────────────────────────────────────────────────────────
-- Job & Engineer Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get engineer jobs"
CREATE INDEX IF NOT EXISTS idx_job_records_engineer_status 
ON job_records(engineer_id, status);

-- Speed up: "Get pending jobs"
CREATE INDEX IF NOT EXISTS idx_job_records_status 
ON job_records(status) WHERE status IN ('pending', 'assigned', 'in_progress');

-- Speed up: "Get completed jobs"
CREATE INDEX IF NOT EXISTS idx_job_records_created_at_completed 
ON job_records(created_at DESC) WHERE status = 'completed';

-- ─────────────────────────────────────────────────────────────
-- Maintenance & Scheduling Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get maintenance logs for machine"
CREATE INDEX IF NOT EXISTS idx_maintenance_logs_machine_id 
ON maintenance_logs(machine_id, created_at DESC);

-- Speed up: "Get service schedules"
CREATE INDEX IF NOT EXISTS idx_service_schedules_machine_id 
ON service_schedules(machine_id);

-- ─────────────────────────────────────────────────────────────
-- Marketer Indexes
-- ─────────────────────────────────────────────────────────────

-- Speed up: "Get marketer permissions"
CREATE INDEX IF NOT EXISTS idx_marketer_permissions_user_id 
ON marketer_permissions(user_id);

-- ═══════════════════════════════════════════════════════════════
-- DEPLOYMENT NOTES
-- ═══════════════════════════════════════════════════════════════
-- 
-- 1. Paste all CREATE INDEX statements into Supabase SQL Editor
-- 2. Execute them all at once (safe, idempotent with IF NOT EXISTS)
-- 3. Table should be updated instantly (indexes build in background)
-- 4. Verify in "Database" → "Indexes" that they appear
-- 5. Queries will now use these indexes automatically
--
-- Expected index creation time: <1 second per index on small tables
--
-- ═══════════════════════════════════════════════════════════════
