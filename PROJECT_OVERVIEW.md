# i_connect — Project Overview

> Living reference for the iFrontiers Connect Flutter + Supabase app.  
> Update this file whenever you add a screen, role, service, or RPC.

---

## 1. App Identity

| Field | Value |
|-------|-------|
| App name | iFrontiers Connect (`i_connect`) |
| Client | iFrontiers Pvt Ltd — Sri Lanka industrial machines vendor |
| Flutter SDK | ≥ 3.0.0 (tested on 3.44.x) |
| Dart SDK | ≥ 3.0.0 |
| Version | 1.0.0+1 |
| Backend | Supabase (PostgreSQL + Realtime + Storage + Edge Functions) |
| Push | Firebase Cloud Messaging (`firebase_messaging ^16`) |
| Crash | Firebase Crashlytics (`firebase_crashlytics ^5`) |
| Total Dart files | 186 (111 screens, ~75 services/providers/utils/widgets) |

---

## 2. Supabase Project

| Field | Value |
|-------|-------|
| Project ID | `mgfehxoampnafcyriqzt` |
| Region | `ap-south-1` (Mumbai) |
| Dashboard | https://supabase.com/dashboard/project/mgfehxoampnafcyriqzt |

**The same Supabase org contains a second unrelated project "Tri Smart" — never touch it.**

### UTC Timestamp Rule — Critical

All `timestamptz` columns must receive UTC ISO-8601 strings:

```dart
// CORRECT — always for timestamptz columns
DateTime.now().toUtc().toIso8601String()   // → "2025-06-20T08:30:00.000Z"

// WRONG — Sri Lanka +5:30 without offset is misread as UTC by the DB
DateTime.now().toIso8601String()            // → "2025-06-20T14:00:00.000" (ambiguous)

// Date-only (no time) — stays local intentionally
DateTime.now().toIso8601String().substring(0, 10)  // → "2025-06-20"

// Comparing against server timestamps — always compare UTC to UTC
final now = DateTime.now().toUtc();
final serverTs = DateTime.parse(row['created_at']).toUtc();
```

### Schema Ground Truth

**Always fetch live schema before trusting column names.** The repo has had hallucinated-column bugs (e.g. app read `duration_days` while the real column is `total_days` on `engineer_leaves`). Use the Supabase dashboard → Table Editor to verify.

---

## 3. Role System

Five roles live in `users.role`:

| Role | Description | Home Screen | Login Method |
|------|-------------|-------------|-------------|
| `customer` | Customers who buy/register machines | `CustomerShellPage` | Email + password |
| `admin` | Full platform admin | `AdminDashboard` | Email + password |
| `marketing_admin` | Marketing portal with permission-gated features | `MarketingAdminDashboard` | Username → `@marketing.iconnect.lk` |
| `engineering_admin` | Engineering operations portal | `EngineeringAdminDashboard` | Username → `@engineering.iconnect.lk` |
| `engineer` | Field technician | `EngineerDashboard` | Username → `@engineer.iconnect.lk` |

### Staff Login (Synthetic Emails)

Staff log in with a plain **username** (no `@`). `login_page.dart` auto-tries three domains in order until one succeeds:
```
<username>@marketing.iconnect.lk
<username>@engineering.iconnect.lk
<username>@engineer.iconnect.lk
```

Staff accounts are **created server-side only** via Supabase Edge Functions:

| Edge Function | Creates |
|---------------|---------|
| `create-engineer` | Engineer account |
| `create-marketer` | Marketing admin account |
| `create-engineering-admin` | Engineering admin account |

**Never create staff via `supabase.auth.signUp()` on the client.**

### Role-Based Navigation

Routing lives in **two places** — both must be kept in sync:

| File | When | Method |
|------|------|--------|
| `lib/main.dart` | Auth state change events | `_navigateByRole()` |
| `lib/screens/splash_screen.dart` | App cold-start | `_checkAuth()` |

```dart
// _navigateByRole switch
admin             → AdminDashboard
engineering_admin → EngineeringAdminDashboard
engineer          → EngineerDashboard
marketing_admin   → MarketingAdminDashboard
customer          → CustomerShellPage   // 5-tab indexed-stack shell
```

