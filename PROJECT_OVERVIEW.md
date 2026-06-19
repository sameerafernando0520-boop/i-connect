# i_connect — Project Overview & Instructions

> Living reference for the iFrontiers Connect Flutter + Supabase app.  
> Update this file whenever you add a screen, role, service, or RPC.

---

## 1. App Identity

| Field | Value |
|-------|-------|
| App name | iFrontiers Connect (i_connect) |
| Client | iFrontiers Pvt Ltd — Sri Lanka industrial machines vendor |
| Flutter SDK | ≥ 3.0.0 (tested on 3.44.x) |
| Dart SDK | ≥ 3.0.0 |
| Version | 1.0.0+1 |
| Backend | Supabase (PostgreSQL + Realtime + Storage + Edge Functions) |
| Push | Firebase Cloud Messaging (firebase_messaging ^16) |
| Crash | Firebase Crashlytics (firebase_crashlytics ^5) |

---

## 2. Supabase Project

| Field | Value |
|-------|-------|
| Project ID | `mgfehxoampnafcyriqzt` |
| Region | `ap-south-1` (Mumbai) |
| Dashboard | https://supabase.com/dashboard/project/mgfehxoampnafcyriqzt |

**The same Supabase org contains a second unrelated project "Tri Smart" — never touch it.**

### UTC Timestamp Convention

All `timestamptz` columns must receive UTC strings:

```dart
// CORRECT
DateTime.now().toUtc().toIso8601String()   // → "2025-06-20T08:30:00.000Z"

// WRONG — Sri Lanka +5:30 without offset is read as UTC by the DB
DateTime.now().toIso8601String()            // → "2025-06-20T14:00:00.000" (ambiguous)
```

Date-only values (no time component) use local date strings:
```dart
DateTime.now().toIso8601String().substring(0, 10)  // → "2025-06-20"
```

### Schema Ground Truth

**Always fetch live schema before trusting column names.** The repo has had "hallucinated column name" bugs (e.g. app read `duration_days` while the real column is `total_days` on `engineer_leaves`). Use Supabase dashboard → Table Editor to verify.

---

## 3. Role System

Five roles live in `users.role`:

| Role | Description | Login Method |
|------|-------------|-------------|
| `customer` | Default. Customers who buy/register machines. | Email + password via Supabase Auth |
| `admin` | Full platform admin. | Email + password |
| `marketing_admin` | Marketing portal with permission-gated features. | Username → `@marketing.iconnect.lk` |
| `engineering_admin` | Engineering operations portal. | Username → `@engineering.iconnect.lk` |
| `engineer` | Field technician. | Username → `@engineer.iconnect.lk` |

### Staff Login (Synthetic Emails)

Staff log in with a plain **username** (no `@`). `login_page.dart` auto-tries three domains in order until one succeeds:
```
<username>@marketing.iconnect.lk
<username>@engineering.iconnect.lk
<username>@engineer.iconnect.lk
```

Staff accounts are **created server-side only** via Supabase Edge Functions:
- `create-engineer` — creates engineer account
- `create-marketer` — creates marketing admin account
- `create-engineering-admin` — creates engineering admin account

Never create staff via `supabase.auth.signUp()` on the client.

### Role-Based Navigation (`main.dart → _navigateByRole`)

```
admin             → AdminDashboard
engineering_admin → EngineeringAdminDashboard
engineer          → EngineerDashboard
marketing_admin   → MarketingAdminDashboard
customer          → CustomerShellPage (tab shell)
```

The auth state listener in `main.dart` fires on every `onAuthStateChange` event and re-routes via `_navigateByRole`.

### Marketing Admin Permissions

`marketing_admin` feature access is gated by a per-user row in `marketer_permissions` (9 boolean columns). These are loaded into `PermissionsProvider` on login and cached in memory. RLS policies named `marketer_*` enforce the same flags server-side.

---

## 4. Authentication Flows

