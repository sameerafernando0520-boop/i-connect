# i_connect — Bugs & Errors

> Full-codebase audit findings. Severity: 🔴 Critical · 🟠 High · 🟡 Medium · 🟢 Low  
> Status: `open` (unfixed as of 2026-06-20)

---

## Summary Table

| # | Sev | File | Issue | Status |
|---|-----|------|-------|--------|
| 1 | 🔴 | `config/supabase_config.dart` | Hardcoded fallback production URL — must never exist | open |
| 2 | 🔴 | `services/attendance_service.dart` | Late detection uses device local time — can be gamed by changing timezone | open |
| 3 | 🔴 | `screens/auth/signup_page.dart` | Points awarded BEFORE referral RPC; no rollback if referral fails | open |
| 4 | 🟠 | `utils/string_utils.dart` | `getInitials()` crashes on whitespace-only or empty string input | open |
| 5 | 🟠 | `services/attendance_service.dart` | `checkOut()` reads `check_in_time` without null guard — crashes if row exists but has no check-in | open |
| 6 | 🟠 | `services/points_service.dart` | `awardOnce()` race — two parallel calls both pass the SharedPreferences guard, awarding double points | open |
| 7 | 🟠 | `services/chat_attachment_service.dart` | No file-size validation before upload — can attempt multi-GB upload | open |
| 8 | 🟠 | `screens/engineer/engineer_my_schedules_page.dart` | `job_records` insert is fire-and-forget with no error feedback | open |
| 9 | 🟠 | `screens/engineer/engineer_schedule_page.dart` | Reschedule stores reason in `cancellation_reason` field — semantically wrong | open |
| 10 | 🟠 | `screens/engineer/engineer_schedule_page.dart` | Overdue/past schedules appear in the Today tab alongside current schedules | open |
| 11 | 🟠 | `screens/engineer/engineer_installation_detail_page.dart` | Completion dialog creates TextEditingControllers but only disposes them on confirm — memory leak on dismiss | open |
| 12 | 🟠 | `screens/engineer/engineer_profile_page.dart` | Storage path extraction (`_extractStoragePath`) breaks if CDN URL format changes | open |
| 13 | 🟠 | `screens/admin/admin_installations_page.dart` | Machine picker hard-limited to 300 rows — silently cuts off older machines | open |
| 14 | 🟠 | `screens/admin/admin_installments_page.dart` | `plan['paid_count']` and `plan['num_installments']` not null-checked before `.toDouble()` — crash on bad RPC data | open |
| 15 | 🟡 | `config/supabase_config.dart` | No SSL/certificate pinning — vulnerable to MITM on untrusted networks | open |
| 16 | 🟡 | `screens/splash_screen.dart` | Supabase domain hardcoded in DNS check — should read from `SupabaseConfig` | open |
| 17 | 🟡 | `services/connectivity_service.dart` | Supabase domain hardcoded in heartbeat (same issue as above) | open |
| 18 | 🟡 | `services/connectivity_service.dart` | No jitter on 15s heartbeat timer — all devices ping simultaneously | open |
| 19 | 🟡 | `providers/permissions_provider.dart` | No cache-invalidation: permission changes made server-side are invisible until restart | open |
| 20 | 🟡 | `screens/engineer/engineer_schedule_page.dart` | No `is_deleted` filter — soft-deleted schedules still appear in timeline | open |
| 21 | 🟡 | `screens/engineer/engineer_installation_detail_page.dart` | Completion report field has no required validation — empty report can be submitted | open |
| 22 | 🟡 | `screens/engineer/engineer_my_schedules_page.dart` | `start_time` falls back to completion time when engineer never pressed "Start" — misleading job record | open |
| 23 | 🟡 | `screens/engineer/engineer_profile_page.dart` | Logout spinner never dismisses if `signOut()` throws — user stuck on loading | open |
| 24 | 🟡 | `screens/customer/my_invoices_page.dart` | No pagination — fetches all invoices without `limit()` / `offset()` | open |
| 25 | 🟡 | `screens/admin/admin_hot_leads_page.dart` | No pagination — could load thousands of suggestions into memory | open |
| 26 | 🟡 | `screens/customer/customer_shell_page.dart` | All 5 tabs kept alive in `IndexedStack` — memory held for tabs user never visits | open |
| 27 | 🟡 | `screens/auth/login_page.dart` | Email regex too loose — allows malformed addresses (consecutive dots, missing TLD length) | open |
| 28 | 🟡 | `screens/auth/signup_page.dart` | Referral code field has no debounce — rapid typing triggers parallel DB validation calls | open |
| 29 | 🟡 | `screens/auth/reset_password_page.dart` | No specific handling for expired recovery session (1-hour TTL) — shows generic error | open |
| 30 | 🟡 | Multiple screens | `DateTime.now()` used for staleness/display comparisons instead of UTC — inconsistent with server data | open |
| 31 | 🟡 | `services/notification_service.dart` | `_storeNotification` silently swallows duplicate-insert errors — real errors masked | open |
| 32 | 🟡 | `screens/engineer/engineer_ticket_detail_page.dart` | `_startLocationStream()` can create duplicate subscriptions if called twice | open |
| 33 | 🟢 | `config/app_theme.dart` | Dead code — entire file unused; `ThemeProvider` is the live implementation | open |
| 34 | 🟢 | `providers/theme_provider.dart` | Workshop/Fusion styles marked "retired" in comments but code still branches on them | open |
| 35 | 🟢 | `screens/engineer/engineer_dashboard.dart` | TRI Engineering logo URL is hardcoded Cloudinary string — breaks if asset is moved | open |
| 36 | 🟢 | Multiple admin screens | Mixed color sources: some use `Brand.*`, some use `AdminColors.*`, some use `const Color(0xFF...)` | open |
| 37 | 🟢 | Multiple screens | Custom paint icons (`LaserIcon`, `CncIcon`) have no `Semantics` label — screen readers see nothing | open |
| 38 | 🟢 | Multiple screens | Status strings hardcoded in English — not routed through `S.of(context)` | open |
| 39 | 🟢 | `screens/engineer/engineer_installation_list_page.dart` | Filter logic mixes installation status with engineer's personal status — ambiguous which tab some items appear in | open |
| 40 | 🟢 | `screens/auth/login_page.dart` | "Too many attempts" message hardcoded — no exponential backoff guidance to user | open |