### Marketing Admin Permissions

`marketing_admin` feature access is gated by a per-user row in `marketer_permissions` (9 boolean columns). Loaded into `PermissionsProvider` on login. RLS policies named `marketer_*` enforce the same flags server-side.

---

## 4. Authentication Flows

### Customer Sign-Up (2 steps)
1. **Step 0** — Full name, company, phone, email, province/district, optional referral code
2. **Step 1** — Password + confirm (live strength indicator)
- Referral code is validated in real-time via `apply_referral_code` RPC
- On creation: `PointsService.awardOnce('signup_bonus')` awards 100 points

### Staff Login
- Username entered → tries 3 synthetic email domains in order
- Error messages distinguish: wrong password / unconfirmed email / too many attempts / network error

### Password Reset (Deep Link)
1. User requests reset on login screen → Supabase sends magic-link email
2. Link opens app via deep link scheme `iconnect://`
3. `main.dart` detects `passwordRecovery` auth event → pushes `ResetPasswordPage`
4. User enters new password → `supabase.auth.updateUser(password:)` → auto-logout → back to login

### Session Expiry
If `tokenRefreshed` event returns an error, user is force-signed-out and redirected to `LoginPage`.

---

## 5. Directory Structure

```
lib/
├── main.dart                        # Entry point, init, auth listener, routing
├── config/
│   ├── brand_colors.dart            # Full color system (Brand, StatusColors, HeroPalette)
│   ├── admin_theme.dart             # Admin-portal colors (AdminColors), dimensions, text styles
│   ├── app_theme.dart               # DEAD — do not use; superseded by ThemeProvider + Brand.*
│   ├── sales_stage_config.dart      # CRM pipeline stage definitions
│   └── supabase_config.dart         # Supabase client singleton + env-var loading
├── l10n/
│   ├── s.dart                       # Re-export shim: export 'app_localizations.dart'
│   ├── app_localizations.dart       # Generated by flutter gen-l10n
│   ├── app_localizations_en.dart    # English strings (edit these)
│   ├── app_localizations_si.dart    # Sinhala strings
│   └── app_localizations_ta.dart    # Tamil strings
├── models/
│   ├── chat_message.dart            # ChatMessage + MessageStatus enum
│   ├── dashboard_stats.dart         # DashboardStats (admin KPIs)
│   ├── inquiry_detail.dart          # InquiryDetail with nested models
│   └── ticket_detail.dart           # TicketDetail, TicketUser, TicketMachine
├── providers/
│   ├── locale_provider.dart         # Per-user language (en/si/ta) via SharedPreferences
│   ├── permissions_provider.dart    # Marketing admin 9-flag feature gate
│   └── theme_provider.dart          # Dark mode, dark style, design variant (NavyGlow/Workshop)
├── repositories/
│   ├── admin_dashboard_repository.dart       # Admin KPI queries
│   ├── engineering_admin_repository.dart     # EA dashboard queries
│   ├── inquiry_detail_repository.dart        # Inquiry + chat CRUD
│   └── ticket_detail_repository.dart         # Ticket + chat + read-status
├── screens/
│   ├── auth/            # 4 screens
│   ├── admin/           # 37 screens
│   ├── customer/        # 24 screens
│   ├── engineer/        # 9 screens
│   ├── engineering_admin/ # 23 screens
│   └── marketing/       # 13 screens
├── services/
│   ├── attendance_service.dart       # Engineer check-in/out
│   ├── chat_attachment_service.dart  # File picker + Supabase Storage upload
│   ├── connectivity_service.dart     # Online/offline ValueNotifier + 15s heartbeat
│   ├── export_service.dart           # RFC-4180 CSV generation + share_plus
│   ├── notification_service.dart     # FCM token, topic subscriptions, message routing
│   ├── offline_cache_service.dart    # SharedPreferences JSON envelope with TTL
│   ├── points_service.dart           # Gamification point awards (fire-and-forget)
│   └── safe_network.dart             # Supabase call wrapper with cache fallback
└── utils/
│   ├── app_logger.dart               # debug/info/warn/error → Crashlytics in release
│   ├── machine_image_helper.dart     # Image URL fallback chain for machine catalog
│   ├── sri_lanka_locations.dart      # 9 provinces + 25 districts static data
│   ├── string_utils.dart             # getInitials(), truncate()
│   ├── time_utils.dart               # Relative timestamps, date separators, greetings
│   └── upload_validator.dart         # MIME sniff + size caps (always call before upload)
└── widgets/
    ├── admin/                         # Admin-specific widgets (inquiry cards, confirm dialog)
    ├── common/                        # Shared (OfflineBanner, LanguageSelectorSheet, ChatAttachBar)
    ├── customer/                      # CustomerNavBar, carousel, submit-payment sheet
    ├── ds/ds_widgets.dart             # Design-system component library (DsPageHeader, etc.)
    ├── engineer/                      # EngineerCheckinCard
    └── engineering_admin/             # EngineerAssignedCard
```