### Customer Sign-Up (2 steps)
1. **Step 0** — Full name, company, phone, email, province/district, optional referral code
2. **Step 1** — Password + confirm password (live strength indicator)
- Referral code is validated in real-time against `apply_referral_code` RPC
- On account creation: `PointsService.awardOnce('signup_bonus')` awards 100 points
- Referral applied via RPC if code is valid

### Login
- `supabase.auth.signInWithPassword(email, password)`
- Staff: tries 3 synthetic email domains before showing "invalid" error
- Error messages distinguish: wrong password / unconfirmed email / too many attempts / network error

### Password Reset (Deep Link)
1. User requests reset on login screen → Supabase sends email with magic link
2. Link opens app via deep link scheme `iconnect://`
3. `main.dart` detects `passwordRecovery` auth event → pushes `ResetPasswordPage`
4. User enters new password → `supabase.auth.updateUser(password:)` → auto-logout → back to login

### Session Expiry
If `tokenRefreshed` event returns an error, user is force-signed-out and sent to `LoginPage`.

---

## 5. App Directory Structure

```
lib/
├── main.dart                    # Entry point, init, auth listener, routing
├── config/
│   ├── brand_colors.dart        # Entire color system (Brand, HeroPalette, StatusColors)
│   ├── admin_theme.dart         # Admin-portal colors, dimensions, text styles
│   ├── app_theme.dart           # LEGACY — not used; superseded by ThemeProvider
│   ├── sales_stage_config.dart  # CRM pipeline stage definitions
│   └── supabase_config.dart     # Supabase client singleton, env-var loading
├── l10n/
│   ├── s.dart                   # Re-export shim for AppLocalizations
│   ├── app_localizations.dart   # Generated (flutter gen-l10n)
│   ├── app_localizations_en.dart
│   ├── app_localizations_si.dart
│   └── app_localizations_ta.dart
├── models/
│   ├── chat_message.dart        # ChatMessage data class
│   ├── dashboard_stats.dart     # DashboardStats (admin KPIs)
│   ├── inquiry_detail.dart      # InquiryDetail with nested models
│   └── ticket_detail.dart       # TicketDetail, TicketUser, TicketMachine
├── providers/
│   ├── locale_provider.dart     # Per-user language (en/si/ta) via shared_prefs
│   ├── permissions_provider.dart# Marketing admin feature flags
│   └── theme_provider.dart      # Dark mode, dark style, design (NavyGlow/Workshop)
├── repositories/
│   ├── admin_dashboard_repository.dart    # Admin KPI queries
│   ├── engineering_admin_repository.dart  # EA dashboard queries
│   ├── inquiry_detail_repository.dart     # Inquiry + chat queries
│   └── ticket_detail_repository.dart      # Ticket + chat queries
├── screens/
│   ├── auth/                    # Login, Signup, ResetPassword, Splash
│   ├── admin/                   # 37 admin screens
│   ├── customer/                # 24 customer screens
│   ├── engineer/                # 9 engineer screens
│   ├── engineering_admin/       # 23 engineering admin screens
│   └── marketing/               # 13 marketing admin screens
├── services/
│   ├── attendance_service.dart  # Engineer check-in/out
│   ├── chat_attachment_service.dart # File pick + Supabase Storage upload
│   ├── connectivity_service.dart    # Online/offline ValueNotifier + heartbeat
│   ├── export_service.dart      # CSV generation + share_plus
│   ├── notification_service.dart    # FCM token, topic subs, message handling
│   ├── offline_cache_service.dart   # SharedPreferences JSON envelope cache
│   ├── points_service.dart      # Gamification point awards (fire-and-forget)
│   └── safe_network.dart        # Supabase call wrapper with cache fallback
├── utils/
│   ├── app_logger.dart          # debug/info/warn/error → Crashlytics in release
│   ├── machine_image_helper.dart# Image URL fallback chain for machine catalog
│   ├── sri_lanka_locations.dart # 9 provinces + 25 districts static data
│   ├── string_utils.dart        # getInitials(), truncate()
│   ├── time_utils.dart          # Relative timestamps, greetings, date separators
│   └── upload_validator.dart    # MIME sniff + size caps for uploads
└── widgets/
    ├── admin/                   # Admin-specific widgets (inquiry cards, chat bubbles, sheets)
    ├── common/                  # Shared widgets (offline banner, nav badge, language sheet)
    ├── customer/                # Customer nav bar, carousel, payment sheet
    ├── ds/ds_widgets.dart       # Design-system component library (DsPageHeader, etc.)
    ├── engineer/                # Engineer check-in card
    └── engineering_admin/       # EA engineer-assigned card
```

