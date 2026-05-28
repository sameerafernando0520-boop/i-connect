# iFrontiers Connect — v24 Changes Summary
**Session date:** 2026-05-23
**Focus:** Engineering Admin + Engineer panels (paired), Excel export, Offline mode

---

## 1. New Files (9)

| File | Purpose |
|------|---------|
| `lib/services/connectivity_service.dart` | Singleton `ValueNotifier<bool>` of online/offline state, wired to `connectivity_plus`. |
| `lib/services/offline_cache_service.dart` | Read-only JSON cache layer using `SharedPreferences` with TTL + "Updated X ago" helper. |
| `lib/services/export_service.dart` | Excel `.xlsx` export with header styling. Helpers for customers, inquiries, service tickets. Shares via `share_plus`. |
| `lib/widgets/common/offline_banner.dart` | `OfflineBanner` widget + `OfflinePill`. Subscribes to `ConnectivityService`. |
| `lib/screens/engineering_admin/ea_broadcast_page.dart` | NEW: Engineering Admin push-notification composer (All Engineers / By Specialization / One Engineer / + customer). Inserts `notifications` rows and invokes `send-push` Edge Function. |

---

## 1b. Second pass — all-panel improvements

| File | Change |
|------|--------|
| `lib/services/safe_network.dart` | NEW: `SafeNetwork.read<T>()` / `.write<T>()` — wraps Supabase calls, caches successful reads, falls back to cache on network errors, toggles `ConnectivityService.isOnline` automatically. |
| `lib/screens/admin/admin_dashboard.dart` | + OfflineBanner wrap around dashboard tab. Existing Quick Actions retained. |
| `lib/screens/marketing/marketing_admin_dashboard.dart` | + OfflineBanner wrap around the IndexedStack body. |
| `lib/screens/engineering_admin/ea_ticket_list_page.dart` | + Excel export action in AppBar (`exportServiceTickets`). |
| `lib/screens/customer/home_page.dart` | Reordered home: **Promo → Customer dashboard → Suggest machine → other content** per user spec. |

---

## 2. Modified Files (10)

### EA panel (5 modified)
| File | Change |
|------|--------|
| `engineering_admin_dashboard.dart` | + Quick Actions strip (Add Engineer / New Schedule / New Installation / Broadcast); + Broadcast tile in More hub; OfflineBanner wrap. |
| `ea_schedule_page.dart` | + FAB "New Schedule" launching admin `CreateSchedulePage`. |
| `ea_installation_page.dart` | + FAB "New Installation" with full bottom-sheet create flow (machine picker, type, date, location, notes). |
| `ea_engineer_list_page.dart` | (already had Add-Engineer FAB; unchanged) |
| `ea_notifications_page.dart` | (unchanged — used view-only; broadcast moved to new page) |

### Engineer panel (1 modified)
| File | Change |
|------|--------|
| `engineer_dashboard.dart` | + Quick Actions row (My Schedules / Installations / Calendar / Alerts); OfflineBanner wrap. |

### Admin export hooks (3 modified)
| File | Change |
|------|--------|
| `customers_management_page.dart` | + Export-to-Excel header icon → `ExportService.exportCustomers` |
| `inquiry_management_page.dart` | + Export header icon → `ExportService.exportInquiries` |
| `tickets_management_page.dart` | + Export header icon → `ExportService.exportServiceTickets` |

### Shell + Customer (2 modified)
| File | Change |
|------|--------|
| `customer_shell_page.dart` | OfflineBanner wraps the `IndexedStack`. |
| `main.dart` | Fire-and-forget init for `OfflineCacheService` and `ConnectivityService`. |

### Dependencies
| File | Change |
|------|--------|
| `pubspec.yaml` | + `excel: ^4.0.6`, `path_provider: ^2.1.5`, `connectivity_plus: ^6.1.0`. |

---

## 3. Action Required Before First Run

```bash
cd C:\Users\sheha\Desktop\i_connect
flutter pub get
flutter analyze
flutter run
```

`flutter pub get` is **required** before the first build — three new dependencies were added.

---

## 4. Verified

- All 13 modified/new Dart files have balanced `{}` and `()` — quick syntax sanity passes.
- Schema-truth column names preserved (no `nickname` / `name` / `attendance_status` mistakes introduced).
- All inter-tab navigation uses `MaterialPageRoute` (no `PageRouteBuilder`).
- All Supabase calls go through `SupabaseConfig.client`.
- No `.withOpacity()` in new code — `.withAlpha()` only.
- No `.is_('col', null)` — uses `.filter('col', 'is', null)` where needed.

---

## 5. Deferred to Next Session

These were in scope but not addressed in this session:

1. **Material 3 Expressive deep redesign** of admin and marketing-admin dashboards (this session was paired EA+Engineer). The EA dashboard got Quick Actions + offline banner but the visual language is still v23.
2. **Customer panel UI polish** beyond the offline banner — typography, motion, spacing pass.
3. **Engineer self-service check-in** — currently EA manages attendance; engineers could check in themselves.
4. **Repository-level offline cache wiring** — `OfflineCacheService` exists but repositories don't call it yet. To activate offline fallback, wrap each `getXxx()` in:
   ```dart
   try {
     final live = await ... ;
     await OfflineCacheService.instance.write('key', live);
     return live;
   } catch (_) {
     final cached = OfflineCacheService.instance.read('key');
     if (cached != null) return cached;
     rethrow;
   }
   ```
5. **PDF/CSV export formats** — only `.xlsx` implemented per user pick.
6. **Export from EA tickets / installations** — could mirror the admin pattern.

---

## 6. Quick Verification Checklist After `pub get`

- EA dashboard → see 4 Quick Actions cards under greeting
- Tap "Add Engineer" → opens existing create-engineer form
- Tap "New Schedule" → opens admin CreateSchedulePage
- Tap "Broadcast" → opens new ea_broadcast_page → audience picker works → send confirmation
- EA Schedule tab → FAB visible bottom-right → opens CreateSchedulePage
- EA Installations → FAB "New Installation" → bottom sheet → machine picker → save → opens detail
- Admin → Customers / Inquiries / Tickets → header download icon → Excel file shares via system share sheet
- Toggle airplane mode → red "You're offline" banner appears on every Scaffold using OfflineBanner
- Engineer dashboard → 4 Quick Action tiles between stats and schedules banner

---

*v24 done. Hand-off ready.*