---

## 6. Screen Catalogue

### Auth (`lib/screens/auth/`)
| File | Purpose |
|------|---------|
| `splash_screen.dart` | Animated 2.2s splash; checks auth token → routes by role |
| `login_page.dart` | Email/username login; staff domain auto-trial |
| `signup_page.dart` | 2-step customer registration with referral code |
| `reset_password_page.dart` | Password update after deep-link recovery session |

### Customer (`lib/screens/customer/`)
| File | Purpose |
|------|---------|
| `customer_shell_page.dart` | 5-tab `IndexedStack` root shell |
| `home_page.dart` | Dashboard: tier progress, quick stats, banners, activity feed |
| `catalog_page.dart` | Machine catalog browse |
| `machine_detail_page.dart` | Public machine detail (from catalog) |
| `my_machines_page.dart` | Customer's registered machines |
| `my_machine_detail_page.dart` | Detail for a registered machine |
| `register_machine_page.dart` | Register a purchased machine |
| `order_form_page.dart` | New machine order/inquiry submission |
| `request_service_page.dart` | Service request form |
| `support_tickets_page.dart` | Customer's support ticket list |
| `ticket_detail_page.dart` | Ticket detail with realtime chat |
| `create_support_ticket_page.dart` | New support ticket form |
| `my_quotations_page.dart` | Customer's received quotations + inline detail |
| `my_invoices_page.dart` | Customer's invoices |
| `customer_invoice_detail_page.dart` | Invoice detail with payment history |
| `customer_installments_page.dart` | Installment plan overview |
| `my_schedule_page.dart` | Upcoming service schedules |
| `knowledge_base_page.dart` | FAQ / help article list |
| `article_detail_page.dart` | Full KB article with bookmarks + view tracking |
| `notification_list_page.dart` | In-app notification inbox |
| `notification_settings_page.dart` | FCM topic opt-in / opt-out |
| `referral_page.dart` | Referral code share + history |
| `points_history_page.dart` | Loyalty points ledger |
| `profile_page.dart` | Customer profile edit + app settings |