---

## 6. Screen Catalogue

### Auth Screens (`lib/screens/auth/`)
| File | Purpose |
|------|---------|
| `splash_screen.dart` | Animated 2.2s splash with auth check + role routing |
| `login_page.dart` | Email/username login with staff domain auto-trial |
| `signup_page.dart` | 2-step customer registration with referral code |
| `reset_password_page.dart` | Password update after deep-link recovery |

### Customer Screens (`lib/screens/customer/`)
| File | Purpose |
|------|---------|
| `customer_shell_page.dart` | 5-tab IndexedStack root shell |
| `home_page.dart` | Dashboard: tier progress, quick stats, activity feed |
| `catalog_page.dart` | Machine catalog browse |
| `machine_detail_page.dart` | Public machine detail (from catalog) |
| `my_machines_page.dart` | Customer's registered machines |
| `my_machine_detail_page.dart` | Detail for a registered machine |
| `register_machine_page.dart` | Register a purchased machine |
| `order_form_page.dart` | New machine order/inquiry submission |
| `request_service_page.dart` | Service request form |
| `support_tickets_page.dart` | List of customer's support tickets |
| `ticket_detail_page.dart` | Ticket detail with chat |
| `create_support_ticket_page.dart` | New support ticket form |
| `my_quotations_page.dart` | Customer's received quotations |
| `my_invoices_page.dart` | Customer's invoices |
| `customer_invoice_detail_page.dart` | Invoice detail with payment history |
| `customer_installments_page.dart` | Installment plan overview |
| `my_schedule_page.dart` | Upcoming service schedules |
| `knowledge_base_page.dart` | FAQ / help article list |
| `article_detail_page.dart` | Full KB article |
| `notification_list_page.dart` | In-app notification inbox |
| `notification_settings_page.dart` | FCM topic opt-in/out |
| `referral_page.dart` | Referral code share + history |
| `points_history_page.dart` | Loyalty points ledger |
| `profile_page.dart` | Customer profile edit + app settings |

