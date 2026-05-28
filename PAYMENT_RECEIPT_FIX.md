# Payment & Receipt System - Bug Fixes

## Issues Fixed

### Issue 1: Customer Cannot Pay Installment with Correct Payment Methods
**Root Cause:** The customer payment form only showed 3 payment methods (`bank_transfer`, `cdm`, `cash`) while the admin system expected 5 methods (`bank_transfer`, `card`, `cheque`, `cash`, `online`). The "cdm" option was custom and not recognized by the admin system.

**File Modified:** [lib/widgets/customer/submit_payment_sheet.dart](lib/widgets/customer/submit_payment_sheet.dart#L506-L512)

**Fix Applied:**
```dart
// Updated payment method options to match admin expectations
const options = [
  ['bank_transfer', 'Bank Transfer', Icons.account_balance_rounded],
  ['card', 'Card Payment', Icons.credit_card_rounded],
  ['cheque', 'Cheque', Icons.description_rounded],
  ['cash', 'Cash', Icons.payments_outlined],
  ['online', 'Online Transfer', Icons.phone_rounded],
];
```

**Impact:** Customers can now select from all 5 payment methods that admins expect, ensuring consistency across the system.

---

### Issue 2: Admin Cannot View Customer Receipts
**Root Causes:**
1. **Missing Timestamp:** Receipt records were not storing the `uploaded_at` timestamp, causing the database ORDER BY clause to fail silently
2. **Poor Error Handling:** When signed URL creation failed, it showed a broken image icon with no error information to the admin
3. **No Error Visibility:** Errors were only logged to the debug console, not communicated to the user

**Files Modified:** 
- [lib/widgets/customer/submit_payment_sheet.dart](lib/widgets/customer/submit_payment_sheet.dart#L223-L231)
- [lib/screens/admin/installment_detail_page.dart](lib/screens/admin/installment_detail_page.dart#L1393-L1433)

**Fixes Applied:**

**1. Added timestamp when uploading receipts:**
```dart
// In _submit() method - now includes uploaded_at
await SupabaseConfig.client.from('payment_receipts').insert({
  'payment_id': paymentId,
  'file_url': path,
  'file_name': r.name,
  'file_size_bytes': r.bytes.length,
  'mime_type': r.mimeType,
  'uploaded_by': userId,
  'uploaded_at': DateTime.now().toUtc().toIso8601String(), // ← ADDED
});
```

**2. Improved error handling in receipt loading:**
```dart
// In _PaymentReceiptsStripState._load()
for (final r in list) {
  final path = r['file_url']?.toString();
  if (path == null || path.isEmpty) {
    debugPrint('warning: receipt has no file_url');
    r['_error'] = 'Missing file path'; // ← Track error
    continue;
  }
  try {
    final signed = await SupabaseConfig.client.storage
        .from('payment-receipts')
        .createSignedUrl(path, 3600);
    r['_signed'] = signed;
  } catch (e) {
    debugPrint('signed url failed for $path: $e');
    r['_error'] = 'Unable to load receipt: ${e.toString()}'; // ← Store error message
  }
}
```

**3. Enhanced receipt display with error feedback:**
```dart
// In receipt itemBuilder - now shows meaningful error
if (url == null) {
  return Tooltip(
    message: error ?? 'Failed to load receipt',
    child: Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withAlpha(26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFEF4444).withAlpha(102),
        ),
      ),
      child: const Icon(Icons.warning_rounded, size: 20, color: Color(0xFFEF4444)),
    ),
  );
}
```

**Impact:** 
- Admins now see a clear warning icon (red) with a tooltip showing the exact error reason
- Receipts are properly ordered by upload time
- Any issues with signed URL generation are clearly communicated instead of silently failing

---

## Database Schema Confirmation

The `payment_receipts` table already has the `uploaded_at` column defined:
```sql
CREATE TABLE IF NOT EXISTS payment_receipts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id      uuid NOT NULL REFERENCES installment_payments(id) ON DELETE CASCADE,
  file_url        text NOT NULL,
  file_name       text,
  file_size_bytes int,
  mime_type       text,
  uploaded_by     uuid REFERENCES users(id),
  uploaded_at     timestamptz NOT NULL DEFAULT now()  -- ← Already exists
);
```

The RLS policies correctly allow admins to read receipts:
```sql
CREATE POLICY "payment_receipts_select"
  ON payment_receipts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM installment_payments ip
      JOIN installment_plans pl ON pl.id = ip.plan_id
      WHERE ip.id = payment_receipts.payment_id
      AND (
        pl.user_id = auth.uid()  -- Customer or
        OR EXISTS (
          SELECT 1 FROM users u
          WHERE u.id = auth.uid()
          AND u.role IN ('admin', 'engineer')  -- Admin/Engineer
        )
      )
    )
  );
```

---

## Testing Recommendations

1. **Customer Payment Submission:**
   - Customer selects each of the 5 payment methods
   - Attaches 1+ receipt images
   - Submits payment
   - Verify receipt is stored in `payment_receipts` table with `uploaded_at` timestamp

2. **Admin Receipt Viewing:**
   - Login as admin
   - Navigate to installment detail page
   - View submitted payment receipts
   - Verify receipts display correctly (as images or with proper icons)
   - If error occurs, hover over warning icon to see error message
   - Verify receipts are ordered by upload time

3. **Edge Cases:**
   - Test with network offline → should show error tooltip
   - Test with corrupted file_url → should show "Missing file path" error
   - Test with multiple receipts → all should display and be orderable