### Admin (`lib/screens/admin/`)
| File | Purpose |
|------|---------|
| `admin_dashboard.dart` | Main hub with KPI cards + realtime activity feed |
| `admin_more_page.dart` | Navigation hub to all sub-sections |
| `admin_settings_page.dart` | Admin account settings |
| `analytics_dashboard.dart` | Business analytics with fl_chart graphs |
| `inquiry_management_page.dart` | CRM inquiry pipeline list |
| `inquiry_detail_page.dart` | Inquiry detail + sales pipeline stepper |
| `inquiry_chat_page.dart` | Chat thread for an inquiry |
| `admin_hot_leads_page.dart` | High-readiness machine suggestions |
| `customers_management_page.dart` | Customer list + search |
| `customer_detail_page.dart` | Customer profile + full activity history |
| `machines_management_page.dart` | Machine catalog management |
| `admin_register_machine_page.dart` | Register machine on behalf of customer |
| `tickets_management_page.dart` | All support tickets |
| `admin_ticket_detail_page.dart` | Ticket detail + internal notes |
| `service_calendar_page.dart` | Service schedule calendar view |
| `create_schedule_page.dart` | Create a service schedule |
| `schedule_detail_page.dart` | Schedule detail + engineer assignment |
| `admin_installations_page.dart` | Machine installation job list |
| `admin_installation_detail_page.dart` | Installation job detail + lifecycle |
| `admin_installments_page.dart` | Installment plan overview |
| `installment_detail_page.dart` | Single installment plan detail |
| `quotation_management_page.dart` | Quotation list |
| `create_quotation_page.dart` | New quotation builder |
| `admin_quotation_detail_page.dart` | Quotation detail + PDF/email actions |
| `payment_dashboard_page.dart` | Payment overview + revenue charts |
| `create_invoice_page.dart` | New invoice builder |
| `admin_invoice_detail_page.dart` | Invoice detail + payment recording |
| `broadcast_notifications.dart` | Push notification broadcast to customer segments |
| `referral_management_page.dart` | Referral tracking |
| `referral_rules_page.dart` | Referral points rule editor |
| `tier_management_page.dart` | Customer loyalty tier editor |
| `admin_knowledge_base_page.dart` | KB article list |
| `admin_knowledge_base_form_page.dart` | KB article create/edit |
| `engineer_management_page.dart` | Engineer account list |
| `marketer_management_page.dart` | Marketer account list |
| `engineering_admin_management_page.dart` | Engineering admin account list |
| `create_marketer_page.dart` | Create marketing admin account |
| `create_engineering_admin_page.dart` | Create engineering admin account |

### Engineer (`lib/screens/engineer/`)
| File | Purpose |
|------|---------|
| `engineer_dashboard.dart` | Engineer home with ticket/schedule/installation counts |
| `engineer_ticket_list_page.dart` | Assigned tickets with multi-filter |
| `engineer_ticket_detail_page.dart` | Ticket detail with realtime chat + location map |
| `engineer_schedule_page.dart` | Calendar + timeline of service schedules |
| `engineer_my_schedules_page.dart` | Today/upcoming schedules with check-in workflow |
| `engineer_create_schedule_page.dart` | Create schedule (status: `pending_approval`) |
| `engineer_installation_list_page.dart` | Installation assignments |
| `engineer_installation_detail_page.dart` | Installation lifecycle + completion |
| `engineer_profile_page.dart` | Profile edit + specializations + performance stats |

### Engineering Admin (`lib/screens/engineering_admin/`)
| File | Purpose |
|------|---------|
| `engineering_admin_dashboard.dart` | EA hub with KPI overview |
| `ea_engineer_list_page.dart` | All engineers list |
| `ea_engineer_detail_page.dart` | Engineer profile + performance history |
| `ea_create_engineer_page.dart` | Create engineer account (calls Edge Function) |
| `ea_ticket_list_page.dart` | All service tickets |
| `ea_ticket_detail_page.dart` | Ticket detail |
| `ea_ticket_chat_page.dart` | Ticket chat thread |
| `ea_schedule_page.dart` | Schedule dispatch view |
| `ea_pending_approvals_page.dart` | Pending schedule approvals queue |
| `ea_installation_page.dart` | Installation jobs list |
| `ea_installation_detail_page.dart` | Installation detail + engineer assignment |
| `ea_assign_engineers_sheet.dart` | Bottom sheet: assign engineers to installation |
| `ea_job_records_page.dart` | Job record history |
| `ea_job_record_form_page.dart` | Create/edit job record |
| `ea_job_record_detail_page.dart` | Job record detail |
| `ea_leave_management_page.dart` | Engineer leave requests list |
| `ea_leave_detail_page.dart` | Leave request detail + approve/reject |
| `ea_attendance_page.dart` | Engineer attendance log |
| `ea_performance_dashboard.dart` | Engineer KPI dashboard with charts |
| `ea_reports_page.dart` | Engineering reports |
| `ea_broadcast_page.dart` | Push notifications to engineers |
| `ea_notifications_page.dart` | EA notification inbox |
| `ea_profile_page.dart` | EA profile edit |
| `ea_settings_page.dart` | EA app settings |