### Admin Screens (`lib/screens/admin/`)
| File | Purpose |
|------|---------|
| `admin_dashboard.dart` | Main admin hub with KPI cards + realtime activity |
| `admin_more_page.dart` | Navigation hub to all sub-sections |
| `admin_settings_page.dart` | Admin account settings |
| `inquiry_management_page.dart` | CRM inquiry pipeline list |
| `inquiry_detail_page.dart` | Inquiry detail + sales pipeline stepper |
| `inquiry_chat_page.dart` | Chat thread for inquiry |
| `admin_hot_leads_page.dart` | High-readiness machine suggestions |
| `customers_management_page.dart` | Customer list + search |
| `customer_detail_page.dart` | Customer profile + activity |
| `machines_management_page.dart` | Machine catalog management |
| `admin_register_machine_page.dart` | Register machine for customer |
| `tickets_management_page.dart` | All support tickets |
| `admin_ticket_detail_page.dart` | Ticket detail + internal notes |
| `service_calendar_page.dart` | Service schedule calendar |
| `create_schedule_page.dart` | Create service schedule |
| `schedule_detail_page.dart` | Schedule detail + engineer assignment |
| `admin_installations_page.dart` | Machine installation job list |
| `admin_installation_detail_page.dart` | Installation job detail |
| `admin_installments_page.dart` | Installment plan overview |
| `installment_detail_page.dart` | Single installment plan detail |
| `quotation_management_page.dart` | Quotation list |
| `create_quotation_page.dart` | New quotation builder |
| `admin_quotation_detail_page.dart` | Quotation detail + PDF/email actions |
| `payment_dashboard_page.dart` | Payment overview + revenue charts |
| `create_invoice_page.dart` | New invoice builder |
| `admin_invoice_detail_page.dart` | Invoice detail + payment recording |
| `analytics_dashboard.dart` | Business analytics with fl_chart graphs |
| `broadcast_notifications.dart` | Push notification broadcast to segments |
| `referral_management_page.dart` | Referral tracking |
| `referral_rules_page.dart` | Referral points rule editor |
| `tier_management_page.dart` | Customer loyalty tier editor |
| `admin_knowledge_base_page.dart` | KB article list |
| `admin_knowledge_base_form_page.dart` | KB article create/edit |
| `engineer_management_page.dart` | Engineer account list |
| `marketer_management_page.dart` | Marketer account list |
| `engineering_admin_management_page.dart` | Engineering admin list |
| `create_marketer_page.dart` | Create marketing admin account |
| `create_engineering_admin_page.dart` | Create engineering admin account |

### Engineer Screens (`lib/screens/engineer/`)
| File | Purpose |
|------|---------|
| `engineer_dashboard.dart` | Engineer home with ticket/schedule/installation counts |
| `engineer_ticket_list_page.dart` | Assigned tickets with multi-filter |
| `engineer_ticket_detail_page.dart` | Ticket detail with realtime chat + location |
| `engineer_schedule_page.dart` | Calendar + timeline of service schedules |
| `engineer_my_schedules_page.dart` | Today/upcoming schedules with check-in workflow |
| `engineer_create_schedule_page.dart` | Create schedule (pending_approval) |
| `engineer_installation_list_page.dart` | Installation assignments |
| `engineer_installation_detail_page.dart` | Installation lifecycle + completion |
| `engineer_profile_page.dart` | Profile edit + specializations + performance |

### Engineering Admin Screens (`lib/screens/engineering_admin/`)
| File | Purpose |
|------|---------|
| `engineering_admin_dashboard.dart` | EA hub with KPI overview |
| `ea_engineer_list_page.dart` | All engineers list |
| `ea_engineer_detail_page.dart` | Engineer profile + performance |
| `ea_create_engineer_page.dart` | Create engineer account |
| `ea_ticket_list_page.dart` | All service tickets |
| `ea_ticket_detail_page.dart` | Ticket detail |
| `ea_ticket_chat_page.dart` | Ticket chat thread |
| `ea_schedule_page.dart` | Schedule dispatch view |
| `ea_installation_page.dart` | Installation jobs list |
| `ea_installation_detail_page.dart` | Installation detail + engineer assignment |
| `ea_assign_engineers_sheet.dart` | Bottom sheet: assign engineers to installation |
| `ea_job_records_page.dart` | Job record history |
| `ea_job_record_form_page.dart` | Create/edit job record |
| `ea_job_record_detail_page.dart` | Job record detail |
| `ea_leave_management_page.dart` | Engineer leave requests |
| `ea_leave_detail_page.dart` | Leave request detail + approve/reject |
| `ea_attendance_page.dart` | Engineer attendance log |
| `ea_pending_approvals_page.dart` | Pending schedule approvals |
| `ea_performance_dashboard.dart` | Engineer KPI dashboard |
| `ea_reports_page.dart` | Engineering reports |
| `ea_broadcast_page.dart` | Push notifications to engineers |
| `ea_notifications_page.dart` | EA notification inbox |
| `ea_profile_page.dart` | EA profile edit |
| `ea_settings_page.dart` | EA app settings |

