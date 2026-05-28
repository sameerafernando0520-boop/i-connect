-- ============================================================
-- Migration: create the missing notification_settings table
-- ============================================================
--
-- Root cause: every signup (engineer invite, customer self-signup,
-- the edge function's inviteUserByEmail, raw /auth/v1/signup) was
-- failing with HTTP 500. The auth log surfaced:
--
--   "500: Database error saving new user"
--   ERROR: relation "notification_settings" does not exist
--   (SQLSTATE 42P01)  path: /signup
--
-- The cascade is: auth.users INSERT fires on_auth_user_created ->
-- handle_new_user() -> public.users INSERT, which fires
-- trigger_create_notification_settings -> create_default_notification_settings()
-- -> INSERT INTO notification_settings. Because that table did not
-- exist, the entire transaction aborted and Supabase Auth rolled back
-- the new user, causing the engineer-add flow (and any future
-- customer self-signup) to fail.
--
-- Columns mirror lib/screens/customer/notification_settings_page.dart
-- exactly, so the existing settings UI works without code changes.

CREATE TABLE IF NOT EXISTS public.notification_settings (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  push_enabled            boolean NOT NULL DEFAULT true,
  service_reminders       boolean NOT NULL DEFAULT true,
  product_updates         boolean NOT NULL DEFAULT true,
  ticket_updates          boolean NOT NULL DEFAULT true,
  new_messages            boolean NOT NULL DEFAULT true,
  promotions              boolean NOT NULL DEFAULT true,
  system_alerts           boolean NOT NULL DEFAULT true,
  email_enabled           boolean NOT NULL DEFAULT false,
  email_service_reminders boolean NOT NULL DEFAULT false,
  quiet_hours_enabled     boolean NOT NULL DEFAULT false,
  quiet_hours_start       text    NOT NULL DEFAULT '22:00',
  quiet_hours_end         text    NOT NULL DEFAULT '07:00',
  sound_enabled           boolean NOT NULL DEFAULT true,
  vibration_enabled       boolean NOT NULL DEFAULT true,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.notification_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own notification settings"
  ON public.notification_settings;
CREATE POLICY "Users manage own notification settings"
  ON public.notification_settings
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- The trigger inserts the default row as part of the auth.users ->
-- public.users cascade. Permit those inserts unconditionally; the FK
-- to public.users (ON DELETE CASCADE) keeps things tidy.
DROP POLICY IF EXISTS "Trigger insert default settings"
  ON public.notification_settings;
CREATE POLICY "Trigger insert default settings"
  ON public.notification_settings
  FOR INSERT
  TO public
  WITH CHECK (true);

-- Backfill: every existing user gets a row so the settings page works.
INSERT INTO public.notification_settings (user_id)
SELECT u.id FROM public.users u
WHERE NOT EXISTS (
  SELECT 1 FROM public.notification_settings s WHERE s.user_id = u.id
);