---

## 1. Security & Data Integrity

### BUG-01 🔴 — Hardcoded fallback Supabase URL
**File:** `lib/config/supabase_config.dart` ~line 33  
**Problem:** A production Supabase URL is hardcoded as a fallback if `SUPABASE_ANON_KEY` is missing from `.env`. This means a release build with a missing `.env` silently connects using stale credentials rather than failing loudly.  
**Risk:** Credentials baked into the binary; shipped builds may use unexpected backend.  
**Fix:** Remove the fallback entirely. Throw a clear exception if env vars are absent:
```dart
final url = dotenv.env['SUPABASE_URL'] ?? (throw Exception('SUPABASE_URL missing from .env'));
final key = dotenv.env['SUPABASE_ANON_KEY'] ?? (throw Exception('SUPABASE_ANON_KEY missing from .env'));
```

---

### BUG-02 🔴 — Attendance late-detection uses device local time
**File:** `lib/services/attendance_service.dart` ~line 56–58  
**Problem:** Whether an engineer is "late" (arrival ≥ 09:30) is determined by `DateTime.now()` (device local time). The stored timestamp is UTC. An engineer can change device timezone to appear on-time.  
**Fix:** Either derive the local time from the UTC timestamp using a fixed office timezone (`Asia/Colombo`, UTC+5:30) or move the late-detection logic to a DB function that uses `now() AT TIME ZONE 'Asia/Colombo'`.

---

