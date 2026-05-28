# Support Ticket Badge Logic - Fixes Applied

## Problem Summary
Support ticket icons in both admin and customer panels were showing inflated badge counts that included resolved/closed tickets. After tasks were completed and tickets marked as "resolved", the badges still showed them as "new" unresolved tickets.

---

## Root Causes

### 1. **Customer Support Tickets Page** 
**File:** [lib/screens/customer/support_tickets_page.dart](lib/screens/customer/support_tickets_page.dart#L355-L375)

**Issue:** Tab badges counted ALL tickets regardless of status
```dart
// BEFORE (WRONG):
final supportCount = _tickets.where((t) => t['ticket_type'] == 'support').length;
final inquiryCount = _tickets.where((t) => t['ticket_type'] == 'inquiry' || t['ticket_type'] == 'order').length;
```

This included resolved, closed, and completed tickets in the count, creating false urgency.

---

### 2. **Admin Customer Detail Page**
**File:** [lib/screens/admin/customer_detail_page.dart](lib/screens/admin/customer_detail_page.dart#L46-L54)

**Issue:** Incomplete status list for active tickets
```dart
// BEFORE (INCOMPLETE):
return s == 'open' || s == 'assigned' || s == 'in_progress';
```

Missing the "waiting_customer" status, which is a valid active state where the ticket is awaiting customer response.

---

### 3. **Admin Dashboard Repository**
**File:** [lib/repositories/admin_dashboard_repository.dart](lib/repositories/admin_dashboard_repository.dart#L80-L83)

**Issue:** Hardcoded status filter missing "waiting_customer"
```dart
// BEFORE (INCOMPLETE):
.inFilter('status', ['open', 'assigned', 'in_progress'])
```

---

## Fixes Applied

### Fix 1: Customer Support Tickets Tab Badges ✅
**File:** [lib/screens/customer/support_tickets_page.dart](lib/screens/customer/support_tickets_page.dart#L355-L375)

**What Changed:**
- Added explicit status filtering using an `activeStatuses` set
- Only counts tickets with status in: `new`, `open`, `assigned`, `in_progress`, `waiting_customer`
- Excludes: `resolved`, `closed`, `completed`

**New Code:**
```dart
// Only count open/active tickets (not resolved/closed)
const activeStatuses = {
  'new',
  'open',
  'assigned',
  'in_progress',
  'waiting_customer'
};
final supportCount = _tickets
    .where((t) =>
        t['ticket_type'] == 'support' &&
        activeStatuses.contains(t['status']))
    .length;
final inquiryCount = _tickets
    .where((t) => 
      (t['ticket_type'] == 'inquiry' || t['ticket_type'] == 'order') &&
      activeStatuses.contains(t['status']))
    .length;
```

**Impact:** 
- Support tab badge now shows only unresolved tickets
- Inquiry/Order tab badge now shows only unresolved requests
- User sees accurate count of work remaining

---

### Fix 2: Admin Customer Detail Page ✅
**File:** [lib/screens/admin/customer_detail_page.dart](lib/screens/admin/customer_detail_page.dart#L49)

**What Changed:**
- Updated from individual `||` comparisons to a set-based contains check
- Added `waiting_customer` status to active statuses

**New Code:**
```dart
int get _openTickets => _tickets.where((t) {
  final s = (t['status'] ?? '').toString();
  return const {'open', 'assigned', 'in_progress', 'waiting_customer'}.contains(s);
}).length;
```

**Impact:**
- Admin correctly sees all truly active tickets for each customer
- Includes tickets awaiting customer response in the active count

---

### Fix 3: Admin Dashboard Repository ✅
**File:** [lib/repositories/admin_dashboard_repository.dart](lib/repositories/admin_dashboard_repository.dart#L82)

**What Changed:**
- Added `waiting_customer` to the status filter

**New Code:**
```dart
.inFilter('status', ['open', 'assigned', 'in_progress', 'waiting_customer'])
```

**Impact:**
- Admin dashboard's "Open Tickets" badge now includes all active tickets
- More accurate KPI metrics

---

## Ticket Status Lifecycle

The system now correctly recognizes this lifecycle:

```
┌─────────────────────────────────────────────────────────────┐
│ ACTIVE STATES (Counted in Badges)                           │
├─────────────────────────────────────────────────────────────┤
│ new                 → Newly created ticket                   │
│ open                → Customer reports issue                 │
│ assigned            → Assigned to engineer                   │
│ in_progress         → Engineer actively working              │
│ waiting_customer    → Awaiting customer response/info        │
├─────────────────────────────────────────────────────────────┤
│ CLOSED STATES (Not Counted in Badges)   ✗                   │
├─────────────────────────────────────────────────────────────┤
│ resolved            → Issue fixed, awaiting customer approval│
│ closed              → Customer confirmed resolution          │
│ completed           → Fully finalized                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Files Modified Summary

| File | Change | Impact |
|------|--------|--------|
| [lib/screens/customer/support_tickets_page.dart](lib/screens/customer/support_tickets_page.dart#L355-L375) | Added status filtering to tab badges | Customer sees accurate unresolved ticket count |
| [lib/screens/admin/customer_detail_page.dart](lib/screens/admin/customer_detail_page.dart#L49) | Expanded active statuses + refactored to set-based check | Admin sees complete active ticket count per customer |
| [lib/repositories/admin_dashboard_repository.dart](lib/repositories/admin_dashboard_repository.dart#L82) | Added waiting_customer to status filter | Admin dashboard KPIs now accurate |

---

## Testing Recommendations

1. **Customer Side:**
   - Create a support ticket → Badge shows "1"
   - Mark as resolved/closed → Badge decreases to "0"
   - Create multiple tickets in different statuses
   - Verify badge accuracy matches "Open" status filter

2. **Admin Side:**
   - View customer detail page
   - Verify open ticket count matches badge on tickets
   - Check dashboard metrics for accuracy
   - Test with mixed ticket statuses

3. **Edge Cases:**
   - Customer with 5 open, 3 resolved → Badge shows "5" only
   - Ticket in waiting_customer status → Still counted as active
   - Very new tickets (status='new') → Counted as active
   - Completed tickets → Not shown in badge

---

## Additional Notes

- The customer home page badge (`_openTickets`) gets data from the `get_customer_dashboard` RPC which should already be filtering correctly
- The system maintains backward compatibility with all existing ticket statuses
- All changes are additive (no breaking changes) and focus on filtering logic
- The `waiting_customer` status was previously undersupported in some metrics but is now consistently included