### Marketing Admin Screens (`lib/screens/marketing/`)
| File | Purpose |
|------|---------|
| `marketing_admin_dashboard.dart` | Marketing hub (feature-permission gated) |
| `ma_home_page.dart` | Marketing home |
| `ma_analytics_page.dart` | Campaign analytics |
| `ma_banners_page.dart` | Hero banner management |
| `ma_broadcast_page.dart` | Customer push notifications |
| `ma_catalog_page.dart` | Product catalog edit |
| `ma_customers_page.dart` | Customer CRM view |
| `ma_knowledge_base_page.dart` | KB article management |
| `ma_points_page.dart` | Loyalty points management |
| `ma_referral_page.dart` | Referral campaign view |
| `ma_tiers_page.dart` | Customer tier management |
| `ma_profile_page.dart` | Marketer profile |

---

## 7. Services

| Service | Singleton | Purpose | Key Methods |
|---------|-----------|---------|-------------|
| `ConnectivityService` | Yes | Online/offline ValueNotifier + 15s heartbeat DNS ping | `initialize()`, `isOnline`, `markOnline()`, `markOffline()` |
| `NotificationService` | Yes | FCM token registration, topic subscriptions, message routing | `initialize()`, `onLogin()`, `onLogout()`, `updateSetting()` |
| `OfflineCacheService` | No (static) | SharedPreferences JSON envelope with TTL advisory | `write()`, `read<T>()`, `isStale()`, `invalidate()`, `clearAll()` |
| `SafeNetwork` | No (static) | Supabase call wrapper — falls back to cache on network error | `read<T>()`, `write<T>()` |
| `AttendanceService` | No (static) | Engineer daily check-in/out to `attendance` table | `checkIn()`, `checkOut()`, `todayRecord()` |
| `ChatAttachmentService` | No (static) | File picker + upload to `chat-attachments` bucket | `pickImage()`, `pickDocument()`, `uploadBytes()`, `currentLocation()` |
| `ExportService` | No (static) | RFC-4180 CSV generation + share_plus | `exportCustomers()`, `exportInquiries()`, `exportTickets()` |
| `PointsService` | No (static) | Fire-and-forget gamification points via RPCs | `awardOnce()`, `articleRead()`, `machinePurchase()` |

---

## 8. Repositories

| Repository | Purpose |
|------------|---------|
| `AdminDashboardRepository` | Batched KPI queries for admin dashboard |
| `EngineeringAdminRepository` | EA dashboard queries (engineer stats, leave counts, attendance) |
| `InquiryDetailRepository` | Inquiry data + chat message CRUD |
| `TicketDetailRepository` | Ticket data + chat messages + read-status updates |

---

## 9. State Management

The app uses `provider` only — no Riverpod or Bloc.

Three providers are registered at the `MultiProvider` root in `main.dart`:

| Provider | Type | When Loaded |
|----------|------|-------------|
| `ThemeProvider` | `ChangeNotifier` | Lazy (first access) |
| `LocaleProvider` | `ChangeNotifier` | On login (`loadForUser(uid)`) |
| `PermissionsProvider` | `ChangeNotifier` | On login (marketing_admin only) |

Both `LocaleProvider` and `PermissionsProvider` are cleared on logout.

---

## 10. Design System

### Color Sources (single source of truth)

- **`brand_colors.dart`** — everything color-related:
  - `Brand.*` — static helpers (canvas, surface, darkCard, royalBlue, etc.)
  - `BrandColors.*` — raw color constants
  - `HeroPalette` — per-design gradient + frosted overlay
  - `DarkPalette` — dark-mode icon/fill colors
  - `StatusColors` — semantic colors (open→blue, in_progress→amber, etc.)
  - `Brand.r(context)` — radius helper (Workshop uses ~35% tighter radii)