### Marketing Admin (`lib/screens/marketing/`)
| File | Purpose |
|------|---------|
| `marketing_admin_dashboard.dart` | Marketing hub (features gated by `PermissionsProvider`) |
| `ma_home_page.dart` | Marketing home with quick stats |
| `ma_analytics_page.dart` | Campaign analytics with charts |
| `ma_banners_page.dart` | Hero banner management |
| `ma_broadcast_page.dart` | Customer push notification broadcasts |
| `ma_catalog_page.dart` | Product catalog editing |
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
| `ConnectivityService` | Yes | Online/offline `ValueNotifier<bool>` + 15s DNS heartbeat | `initialize()`, `isOnline`, `markOnline()`, `markOffline()` |
| `NotificationService` | Yes | FCM token, topic subscriptions, message routing | `initialize()`, `onLogin()`, `onLogout()`, `updateSetting()` |
| `OfflineCacheService` | Static | SharedPreferences JSON envelope with TTL advisory | `write()`, `read<T>()`, `isStale()`, `invalidate()`, `clearAll()` |
| `SafeNetwork` | Static | Supabase call wrapper — cache fallback on network error | `read<T>()`, `write<T>()` |
| `AttendanceService` | Static | Engineer daily check-in/out to `attendance` table | `checkIn()`, `checkOut()`, `todayRecord()` |
| `ChatAttachmentService` | Static | File picker + upload to `chat-attachments` Storage bucket | `pickImage()`, `pickDocument()`, `uploadBytes()`, `currentLocation()` |
| `ExportService` | Static | RFC-4180 CSV generation + share_plus | `exportCustomers()`, `exportInquiries()`, `exportTickets()` |
| `PointsService` | Static | Fire-and-forget gamification points via RPCs | `awardOnce()`, `articleRead()`, `machinePurchase()` |
| `UploadValidator` | Static (utils) | MIME sniff + size cap validation before any upload | `validateImage()`, `validateDocument()`, `validateVoice()` |

> **Upload rule:** Always call `UploadValidator.validate*()` before `ChatAttachmentService.uploadBytes()`.

---

## 8. State Management

Provider only — no Riverpod, no Bloc.

Three providers registered at the `MultiProvider` root in `main.dart`:

| Provider | Type | When Loaded | Cleared On Logout |
|----------|------|-------------|-------------------|
| `ThemeProvider` | `ChangeNotifier` | Lazy (first access) | No |
| `LocaleProvider` | `ChangeNotifier` | Login → `loadForUser(uid)` | Yes |
| `PermissionsProvider` | `ChangeNotifier` | Login (marketing_admin only) | Yes |

---

## 9. Design System

### Color Sources (single source of truth)

**`lib/config/brand_colors.dart`** — all customer/shared colors:

| API | Purpose |
|-----|---------|
| `Brand.canvas(isDark)` | Page/scaffold background |
| `Brand.surface(isDark)` | Card / sheet background (replaces `isDark ? Brand.darkCard : Colors.white`) |
| `Brand.darkCard` | Dark-mode card base |
| `Brand.darkCardElevated` | Dark-mode elevated card |
| `Brand.royalBlue` | Primary accent (`Color(0xFF1A56DB)`) |
| `Brand.lightGreen` | Success / positive accent (`Color(0xFF22C55E)`) |
| `Brand.r(double)` | Radius helper — Workshop scales 35% tighter; NavyGlow returns unchanged |
| `Brand.cardRadius` | Default card radius (16 NavyGlow, 14 Workshop) |
| `Brand.ink(isDark)` | Primary text color |
| `Brand.cardBorder(isDark)` | Card border color |
| `StatusColors.danger` | Red `Color(0xFFEF4444)` — errors, overdue, destructive actions |
| `StatusColors.success` | Green `Color(0xFF22C55E)` — resolved, paid, accepted |
| `StatusColors.warning` | Amber `Color(0xFFF59E0B)` — pending, caution |
| `StatusColors.open` | Blue `Color(0xFF3B82F6)` — open tickets/inquiries |
| `StatusColors.inProgress` | Amber `Color(0xFFF59E0B)` — in-progress status |
| `StatusColors.closed` | Slate `Color(0xFF64748B)` — closed/archived |