### BUG-03 🔴 — Points awarded before referral RPC; no rollback
**File:** `lib/screens/auth/signup_page.dart` ~lines 164, 177  
**Problem:** `PointsService.awardOnce('signup_bonus')` fires before `apply_referral_code` RPC. If the referral RPC fails (network timeout, DB error), the user gets 100 sign-up points but the referrer gets nothing and the referral chain is broken. There is no compensation or retry.  
**Fix:** Either call both in a DB transaction (new RPC that atomically awards points + applies referral), or reverse the order and award points only after the referral is confirmed.

---

## 2. Crash Risks

### BUG-04 🟠 — `getInitials()` crashes on empty / whitespace input
**File:** `lib/utils/string_utils.dart` ~line 8  
**Problem:** `name.trim().split(' ')[0][0]` throws a `RangeError` if `name` is `""` or `"   "`.  
**Reproducer:** Pass an empty display name (e.g., user with no full_name set).  
**Fix:**
```dart
static String getInitials(String name) {
  final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
}
```

---

### BUG-05 🟠 — `checkOut()` doesn't guard against null `check_in_time`
**File:** `lib/services/attendance_service.dart` ~line 107  
**Problem:** `checkOut()` fetches today's attendance row and calls `DateTime.parse(row['check_in_time'])`. If the row exists but `check_in_time` is null (e.g., row was manually inserted by admin), this throws a `FormatException`.  
**Fix:** Add a null check:
```dart
final checkInStr = row['check_in_time'] as String?;
if (checkInStr == null) throw Exception('No check-in time recorded for today');
```

---

### BUG-06 🟠 — `awardOnce()` race condition
**File:** `lib/services/points_service.dart` ~lines 59–63  
**Problem:** Check-then-act is non-atomic. Two parallel calls (e.g., from two quick tab navigations) both see `prefs.getBool(key) == null`, both proceed to call `awardTo()`, and the user receives double points.  
**Fix:** Add a DB-side unique constraint on `(user_id, event_type)` in the points table, so the second insert is a no-op even if the client fires twice.

---

### BUG-11 🟠 — TextEditingController memory leak in completion dialog
**File:** `lib/screens/engineer/engineer_installation_detail_page.dart` ~lines 186–190  
**Problem:** `reportCtrl` and `notesCtrl` are created inside `showDialog` but `dispose()` is only called when the user confirms (`ok == true`). Dismissing the dialog (back button, tap outside) leaks the controllers.  
**Fix:** Use a `StatefulWidget` dialog or dispose in `finally`:
```dart
final reportCtrl = TextEditingController();
try {
  final ok = await showDialog(...);
  if (ok == true) { /* submit */ }
} finally {
  reportCtrl.dispose();
}
```

---

### BUG-14 🟠 — Null crash on installment plan numeric fields
**File:** `lib/screens/admin/admin_installments_page.dart` ~lines 231, 340  
**Problem:** `(plan['paid_count'] as num).toDouble()` throws if the RPC returns a null for either field (e.g., plan with no payments recorded yet).  
**Fix:**
```dart
final paid = (plan['paid_count'] as num? ?? 0).toDouble();
final total = (plan['num_installments'] as num? ?? 1).toDouble();
```

---

## 3. Logic Errors

### BUG-09 🟠 — Reschedule reason stored in wrong column
**File:** `lib/screens/engineer/engineer_schedule_page.dart` ~lines 916–917  
**Problem:** When an engineer reschedules, the reason is stored as `"Rescheduled: {reason}"` in the `cancellation_reason` column. This causes confusion for admins who read the column expecting a cancellation reason, and contaminates analytics that filter on `cancellation_reason IS NOT NULL`.  
**Fix:** Add a dedicated `reschedule_reason` column in the `service_schedules` table, or store the action type in a separate `schedule_events` log table.

---

### BUG-10 🟠 — Past overdue schedules appear in Today tab
**File:** `lib/screens/engineer/engineer_schedule_page.dart` ~lines 252–253  
**Problem:** The Today tab shows schedules where `date == today`. Past uncompleted schedules from earlier days also match the filter because the date comparison is inclusive of "same day but past midnight". Engineers see stale yesterday-or-earlier cards mixed with today's work.  
**Fix:** Add a secondary filter: `scheduledDate.isAtSameMomentAs(today) || !schedule.isCompleted`.  
Actually the correct fix is to show overdue items in their own "Overdue" section, not in the Today tab.