- **`admin_theme.dart`** — admin/staff portal constants:
  - `AdminColors.*` — theme-aware card/bg/border getters
  - `AdminDimens.*` — cardRadius, pagePadding, etc.
  - `AdminStyles.*` — text styles (pageTitle, sectionHeading, body, tag)

- **`widgets/ds/ds_widgets.dart`** — design-system component library:
  - `DsPageHeader` — standardised page header (used by almost all screens)
  - Other reusable UI components

- **`widgets/common/theme_style_sheet.dart`** — additional shared styles

### Design Variants

Two structural designs, toggled in `ThemeProvider`:
- **NavyGlow** (default) — navy backgrounds, larger radii, glow effects
- **Workshop** — navy/slate hybrid, tighter radii (~35% less via `Brand.r()`)

Two dark styles (NavyGlow only):
- **Navy** — deep navy backgrounds
- **Workshop** / **Fusion** — currently marked "retired" in comments but still supported in code

### Key Design Rule

Always use `Brand.r(context)` or `Brand.r(isDark)` for corner radii — never hardcode `BorderRadius.circular(12)`.

---

## 11. Offline & Connectivity

```
ConnectivityService.isOnline (ValueNotifier<bool>)
    ↓ listened by
OfflineBanner widget (shown at top of screen when offline)
SafeNetwork.read<T>()
    ├─ online  → fetch from Supabase → write to OfflineCacheService → return data
    └─ offline → read from OfflineCacheService → return stale data + mark offline
```

**Heartbeat:** `ConnectivityService` pings `mgfehxoampnafcyriqzt.supabase.co` every 15s via DNS lookup to detect captive portals (Wi-Fi that shows connectivity but has no internet).

---

## 12. Push Notifications

**Stack:** Firebase Cloud Messaging + Supabase `notifications` table for in-app inbox.

| Event | What Happens |
|-------|-------------|
| App cold-start | `NotificationService.initialize()` → get FCM token → store in `fcm_tokens` table |
| Login | `NotificationService.onLogin()` → retries init if failed at cold-start |
| Role assigned | Subscribe to role topic (`all_users` + `customers`/`engineers`/`admins`) |
| Token refresh | Deactivate old token, store new token |
| Foreground message | Stored to `notifications` table, in-app snackbar shown |
| Background tap | Deep link to relevant screen via `navigatorKey` |
| Logout | `NotificationService.onLogout()` → deactivate token in `fcm_tokens` |

**Test notification** available via `NotificationService.sendTestNotification()`.

---

## 13. Localisation

Three languages: English (`en`), Sinhala (`si`), Tamil (`ta`).

| File | Purpose |
|------|---------|
| `lib/l10n/app_localizations_en.dart` | English strings (generated) |
| `lib/l10n/app_localizations_si.dart` | Sinhala strings (generated) |
| `lib/l10n/app_localizations_ta.dart` | Tamil strings (generated) |
| `lib/l10n/s.dart` | `export 'app_localizations.dart'` shim |

**Usage in widgets:**
```dart
import 'package:i_connect/l10n/s.dart';
final s = S.of(context);
Text(s.invoiceLoadFailed)
```

**Locale storage:** `LocaleProvider` stores the locale under `'app_locale_$userId'` in `SharedPreferences`. This means each device user has their own locale; signing in with a different account restores that account's saved language.

**Language selector:** Available via `LanguageSelectorSheet` widget (bottom sheet with flag + native name).

---

## 14. Key Supabase Tables (Observed)