**`lib/config/admin_theme.dart`** — admin/staff portal constants:

| API | Purpose |
|-----|---------|
| `AdminColors.border(context)` | Theme-aware admin border color |
| `AdminColors.primary` | Admin primary accent |
| `AdminColors.error` | Admin error color |
| `AdminColors.cardElevated(context)` | Elevated card color |
| `AdminDimens.cardRadius` | Admin card radius |
| `AdminStyles.pageTitle` | Page title text style |

### Radius Rule

```dart
// CORRECT — always pass a raw number; Brand.r() scales it for Workshop
BorderRadius.circular(Brand.r(16))
BorderRadius.circular(Brand.r(12))

// WRONG — never hardcode a radius number directly
BorderRadius.circular(12)   // ← forbidden
BorderRadius.circular(16)   // ← forbidden
```

> **Note:** `Brand.r()` takes a `double`, not a `BuildContext`. The CLAUDE.md example showing `Brand.r(context)` is incorrect.

### Color Rules

```dart
// CORRECT
Brand.canvas(isDark)              // scaffold background
Brand.surface(isDark)             // card / sheet / chip background
Brand.royalBlue                   // primary accent
StatusColors.danger               // red — errors, destructive
AdminColors.border(context)       // admin UI borders

// WRONG — never hardcode
Color(0xFF1A2B3C)                 // ← forbidden
Colors.blue                       // ← forbidden
Colors.red                        // ← forbidden (use StatusColors.danger)
Colors.white                      // ← forbidden as surface (use Brand.surface)
                                  // ALLOWED as contrast on colored/navy/gradient backgrounds
```

### Component Library

- **`DsPageHeader`** — standard AppBar for every screen
- **`lib/widgets/ds/ds_widgets.dart`** — design-system components
- **`lib/widgets/common/theme_style_sheet.dart`** — shared text styles
- **`OfflineBanner`** / **`OfflinePill`** — wrap scaffold body or embed in header

### Design Variants (toggled in `ThemeProvider`)

| Variant | Description |
|---------|-------------|
| **NavyGlow** (default) | Deep navy backgrounds, larger radii, glow effects |
| **Workshop** | Navy/slate hybrid, ~35% tighter radii, bold card borders |

`Brand.r(double)` automatically returns the correct value for the active variant. `Brand.surface(isDark)` similarly resolves to the correct card color per variant.

---

## 10. Offline & Connectivity

```
ConnectivityService.isOnline (ValueNotifier<bool>)
    ↓ listened by
OfflineBanner widget (shown at top when offline)
SafeNetwork.read<T>()
    ├─ online  → fetch Supabase → write OfflineCacheService → return data
    └─ offline → read OfflineCacheService → return stale data + set offline flag
```

**Heartbeat:** `ConnectivityService` pings `mgfehxoampnafcyriqzt.supabase.co` every 15 seconds via DNS lookup — detects captive portals (Wi-Fi with no real internet).

---

## 11. Push Notifications

**Stack:** Firebase Cloud Messaging + Supabase `notifications` table for the in-app inbox.

| Event | Behaviour |
|-------|-----------|
| App cold-start | `NotificationService.initialize()` → get FCM token → upsert `fcm_tokens` |
| Login | `NotificationService.onLogin()` → retry init if cold-start failed |
| Role assigned | Subscribe to `all_users` + role topic (`customers` / `engineers` / `admins`) |
| Token refresh | Deactivate old token, store new token |
| Foreground message | Write to `notifications` table; show in-app snackbar |
| Background tap | Deep-link to relevant screen via `navigatorKey` |
| Logout | `NotificationService.onLogout()` → deactivate token in `fcm_tokens` |

---

## 12. Localisation

Three languages: English (`en`), Sinhala (`si`), Tamil (`ta`).

```dart
import 'package:i_connect/l10n/s.dart';

// CORRECT
Text(S.of(context)!.invoiceLoadFailed)

// WRONG — never hardcode English strings
Text('Failed to load invoices')
```