---

### BUG-08 🟠 — `job_records` insert is silent fire-and-forget
**File:** `lib/screens/engineer/engineer_my_schedules_page.dart` ~lines 181–206  
**Problem:** The DB insert for `job_records` is not awaited and has a bare `catch (_)` that logs nothing. If the insert fails (column type mismatch, RLS violation, network drop), the ticket status updates but no job record exists — silently corrupting the audit trail.  
**Fix:** Await the insert, catch specific exceptions, and show a snackbar or retry prompt if it fails.

---

### BUG-22 🟡 — `start_time` on job record uses completion time when engineer never started
**File:** `lib/screens/engineer/engineer_my_schedules_page.dart` ~line 191  
**Problem:** `start_time: assignment['started_at'] ?? now` — if the engineer skips pressing "Start work" and goes straight to "Complete", `started_at` is null, so start_time and end_time are identical. Job duration = 0 minutes in all reports.  
**Fix:** Make "Start work" mandatory before "Complete" is shown, or flag in the record that start_time is estimated.

---

## 4. Missing Validation

### BUG-07 🟠 — No file-size check before chat attachment upload
**File:** `lib/services/chat_attachment_service.dart` ~line 44  
**Problem:** `uploadBytes(bytes, ...)` sends the file to Supabase Storage without checking size first. A user could accidentally attach a 500 MB video.  
**Fix:** Call `UploadValidator.validateChatAttachment(bytes, mimeType)` (already exists in `upload_validator.dart`) before calling `uploadBytes`.

---

### BUG-21 🟡 — Completion report has no required validation
**File:** `lib/screens/engineer/engineer_installation_detail_page.dart` ~line 262  
**Problem:** The completion dialog sends the RPC even if the report text field is empty. An empty completion report provides no audit trail.  
**Fix:**
```dart
if (reportCtrl.text.trim().isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter a completion report')));
  return;
}
```

---

### BUG-28 🟡 — Referral code field has no debounce
**File:** `lib/screens/auth/signup_page.dart` ~lines 80–128  
**Problem:** Every keystroke in the referral code field triggers a Supabase RPC call. Rapid typing (e.g., pasting a code character-by-character) fires 10+ queries in parallel. The last-to-arrive response wins, which could show a stale "invalid" state after the correct response already arrived.  
**Fix:** Add a 600ms debounce timer that cancels the previous call before firing a new one.

---

## 5. Performance Issues

### BUG-13 🟠 — Machine picker hard-limited to 300 rows
**File:** `lib/screens/admin/admin_installations_page.dart` ~line 137  
**Problem:** `machine_catalog.select().limit(300)` silently drops machines beyond row 300. As catalog grows, admins can't assign newer machines.  
**Fix:** Replace with a search-as-you-type input that queries by name (`ilike`) rather than loading all rows upfront.

---

### BUG-24 🟡 — Invoice list has no pagination
**File:** `lib/screens/customer/my_invoices_page.dart`  
**Problem:** `invoices.select().eq('customer_id', uid)` — no `limit()`. High-volume customers could have hundreds of invoices loaded into a single list.  
**Fix:** Use cursor pagination: `range(0, 19)` initially, load next page on scroll.

---

### BUG-25 🟡 — Hot leads list has no pagination
**File:** `lib/screens/admin/admin_hot_leads_page.dart`  
**Problem:** Same issue — `machine_suggestions` query has no `limit()`. Could return thousands of rows.  
**Fix:** Add `limit(50)` with a "load more" button, or implement infinite scroll.

---

