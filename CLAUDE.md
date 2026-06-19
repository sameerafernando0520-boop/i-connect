# i_connect — Claude Code Project Instructions

Flutter 3.44 + Supabase app for iFrontiers Pvt Ltd (Sri Lanka industrial machines vendor).  
5 user roles. Multi-language (en/si/ta). Firebase FCM + Crashlytics. Offline-capable.  
Deep reference: [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) | Bug list: [BUGS_AND_ERRORS.md](BUGS_AND_ERRORS.md)

---

## Commands

```bash
flutter pub get                          # install / sync dependencies
flutter run                             # run on connected device
flutter gen-l10n                        # regenerate after editing .arb locale files
dart run flutter_launcher_icons         # regenerate app icons
dart run flutter_native_splash:create   # regenerate native splash screen
flutter build apk --release             # Android release
flutter build ios --release             # iOS release
```

`.env` must exist at project root with `SUPABASE_URL` and `SUPABASE_ANON_KEY`.  
`google-services.json` and `GoogleService-Info.plist` are required (not in git).

---

## Role System

| Role | Home Screen | Login Method |
|------|-------------|-------------|
| `customer` | `CustomerShellPage` | Email + password |
| `admin` | `AdminDashboard` | Email + password |
| `marketing_admin` | `MarketingAdminDashboard` | Username → `@marketing.iconnect.lk` |
| `engineering_admin` | `EngineeringAdminDashboard` | Username → `@engineering.iconnect.lk` |
| `engineer` | `EngineerDashboard` | Username → `@engineer.iconnect.lk` |

**Routing lives in two places:**
- `lib/main.dart` → `_navigateByRole()` (auth state listener)
- `lib/screens/splash_screen.dart` → `_checkAuth()` (cold-start role sequence)

**Staff accounts are created server-side only** via Supabase Edge Functions (`create-engineer`, `create-marketer`, `create-engineering-admin`). Never use `supabase.auth.signUp()` for staff.

`marketing_admin` feature visibility is gated by `PermissionsProvider` (loaded from `marketer_permissions` table on login).

---

## Supabase

- **Project ID:** `mgfehxoampnafcyriqzt` (region: ap-south-1 Mumbai)
- **Second project "Tri Smart" exists in the same org — never touch it.**
- **Always verify column names against the live Supabase dashboard before writing queries.** The repo has had hallucinated-column bugs.

### UTC Timestamp Rule — CRITICAL

```dart
// CORRECT — always for timestamptz columns
DateTime.now().toUtc().toIso8601String()    // "2025-06-20T08:30:00.000Z"

// WRONG — local +5:30 without offset is misread as UTC by the DB
DateTime.now().toIso8601String()            // "2025-06-20T14:00:00.000" ← bug

// Date-only (no time) — stays local intentionally
DateTime.now().toIso8601String().substring(0, 10)   // "2025-06-20"

// Comparing against server timestamps — always compare UTC to UTC
final now = DateTime.now().toUtc();
final serverTs = DateTime.parse(row['created_at']).toUtc();
```

### Key Tables (quick reference)

`users` · `service_tickets` · `chat_messages` · `service_schedules` · `service_schedule_engineers` · `machine_catalog` · `customer_machines` · `machine_installations` · `installation_engineers` · `inquiries` · `machine_suggestions` · `quotations` · `invoices` · `installment_plans` · `installment_payments` · `notifications` · `fcm_tokens` · `referrals` · `customer_tiers` · `marketer_permissions` · `knowledge_base_articles` · `attendance` · `job_records` · `engineer_leaves` · `engineer_kpi_snapshots` · `banners`

### Key RPCs

`get_installment_plans` · `get_invoice_detail` · `update_installation_status` · `engineer_acknowledge_installation` · `assign_installation_engineers` · `remove_installation_engineer` · `fn_post_job_status_chat` · `apply_referral_code`

---

## Design System

### Colors — strict rules

```dart
// CORRECT
Brand.canvas(isDark)          // page background
Brand.surface(isDark)         // card / sheet background
Brand.darkCard(isDark)        // elevated card
Brand.royalBlue               // primary accent
AdminColors.border(context)   // admin UI borders
StatusColors.forStatus('open') // semantic status color

// WRONG — never hardcode colors
Color(0xFF1A2B3C)             // ← forbidden
Colors.blue                   // ← forbidden (use Brand.*)
```

### Radii — always use `Brand.r()`

```dart
// CORRECT
borderRadius: BorderRadius.circular(Brand.r(context))
borderRadius: Brand.cardRadius(context)

// WRONG
borderRadius: BorderRadius.circular(12)   // ← forbidden
```

### Component library

- **`DsPageHeader`** — use for every screen's AppBar (standard across all screens)
- **`lib/widgets/ds/ds_widgets.dart`** — design-system components; check here before building a new widget
- **`lib/widgets/common/theme_style_sheet.dart`** — shared text styles
- **`lib/config/admin_theme.dart`** — `AdminColors.*`, `AdminDimens.*`, `AdminStyles.*` (admin/staff portals)
- **`lib/config/brand_colors.dart`** — `Brand.*`, `BrandColors.*`, `HeroPalette`, `StatusColors`

Two structural designs exist (`NavyGlow` default, `Workshop` tighter radii). `Brand.r()` handles both automatically.

---

## Adding a New Screen