**Workflow:** After adding/editing keys in `app_localizations_en.dart`, add matching keys to `si` and `ta` files, then run:
```bash
flutter gen-l10n
```

**Locale storage:** `LocaleProvider` stores per-user locale under `'app_locale_$userId'` in SharedPreferences. Each account remembers its own language independently.

---

## 13. Key Supabase Tables

| Table | Used By |
|-------|---------|
| `users` | All roles — profile, role, photo, specializations |
| `service_tickets` | Customer, admin, engineer, EA |
| `chat_messages` | Ticket + inquiry chat threads |
| `service_schedules` | Admin, engineer, EA, customer |
| `service_schedule_engineers` | M2M: schedules ↔ engineers |
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
| `fcm_tokens` | `NotificationService` |
| `referrals` | Customer, admin, marketing |
| `referral_rules` | Admin, marketing |
| `customer_tiers` | Customer home, marketing |
| `marketer_permissions` | `PermissionsProvider` |
| `knowledge_base_articles` | Customer, admin, marketing |
| `attendance` | Engineer, EA (check-in/out) |
| `job_records` | Engineer, EA |
| `engineer_leaves` | Engineer, EA |
| `engineer_kpi_snapshots` | EA performance dashboard |
| `banners` | Marketing, customer home carousel |

---

## 14. Key RPC Functions

| RPC | Called By |
|-----|-----------|
| `get_installment_plans(p_customer_id?)` | admin installments page, customer installments page |
| `get_invoice_detail(p_invoice_id)` | admin + customer invoice detail pages |
| `update_installation_status(p_id, p_status, p_report, p_notes)` | engineer, EA, admin installation detail |
| `engineer_acknowledge_installation(p_installation_id)` | `engineer_installation_detail_page` |
| `assign_installation_engineers(p_id, p_engineers)` | installation detail pages |
| `remove_installation_engineer(p_id, p_engineer_id)` | installation detail pages |
| `fn_post_job_status_chat(p_schedule_id, p_engineer_id, p_kind, p_note)` | `engineer_my_schedules_page` |
| `apply_referral_code(p_code, p_user_id)` | `signup_page` |
| `generate_engineer_kpi_snapshots(p_month)` | pg_cron scheduled job (not called from app) |

---

## 15. Patterns In Use

### Realtime debouncing
```dart
Timer? _debounce;
void _onRealtimeEvent(_) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(seconds: 2), _load);
}
```

### In-flight deduplication
```dart
if (_loading) return;
setState(() => _loading = true);
try { await _fetchData(); }
finally { if (mounted) setState(() => _loading = false); }
```

### Staleness guard
```dart
if (_lastFetch != null &&
    DateTime.now().difference(_lastFetch!) < const Duration(seconds: 10)) return;
```

### Fire-and-forget (non-critical writes)
```dart
// Do NOT await — errors are logged only
unawaited(PointsService.awardOnce('event_key'));
```

### Realtime channel cleanup
```dart
@override
void dispose() {
  _debounce?.cancel();
  supabase.removeChannel(_channel);
  super.dispose();
}
```

---

## 16. Known Bug Hotspots

Full list: [BUGS_AND_ERRORS.md](BUGS_AND_ERRORS.md)

Three most likely to be reintroduced:

**1. UTC timestamp omission** — every new DB write that stores a timestamp must use `.toUtc().toIso8601String()`. Forgetting `.toUtc()` writes local Sri Lanka time (+5:30) which the DB misreads as UTC, shifting all time-based logic by 5.5 hours.

**2. Hardcoded Supabase domain** — `'mgfehxoampnafcyriqzt.supabase.co'` is already hardcoded in `splash_screen.dart` and `connectivity_service.dart`. Don't add a third. New DNS/heartbeat checks must read the host from `SupabaseConfig`.

**3. `getInitials()` crash on empty string** — `StringUtils.getInitials(name)` throws on empty or whitespace-only input. Always guard:
```dart
name.trim().isEmpty ? '?' : StringUtils.getInitials(name)
```

---

## 17. Adding a New Screen