### BUG-26 🟡 — All 5 customer tabs kept alive in `IndexedStack`
**File:** `lib/screens/customer/customer_shell_page.dart`  
**Problem:** `IndexedStack` keeps all 5 tab pages in the widget tree at all times. Pages that are never visited still consume memory for their state and caches.  
**Fix:** For rarely used tabs, consider lazy initialisation with a late flag, or use `AutomaticKeepAliveClientMixin` only on the Home tab.

---

## 6. UTC / Timezone Issues

### BUG-30 🟡 — `DateTime.now()` used for server-relative comparisons
**Files:** `admin_dashboard.dart`, `admin_hot_leads_page.dart`, `home_page.dart`, and others  
**Problem:** `DateTime.now()` returns device local time. When compared to server-stored UTC timestamps (e.g., "is this invoice overdue?", "how stale is this lead?"), the result drifts by ±5:30 hours on Sri Lanka devices.  
**Fix:** Always compare UTC to UTC:
```dart
// When comparing against a server timestamp:
final now = DateTime.now().toUtc();
final serverTs = DateTime.parse(row['created_at']).toUtc();
final diff = now.difference(serverTs);
```

---

## 7. Dead / Conflicting Code

### BUG-33 🟢 — `app_theme.dart` is entirely unused
**File:** `lib/config/app_theme.dart`  
**Problem:** The file defines an `AppTheme` class that is never imported or instantiated anywhere. `ThemeProvider` (`providers/theme_provider.dart`) is the live implementation. Having both creates confusion about which one to use.  
**Fix:** Delete `lib/config/app_theme.dart`.

---

### BUG-34 🟢 — Workshop/Fusion styles marked "retired" but still active in code
**File:** `lib/providers/theme_provider.dart` ~lines 90–91  
**Problem:** Comments say Workshop and Fusion dark styles are "retired" but the code still branches on `DarkStyle.workshop` and `DarkStyle.fusion`. This is confusing for new developers.  
**Fix:** Either remove the branches and simplify to Navy-only, or remove the "retired" comment.

---

## 8. UX & Accessibility Gaps

### BUG-37 🟢 — Custom paint icons have no accessibility labels
**Files:** `home_page.dart` (LaserIcon, CncIcon), others with `CustomPaint`  
**Problem:** Screen readers on Android/iOS see nothing for these icons.  
**Fix:** Wrap in `Semantics`:
```dart
Semantics(label: 'Laser machine category', child: LaserIcon(...))
```

---

### BUG-38 🟢 — Status strings hardcoded in English
**Files:** `admin_invoice_detail_page.dart`, `admin_installations_page.dart`, multiple screens  
**Problem:** Status labels (`'draft'`, `'in_progress'`, `'completed'`, etc.) displayed in UI are raw DB strings, never localised.  
**Fix:** Add a `statusLabel(String status, S s)` helper in `string_utils.dart` that maps statuses to localised strings.

---

### BUG-40 🟢 — No rate-limit backoff on login
**File:** `lib/screens/auth/login_page.dart` ~line 220  
**Problem:** After too many failed login attempts, Supabase returns a 429. The app shows a hardcoded message but gives no indication of how long to wait or any backoff mechanism.  
**Fix:** Parse the `Retry-After` header from Supabase's error response (if present) and show a countdown, or disable the button for 30 seconds after 5 failures.

---

## Hardcoded Values That Should Be Constants

| Location | Hardcoded Value | Should Become |
|----------|----------------|---------------|
| `splash_screen.dart` | `'mgfehxoampnafcyriqzt.supabase.co'` | `SupabaseConfig.host` |
| `connectivity_service.dart` | `'mgfehxoampnafcyriqzt.supabase.co'` | `SupabaseConfig.host` |
| `attendance_service.dart` | `TimeOfDay(hour: 9, minute: 30)` — late cutoff | Named constant `kLateThreshold` |
| `engineer_dashboard.dart` | Cloudinary TRI logo URL | Config constant or asset |
| `admin_installations_page.dart` | `limit(300)` on machine picker | Named constant `kMachinePickerLimit` |
| `my_invoices_page.dart` | 10-second staleness threshold | Named constant `kInvoiceStalenessMs` |