1. Create `lib/screens/<role>/my_new_page.dart`
2. Use `DsPageHeader` for the AppBar
3. Colors: `Brand.*` / `AdminColors.*` only — no `Color(0xFF...)`
4. Radii: `Brand.r(context)` only — no magic numbers
5. Timestamps: `DateTime.now().toUtc().toIso8601String()` for any DB writes
6. Strings: add keys to `lib/l10n/app_localizations_en.dart` (+ si/ta), run `flutter gen-l10n`
7. Errors: `AppLogger.error('tag', 'message', error)` — never raw `print` or `debugPrint`
8. Offline: wrap Supabase reads in `SafeNetwork.read<T>()` if the screen should work offline
9. Register navigation in `main.dart` if it's a top-level destination

---

## State Management

Provider only — no Riverpod, no Bloc.

| Provider | Loaded When | What It Holds |
|----------|-------------|--------------|
| `ThemeProvider` | Lazy (first access) | Dark mode, dark style, design variant |
| `LocaleProvider` | Login → `loadForUser(uid)` | Per-user language (en/si/ta) |
| `PermissionsProvider` | Login (marketing_admin only) | 9 feature-flag booleans from `marketer_permissions` |

Both `LocaleProvider` and `PermissionsProvider` are cleared on logout.

---

## Services — What to Call

| Task | Use |
|------|-----|
| Supabase read with offline fallback | `SafeNetwork.read<T>()` |
| Engineer check-in / check-out | `AttendanceService.checkIn()` / `.checkOut()` |
| Upload file to chat | `ChatAttachmentService.uploadBytes()` |
| Validate file before upload | `UploadValidator.validate*()` (always call this first) |
| Award points (non-blocking) | `PointsService.awardOnce()` / `.articleRead()` |
| Export CSV | `ExportService.export*()` |
| Log structured message | `AppLogger.debug/info/warn/error()` |
| FCM topics on login | `NotificationService.onLogin()` |
| FCM cleanup on logout | `NotificationService.onLogout()` |
| Check online status | `ConnectivityService.instance.isOnline` (ValueNotifier) |

---

## Patterns In Use — Follow These

### Realtime debouncing (all realtime screens)
```dart
Timer? _debounce;
void _onRealtimeEvent(_) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(seconds: 2), _load);
}
```

### In-flight dedup (long fetches)
```dart
if (_loading) return;
setState(() => _loading = true);
try { await _fetchData(); }
finally { if (mounted) setState(() => _loading = false); }
```

### Staleness guard (skip reload if fresh)
```dart
if (_lastFetch != null &&
    DateTime.now().difference(_lastFetch!) < const Duration(seconds: 10)) return;
```

### Fire-and-forget (non-critical writes)
```dart
// Do NOT await; errors are logged only
unawaited(PointsService.awardOnce('event_key'));
```

### Realtime subscription cleanup
```dart
@override
void dispose() {
  _debounce?.cancel();
  supabase.removeChannel(_channel);
  super.dispose();
}
```

---

## Strings & Localisation

```dart
import 'package:i_connect/l10n/s.dart';

// CORRECT
Text(S.of(context).invoiceLoadFailed)

// WRONG — never hardcode English strings
Text('Failed to load invoices')
```

After adding/editing strings in `lib/l10n/app_localizations_en.dart`, always run:
```bash
flutter gen-l10n
```
Add matching keys to `app_localizations_si.dart` and `app_localizations_ta.dart`.

---

## DO NOT

- **DO NOT** hardcode `Color(0xFF...)` anywhere — use `Brand.*` or `AdminColors.*`
- **DO NOT** hardcode `BorderRadius.circular(12)` — use `Brand.r(context)`
- **DO NOT** use `DateTime.now()` for server timestamp writes — use `.toUtc()`
- **DO NOT** compare `DateTime.now()` directly to server timestamps — both must be UTC
- **DO NOT** create staff accounts via `supabase.auth.signUp()` — use Edge Functions only
- **DO NOT** hardcode the Supabase project domain as a string literal — use `SupabaseConfig.*`
- **DO NOT** call `debugPrint` or `print` — use `AppLogger.*`
- **DO NOT** hardcode English UI strings — use `S.of(context).*`
- **DO NOT** trust column names from memory — verify against live Supabase schema
- **DO NOT** upload files without calling `UploadValidator` first
- **DO NOT** use `app_theme.dart` — it is dead code; use `ThemeProvider` and `Brand.*`
- **DO NOT** await fire-and-forget point awards — they are intentionally non-blocking
- **DO NOT** touch the "Tri Smart" Supabase project in the same org

---

## Known Bug Hotspots

Full list: [BUGS_AND_ERRORS.md](BUGS_AND_ERRORS.md)

The three most likely to be accidentally re-introduced:

**1. UTC timestamp omission** — every new DB write that stores a timestamp must use `.toUtc().toIso8601String()`. Forgetting `.toUtc()` writes local Sri Lanka time (+5:30) which the DB misreads as UTC, shifting all time-based logic by 5.5 hours.

**2. Hardcoded domain string** — `'mgfehxoampnafcyriqzt.supabase.co'` is already hardcoded in two places (`splash_screen.dart`, `connectivity_service.dart`). Don't add a third. New DNS/heartbeat checks must read the host from `SupabaseConfig`.

**3. `getInitials()` crash on empty string** — `StringUtils.getInitials(name)` throws on empty or whitespace-only input (`lib/utils/string_utils.dart`). Always guard: `name.trim().isEmpty ? '?' : StringUtils.getInitials(name)`.