1. Create `lib/screens/<role>/my_new_page.dart`
2. Use **`DsPageHeader`** for the AppBar (standard across all screens)
3. Colors: `Brand.*` / `AdminColors.*` / `StatusColors.*` only — no `Color(0xFF...)`
4. Radii: `Brand.r(16)` — no magic numbers
5. Timestamps: `DateTime.now().toUtc().toIso8601String()` for any DB writes
6. Strings: add keys to `lib/l10n/app_localizations_en.dart` (+ si/ta), run `flutter gen-l10n`
7. Errors: `AppLogger.error('tag', 'message', error)` — never raw `print` or `debugPrint`
8. Offline: wrap Supabase reads in `SafeNetwork.read<T>()` if the screen should work offline
9. Uploads: call `UploadValidator.validate*()` before any file upload
10. Register navigation in `main.dart` if it's a top-level destination

---

## 18. Adding a New Role

1. Add the role string to the `users.role` enum in Supabase (migration required)
2. Create an Edge Function for account creation (use `create-engineer` as template)
3. Add routing in `main.dart → _navigateByRole` switch
4. Add routing in `splash_screen.dart → _checkAuth` role sequence
5. Add synthetic email domain (if staff) to `login_page.dart` domain trial list
6. Create dashboard + screen tree under `lib/screens/<new_role>/`
7. Add FCM topic subscription in `NotificationService` for the new role
8. Create RLS policies in Supabase for all tables the role needs
9. Update this file

---

## 19. Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `provider` | ^6.1.5+1 | State management |
| `supabase_flutter` | ^2.3.0 | Backend (DB, Auth, Storage, Realtime) |
| `firebase_core` | ^4.7.0 | Firebase base |
| `firebase_messaging` | ^16.2.0 | FCM push notifications |
| `firebase_crashlytics` | ^5.2.3 | Crash reporting |
| `flutter_dotenv` | ^6.0.1 | `.env` file loading |
| `google_fonts` | ^8.1.0 | Montserrat typography |
| `cached_network_image` | ^3.3.1 | Image caching |
| `image_picker` | ^1.0.7 | Camera / gallery photo pick |
| `fl_chart` | ^1.2.0 | Charts in analytics dashboards |
| `table_calendar` | ^3.1.2 | Calendar widget |
| `shared_preferences` | ^2.2.2 | Local key-value store (locale, theme, cache) |
| `connectivity_plus` | ^7.1.1 | Network state stream |
| `path_provider` | ^2.1.5 | Temp file paths for CSV export |
| `share_plus` | ^13.0.0 | Share CSV / files via OS share sheet |
| `url_launcher` | ^6.2.1 | Open `tel:`, `mailto:`, `https:` links |
| `intl` | ^0.20.2 | Date formatting, plurals |
| `uuid` | ^4.3.3 | UUID generation |
| `email_validator` | ^3.0.0 | Email format validation |
| `record` | ^7.0.0 | Audio recording (voice chat attachments) |
| `just_audio` | ^0.10.5 | Audio playback |
| `file_picker` | ^12.0.0-beta.7 | Document file picking |
| `geolocator` | ^14.0.1 | GPS location for engineer route/check-in |
| `permission_handler` | ^12.0.1 | Runtime permission requests |
| `flutter_map` | ^8.3.0 | OpenStreetMap tile map |
| `latlong2` | ^0.9.1 | Lat/Lng data types for flutter_map |

---

## 20. Build & Run

### Prerequisites

Create `i_connect/.env`:
```
SUPABASE_URL=https://mgfehxoampnafcyriqzt.supabase.co
SUPABASE_ANON_KEY=<anon key from Supabase dashboard>
```

`google-services.json` (Android) and `GoogleService-Info.plist` (iOS) must be in their standard locations — not committed to git.

### Commands

```bash
# Install / sync dependencies
flutter pub get

# Run on connected device
flutter run

# Regenerate localizations (after editing .arb files)
flutter gen-l10n

# Regenerate app icons
dart run flutter_launcher_icons

# Regenerate native splash
dart run flutter_native_splash:create

# Android release APK
flutter build apk --release

# iOS release
flutter build ios --release
```
