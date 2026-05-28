# iFrontiers Connect — v24b changes + workflow intro
**Session date:** 2026-05-24
**Focus:** Stale-badge bug, engineer self-check-in, schedule approval workflow,
nav-bar polish, splash redesign, app-icon scaling fix.

---

## 1. What changed this session

### New files (4)
| File | Purpose |
|------|---------|
| `lib/services/attendance_service.dart` | Engineer self check-in / check-out. Upserts today's `engineer_attendance` row, auto-flags `late` after 09:30. |
| `lib/widgets/engineer/engineer_checkin_card.dart` | Three-state card (not-checked-in / on-shift / shift-complete) wired into the engineer dashboard. |
| `lib/screens/engineering_admin/ea_pending_approvals_page.dart` | Approval queue for engineer-proposed schedules. Approve flips status → `scheduled` and notifies customer + engineer; Reject flips → `cancelled` and notifies engineer only. |
| `assets/app_icon_foreground.png` | Pre-padded 512×512 PNG (logo at 66% of canvas) used as the Android adaptive-icon foreground. |

### Modified files (7)
| File | Change |
|------|--------|
| `lib/screens/customer/home_page.dart` | Realtime ticket channel now listens to `all` events (insert + update + delete) and **propagates the fresh open-ticket count to `CustomerNavController`** so the badge clears when tickets close. |
| `lib/screens/customer/support_tickets_page.dart` | Active-status set now includes `waiting_customer`. On load, pushes openCount to the shell nav controller. |
| `lib/screens/engineer/engineer_create_schedule_page.dart` | Engineer-created schedules now start with `status='pending_approval'` and notify every admin/EA for review. Customer is **not** notified at this point. |
| `lib/screens/engineering_admin/engineering_admin_dashboard.dart` | More hub gets a "Pending Approvals" tile (`EaPendingApprovalsPage`). |
| `lib/screens/engineer/engineer_dashboard.dart` | `EngineerCheckinCard` inserted between stats row and quick actions. |
| `lib/widgets/customer/customer_nav_bar.dart` | Rebuilt with `_AnimatedNavItem`: pill grows with `easeOutBack`, icon scales 1.0→1.12, label slides up. Center FAB uses `_BounceTap`. |
| `lib/screens/splash_screen.dart` | Replaced multi-orb pattern with a single soft `RadialGradient` halo for a cleaner dashboard-style look. |
| `pubspec.yaml` | `flutter_launcher_icons` now uses a pre-padded foreground PNG so adaptive launchers stop oversizing the logo. Adds `remove_alpha_ios: true`. |

### Action required before rebuilding
```bash
cd C:\Users\sheha\Desktop\i_connect
flutter pub get
flutter pub run flutter_launcher_icons
flutter run
```

### Schema note
The approval workflow assumes `service_schedules` accepts `status='pending_approval'` and has `approved_by` / `approved_at` columns. If your DB has a CHECK constraint on `status`, run:
```sql
ALTER TABLE service_schedules
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;

-- If a CHECK constraint exists on status, drop and recreate with the new value:
ALTER TABLE service_schedules DROP CONSTRAINT IF EXISTS service_schedules_status_check;
ALTER TABLE service_schedules ADD CONSTRAINT service_schedules_status_check
  CHECK (status IN (
    'pending_approval','scheduled','confirmed','in_progress',
    'completed','cancelled','rescheduled'
  ));
```

---

## 2. Service Ticket Workflow — intro for users

This is a quick reference for how the three roles work together on a service ticket.

### Customer
1. Tap the centre support button → **Create Ticket**.
2. Pick the machine, describe the problem, attach photos.
3. Once submitted you'll see the ticket in **Support** with a status pill (New → Open → In Progress → Resolved → Closed).
4. When an engineer is dispatched you'll receive a push notification and can chat with them inside the ticket.
5. When the engineer marks the job **Complete**, the ticket moves to **Resolved**. You'll be asked to rate the service.
6. Approvals from staff are invisible — you only ever see scheduled visits as they happen.

### Engineering Admin (EA)
1. **Dashboard → Pending Approvals** to triage engineer-submitted schedules.
2. **Tickets tab** → assign engineers using the Dispatch sheet (multi-select + Lead engineer + date/time).
3. Send estimates to customers from the ticket chat (`+` → Send estimate). The customer approves/rejects inside the chat.
4. EA gets notifications when engineers update job status (Travelling → Arrived → Started → Completed).
5. EA can broadcast a push to engineers / one engineer / by specialization from the dashboard quick actions.

### Engineer
1. **Check In** from the dashboard card when arriving at the office (sets `engineer_attendance.status='present'` automatically).
2. Open assigned tickets, chat with the customer, attach progress photos.
3. **My Schedules** lists dispatched jobs. Tap the action button to advance state: Travelling → Arrived → Started → Paused → Completed.
4. To propose your own service or installation, use **+ New Schedule** — it will appear in the EA's Pending Approvals list and only goes live (and notifies the customer) once approved.
5. **Check Out** at end of shift records `check_out_time`.

### Admin (super)
1. Has full visibility into every ticket, inquiry, schedule, customer.
2. Excel export buttons on Customers / Inquiries / Tickets give downloadable .xlsx reports respecting current filters.
3. Approves marketer/engineer/EA staff via the More menu.
4. Receives notifications when an engineer submits a schedule for approval and can approve it from the same Pending Approvals page.

---

## 3. Deferred items (still on the user's wish list)

These were requested but are too large for one session and need dedicated follow-ups:

1. **Full i18n migration** — the strings in the ARB files are wired up, but a few hundred hard-coded English strings remain across screens. Migration plan: file-by-file, run `flutter gen-l10n`, replace `Text('Hello')` with `Text(S.of(context)!.hello)`. Estimated 2–3 sessions for full coverage.

2. **Font audit** — currently every panel inherits the default Roboto. Possible direction: pick a single brand font (Inter or Plus Jakarta Sans) via `google_fonts` and apply via `ThemeData.textTheme`. One session to do per panel correctly.

3. **Follow-up flow** — "include any engineer (arrived or not) when following up on a ticket". Needs a small new column `service_tickets.follow_up_user_id` plus a notification fan-out edge function. Half-session of work.

4. **Repository-level offline cache wiring** — `OfflineCacheService` + `SafeNetwork` exist; the next step is to wrap every repository read with `SafeNetwork.read()` so offline mode actually serves cached lists. About one session.

5. **EA installation Excel export + approvals coverage** — Schedule approvals are wired; installations could follow the same pattern. One small session.

6. **Notification settings per category** — let users mute schedule, approval, broadcast classes independently. Requires UI + small DB column. Half-session.

7. **End-to-end runtime test** — `flutter analyze` + manual click-through of every panel. Best done in an environment that can run the app.

---

*v24b closed. The next session can resume with any of the deferred items above.*