| Table | Used By |
|-------|---------|
| `users` | All roles — profile, role, photo, specializations |
| `service_tickets` | Customer, admin, engineer, EA |
| `chat_messages` | Ticket + inquiry chat |
| `service_schedules` | Admin, engineer, EA, customer |
| `service_schedule_engineers` | Engineer, EA (M2M: schedules ↔ engineers) |
| `machine_catalog` | Admin, marketing, customer (product listing) |
| `customer_machines` | Customer, admin (registered machines) |
| `machine_installations` | Admin, engineer, EA |
| `installation_engineers` | M2M: installations ↔ engineers |
| `inquiries` | Admin (CRM pipeline) |
| `machine_suggestions` | Admin hot leads |
| `quotations` | Admin, customer |
| `invoices` | Admin, customer |
| `installment_plans` | Admin, customer |
| `installment_payments` | Admin, customer |
| `notifications` | All roles (in-app inbox) |
| `fcm_tokens` | NotificationService |
| `referrals` | Customer, admin, marketing |
| `referral_rules` | Admin, marketing |
| `customer_tiers` | Customer home, marketing |
| `marketer_permissions` | PermissionsProvider |
| `knowledge_base_articles` | Customer, admin, marketing |
| `attendance` | Engineer, EA (check-in/out) |
| `job_records` | Engineer, EA |
| `engineer_leaves` | Engineer, EA |
| `engineer_kpi_snapshots` | EA performance dashboard |
| `banners` | Marketing, customer home carousel |

---

## 15. Key RPC Functions (Observed)

| RPC | Called By |
|-----|-----------|
| `get_installment_plans(p_customer_id?)` | admin_installments_page, customer_installments_page |
| `get_invoice_detail(p_invoice_id)` | admin_invoice_detail_page, customer_invoice_detail_page |
| `update_installation_status(p_id, p_status, p_report, p_notes)` | engineer, EA, admin installation detail pages |
| `engineer_acknowledge_installation(p_installation_id)` | engineer_installation_detail_page |
| `assign_installation_engineers(p_id, p_engineers)` | installation detail pages |
| `remove_installation_engineer(p_id, p_engineer_id)` | installation detail pages |
| `fn_post_job_status_chat(p_schedule_id, p_engineer_id, p_kind, p_note)` | engineer_my_schedules_page |
| `apply_referral_code(p_code, p_user_id)` | signup_page |
| `generate_engineer_kpi_snapshots(p_month)` | pg_cron (not called from app) |

---

## 16. Conventions & Rules

### Must Follow

1. **UTC timestamps:** Always use `DateTime.now().toUtc().toIso8601String()` for `timestamptz` writes.
2. **Date-only values:** Use `.toIso8601String().substring(0, 10)` — this intentionally stays local.
3. **Color:** Always use `Brand.*`, `AdminColors.*`, or `StatusColors.*`. Never hardcode `Color(0xFF...)`.
4. **Radii:** Always use `Brand.r(context)` — never `BorderRadius.circular(12)`.
5. **Logging:** Use `AppLogger.debug/info/warn/error` — never raw `debugPrint` or `print`.
6. **Network calls:** Wrap reads in `SafeNetwork.read<T>()` if offline fallback is wanted.
7. **Localisation:** Use `S.of(context).*` for all user-facing strings — never hardcode English.
8. **Staff accounts:** Only created via Edge Functions — never `supabase.auth.signUp()`.
9. **Schema:** Verify column names against live DB before writing queries.

### Patterns In Use

- **Realtime debouncing:** All realtime subscriptions use a 2-second debounce timer to batch rapid DB events into a single `_load()` call.
- **Fire-and-forget:** Non-critical writes (points, notifications) are not awaited; errors are logged only.
- **In-flight deduping:** Long-running fetches set `_loading = true` and skip re-entry to prevent duplicate requests.
- **Staleness guard:** Many screens skip reload if last fetch was < N seconds ago (`_lastFetch` pattern).
- **Cache-first offline:** `SafeNetwork.read()` serves cached data when offline and marks the banner.

---

## 17. Adding a New Screen

1. **Create the file** in `lib/screens/<role>/my_new_page.dart`
2. **Use `DsPageHeader`** for the AppBar (standard across all screens)
3. **Fetch data** with `SafeNetwork.read<T>()` if offline fallback matters; otherwise direct Supabase call
4. **Timestamps:** Use `DateTime.now().toUtc().toIso8601String()` for any writes
5. **Colors:** Import `brand_colors.dart` and use `Brand.*` / `AdminColors.*` only
6. **Radii:** `Brand.r(context)` everywhere
7. **Strings:** Add keys to `lib/l10n/app_localizations_en.dart` (and si/ta), run `flutter gen-l10n`
8. **Log errors:** `AppLogger.error('tag', 'message', error)`
9. **Register the route** in `main.dart` if it's a top-level destination, or navigate directly with `Navigator.push`
10. **Test offline:** Disable Wi-Fi and confirm the screen either shows cached data or a graceful error — not a crash

---

## 18. Adding a New Role

1. **Add the role string** to the `users.role` enum in Supabase (migration required)
2. **Create Edge Function** for account creation (follow `create-engineer` as template)
3. **Add routing** in `main.dart → _navigateByRole` switch
4. **Add routing** in `splash_screen.dart → _checkAuth` role sequence
5. **Add synthetic email domain** (if staff role) in `login_page.dart` domain trial list
6. **Create dashboard + screen tree** under `lib/screens/<new_role>/`
7. **Add FCM topic subscription** in `NotificationService` for the new role
8. **Create RLS policies** in Supabase for all tables the new role needs to access
9. **Update this file**

---

## 19. Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `provider` | ^6.1.5 | State management |
| `supabase_flutter` | ^2.3.0 | Backend (DB, Auth, Storage, Realtime) |
| `firebase_core` | ^4.7.0 | Firebase base |
| `firebase_messaging` | ^16.2.0 | FCM push notifications |
| `firebase_crashlytics` | ^5.2.3 | Crash reporting |
| `flutter_dotenv` | ^6.0.1 | `.env` file loading |
| `google_fonts` | ^8.1.0 | Montserrat typography |
| `cached_network_image` | ^3.3.1 | Image caching |
| `image_picker` | ^1.0.7 | Camera/gallery photo pick |
| `fl_chart` | ^1.2.0 | Charts in analytics dashboard |
| `table_calendar` | ^3.1.2 | Calendar widget |
| `shared_preferences` | ^2.2.2 | Local key-value store (locale, theme, cache) |
| `connectivity_plus` | ^7.1.1 | Network state stream |
| `path_provider` | ^2.1.5 | Temp file paths for CSV export |
| `share_plus` | ^13.0.0 | Share CSV / files |
| `url_launcher` | ^6.2.1 | Open tel:, mailto:, https: links |
| `intl` | ^0.20.2 | Date formatting, plurals |
| `uuid` | ^4.3.3 | UUID generation |
| `email_validator` | ^3.0.0 | Email format validation |
| `record` | ^7.0.0 | Audio recording (chat attachments) |
| `just_audio` | ^0.10.5 | Audio playback |
| `file_picker` | ^12.0.0 | Document file picking |
| `geolocator` | ^14.0.1 | GPS location for engineer route/check-in |
| `permission_handler` | ^12.0.1 | Runtime permissions |
| `flutter_map` | ^8.3.0 | OpenStreetMap tile map |
| `latlong2` | ^0.9.1 | Lat/Lng data types for flutter_map |

---

## 20. Build & Run

### Prerequisites

Create `i_connect/.env` with:
```
SUPABASE_URL=https://mgfehxoampnafcyriqzt.supabase.co
SUPABASE_ANON_KEY=<anon key from Supabase dashboard>
```

`google-services.json` (Android) and `GoogleService-Info.plist` (iOS) must be placed in the standard locations — not committed to git.

### Commands

```bash
# Install dependencies
flutter pub get

# Regenerate localizations (after editing .arb files)
flutter gen-l10n

# Regenerate app icons
dart run flutter_launcher_icons

# Regenerate native splash
dart run flutter_native_splash:create

# Run on connected device
flutter run

# Release build — Android
flutter build apk --release

# Release build — iOS
flutter build ios --release
```
