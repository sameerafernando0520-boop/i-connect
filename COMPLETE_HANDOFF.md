# iConnect - Complete Handoff Document

**Version:** 18  
**Date:** April 5, 2026  
**Stack:** Flutter + Dart, Supabase, Firebase, Provider  

---

## Table of Contents

1. [App Overview](#1-app-overview)
2. [Architecture & Launch Flow](#2-architecture--launch-flow)
3. [Role-Based Access & Navigation](#3-role-based-access--navigation)
4. [Database Schema](#4-database-schema)
5. [Screen Inventory by Role](#5-screen-inventory-by-role)
6. [Screen Details](#6-screen-details)
7. [Key Services & Utilities](#7-key-services--utilities)
8. [Handoff Checklist](#8-handoff-checklist)

---

## 1. App Overview

**iConnect** is a role-based Flutter mobile application for managing industrial machine sales, support, and service scheduling across three user types:

- **Customer** — Purchase and manage machines, create support tickets, view invoices/installments
- **Engineer** — Manage assigned work tickets and service schedules
- **Admin** — Full platform administration: customer management, engineer assignment, sales inquiries, payments, analytics

### Core Dependencies

```yaml
supabase_flutter          # Auth + real-time database
firebase_core             # Push notifications foundation
provider                  # State management
flutter_localizations     # Multi-language support
cached_network_image      # Image caching
intl                      # Date/number formatting
flutter_dotenv            # Environment variable management
```

### Environment Configuration

Uses `.env` file (not committed to git). Load order in `main.dart`:

1. `dotenv.load(fileName: '.env')`
2. `Firebase.initializeApp()`
3. `SupabaseConfig.initialize()` ← reads `SUPABASE_URL` and `SUPABASE_ANON_KEY`
4. `NotificationService().initialize()`

---

## 2. Architecture & Launch Flow

### Singleton Pattern

```dart
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
```

Used throughout the app for deep links and role-based navigation.

### Launch Sequence

```
main()
  ├─ Load .env
  ├─ Initialize Firebase
  ├─ Initialize Supabase
  ├─ Initialize NotificationService
  └─ runApp(MyApp)
      └─ SplashScreen (3-second delay)
          ├─ Check auth state
          ├─ Fetch user role
          ├─ Register FCM token
          └─ Navigate by role
              ├─ admin → AdminDashboard
              ├─ engineer → EngineerDashboard
              └─ customer → HomePage
```

### Auth Flow

1. **Sign-Up** (`SignupPage`)
   - Accepts optional `referralCode` from deep links
   - Creates user in `users` table
   - Stores tier info and referral association

2. **Login** (`LoginPage`)
   - Supabase email/password auth
   - Creates session

3. **Auth State Listener**
   - Subscribes to `SupabaseConfig.client.auth.onAuthStateChange`
   - On `signedIn`: loads user role and navigates
   - On `signedOut`: clears locale
   - Registers FCM token on login
   - Subscribes to role-based FCM topics

### Deep Link Handling

- **Scheme:** `iconnect://`
- **Known routes:**
  - `iconnect://ref/<code>` → Opens signup with referral code
  - `iconnect://auth-callback` → Handled by auth listener

---

## 3. Role-Based Access & Navigation

### Role Model

Users are stored in the `users` table with a `role` field set to one of:
- `'customer'`
- `'engineer'`
- `'admin'`

### Navigation by Role

After login, auth listener calls `_navigateByRole(role)`:

```dart
switch (role) {
  case 'admin':
    destination = const AdminDashboard();
  case 'engineer':
    destination = const EngineerDashboard();
  default:
    destination = const HomePage(); // customer
}
```

### FCM Topic Subscriptions

Topics derived from role (in `NotificationService`):
- `admin_notifications`
- `engineer_notifications`
- `customer_notifications`

---

## 4. Database Schema

### Core Tables

#### **users**

```
id                 UUID (PK, FK to auth.users)
full_name          TEXT
email              TEXT
phone_number       TEXT
company_name       TEXT (nullable)
profile_photo      TEXT URL (nullable)
role               TEXT ('customer' | 'engineer' | 'admin')
specializations    JSONB array (engineers)
availability_status TEXT (engineers)
tier               TEXT (customers: 'basic' | 'premium' | 'enterprise')
tier_expiry_date   TIMESTAMP (nullable)
daily_login_streak INT (default 0)
last_login_date    DATE
created_at         TIMESTAMP
updated_at         TIMESTAMP
```

**Indexes:**
- `(role)` for role-based queries
- `(email)` for uniqueness

---

#### **service_tickets**

Core tickets for customer support, service requests, and sales inquiries.

```
id                      UUID (PK)
ticket_number           TEXT (unique, human-readable)
user_id                 UUID (FK→users, customer)
assigned_to             UUID (FK→users, engineer/admin, nullable)
customer_machine_id     UUID (FK→customer_machines, nullable)
catalog_machine_id      UUID (FK→machine_catalog, nullable - for ordered machines)

-- Ticket Classification
ticket_type             TEXT ('support' | 'service' | 'inquiry' | 'maintenance')
subject                 TEXT
description             TEXT (nullable)
status                  TEXT ('open' | 'in_progress' | 'on_hold' | 'resolved' | 'closed')
priority                TEXT ('low' | 'medium' | 'high' | 'urgent')
category                TEXT (nullable, e.g., 'mechanical', 'electrical')

-- Sales/Inquiry Fields
sales_stage             TEXT (nullable, 'new' | 'contacted' | 'quoted' | 'negotiating' | 'won')
quantity                INT (for orders, default 1)
deliveryAddress         TEXT (nullable)
estimatedResolution     TIMESTAMP (nullable)

-- Escalation
escalated               BOOLEAN (default false)
escalated_at            TIMESTAMP (nullable)
escalation_reason       TEXT (nullable)

-- Customer Feedback
customer_rating         INT (1-5, nullable)
customer_feedback       TEXT (nullable)

-- Timing & History
first_response_at       TIMESTAMP (nullable)
reopened_count          INT (default 0)
closed_at               TIMESTAMP (nullable)
created_at              TIMESTAMP
updated_at              TIMESTAMP

-- Admin Notes
admin_notes             TEXT (nullable)

-- Metadata (JSONB)
metadata                JSONB {
                          'additional_requirements': string,
                          'expected_delivery': string,
                          ...other context
                        }
```

**Indexes:**
- `(user_id, status)` for customer ticket filtering
- `(assigned_to, status)` for engineer ticket lists
- `(status)` for admin dashboards
- `(ticket_type)` for role-specific views
- `(created_at DESC)` for recent activity

---

#### **customer_machines**

Machines owned/registered by customers.

```
id                      UUID (PK)
user_id                 UUID (FK→users)
catalog_machine_id      UUID (FK→machine_catalog)

-- Machine Instance Info
serial_number           TEXT (unique)
purchase_date           TIMESTAMP
warranty_end_date       TIMESTAMP (nullable)
installation_date       TIMESTAMP (nullable)
status                  TEXT ('active' | 'inactive' | 'under_warranty' | 'expired_warranty')

-- Photos/Document
photos                  TEXT[] (array of URLs)

-- Tracking
created_at              TIMESTAMP
updated_at              TIMESTAMP
```

**Indexes:**
- `(user_id)` for customer machine list
- `(serial_number)` for machine lookup
- `(catalog_machine_id)` for analytics

---

#### **machine_catalog**

Master catalog of available machine models.

```
id                      UUID (PK)
machine_name            TEXT
brand                   TEXT
model_number            TEXT
category                TEXT ('laser' | 'cnc' | other)
description             TEXT (nullable)
specifications          JSONB {
                          'power': '...',
                          'dimensions': '...',
                          'features': [...]
                        }
image_url               TEXT (nullable)
price                   NUMERIC (nullable)
created_at              TIMESTAMP
updated_at              TIMESTAMP
```

---

#### **chat_messages**

Messages within tickets (customer/engineer/admin conversations).

```
id                      UUID (PK)
ticket_id               UUID (FK→service_tickets)
sender_id               UUID (FK→users)
sender_type             TEXT ('customer' | 'engineer' | 'admin')
message                 TEXT
attachments             TEXT[] (array of file URLs)
is_internal             BOOLEAN (only visible to admin/engineer)
is_read                 BOOLEAN (default false)
read_at                 TIMESTAMP (nullable)
created_at              TIMESTAMP
```

**Indexes:**
- `(ticket_id, created_at)` for message ordering
- `(sender_id)` for user activity tracking

---

#### **service_schedules**

Scheduled service appointments.

```
id                      UUID (PK)
customer_id             UUID (FK→users)
engineer_id             UUID (FK→users, nullable)
customer_machine_id     UUID (FK→customer_machines, nullable)
ticket_id               UUID (FK→service_tickets, nullable)

-- Scheduling
scheduled_date          DATE
scheduled_time          TIME
duration_minutes        INT
status                  TEXT ('pending' | 'confirmed' | 'completed' | 'cancelled')

-- Location & Details
location                TEXT (nullable)
notes                   TEXT (nullable)

-- Tracking
created_at              TIMESTAMP
updated_at              TIMESTAMP
```

**Indexes:**
- `(engineer_id, scheduled_date)` for engineer schedule
- `(customer_id, scheduled_date)` for customer schedule

---

#### **invoices**

Customer invoices.

```
id                      UUID (PK)
invoice_number          TEXT (unique)
user_id                 UUID (FK→users)
ticket_id               UUID (FK→service_tickets, nullable)
status                  TEXT ('draft' | 'sent' | 'paid' | 'overdue' | 'cancelled')

-- Amounts
subtotal                NUMERIC
tax_amount              NUMERIC
total_amount            NUMERIC
paid_amount             NUMERIC (default 0)

-- Dates
issue_date              TIMESTAMP
due_date                TIMESTAMP
paid_at                 TIMESTAMP (nullable)

-- Metadata
notes                   TEXT (nullable)
created_at              TIMESTAMP
updated_at              TIMESTAMP
```

**Indexes:**
- `(user_id, status)` for customer invoice list
- `(status)` for payment tracking
- `(due_date)` for overdue alerts

---

#### **invoice_items**

Line items for invoices.

```
id                      UUID (PK)
invoice_id              UUID (FK→invoices)
description             TEXT
quantity                INT
unit_price              NUMERIC
total_price             NUMERIC (quantity × unit_price)
```

---

#### **payments**

Payment records against invoices.

```
id                      UUID (PK)
invoice_id              UUID (FK→invoices)
user_id                 UUID (FK→users)
amount                  NUMERIC
payment_method          TEXT ('card' | 'bank_transfer' | 'cheque')
payment_date            TIMESTAMP
reference               TEXT (transaction ID, nullable)
status                  TEXT ('pending' | 'completed' | 'failed')
created_at              TIMESTAMP
```

---

#### **installment_plans**

Payment plans allowing customers to pay invoices in installments.

```
id                      UUID (PK)
invoice_id              UUID (FK→invoices)
user_id                 UUID (FK→users)
status                  TEXT ('active' | 'completed' | 'defaulted')
total_amount            NUMERIC
installments_count      INT
created_at              TIMESTAMP
```

---

#### **installment_payments**

Individual installment due dates and payment records.

```
id                      UUID (PK)
installment_plan_id     UUID (FK→installment_plans)
invoice_id              UUID (FK→invoices)
user_id                 UUID (FK→users)
due_date                TIMESTAMP
amount                  NUMERIC
status                  TEXT ('pending' | 'paid' | 'overdue')
paid_at                 TIMESTAMP (nullable)
created_at              TIMESTAMP
```

**Indexes:**
- `(user_id, due_date)` for customer upcoming payments
- `(status)` for admin collections tracking

---

#### **ticket_activities**

Audit log of changes to tickets.

```
id                      UUID (PK)
ticket_id               UUID (FK→service_tickets)
actor_id                UUID (FK→users)
action_type             TEXT ('created' | 'updated' | 'assigned' | 'escalated' | 'closed')
field_changed           TEXT (nullable)
old_value               TEXT (nullable)
new_value               TEXT (nullable)
created_at              TIMESTAMP
```

---

#### **referrals**

Tracking referral program participation.

```
id                      UUID (PK)
referrer_id             UUID (FK→users)
referred_user_id        UUID (FK→users, nullable - may not signup yet)
referral_code           TEXT (unique)
status                  TEXT ('pending' | 'completed' | 'expired')
reward_amount           NUMERIC (nullable)
reward_claimed_at       TIMESTAMP (nullable)
created_at              TIMESTAMP
expires_at              TIMESTAMP
```

---

#### **referral_commission_rules**

Admin-configurable referral reward rules.

```
id                      UUID (PK)
rule_name               TEXT
reward_type             TEXT ('fixed' | 'percentage')
reward_value            NUMERIC
description             TEXT (nullable)
is_active               BOOLEAN (default true)
created_at              TIMESTAMP
updated_at              TIMESTAMP
```

---

#### **notifications**

In-app and push notifications.

```
id                      UUID (PK)
user_id                 UUID (FK→users, nullable)
title                   TEXT
body                    TEXT
data                    JSONB (nullable - action/link metadata)
notification_type       TEXT ('ticket' | 'invoice' | 'schedule' | 'payment' | 'broadcast')
is_read                 BOOLEAN (default false)
read_at                 TIMESTAMP (nullable)
created_at              TIMESTAMP
```

---

#### **notification_settings**

User preferences for notification delivery.

```
id                      UUID (PK)
user_id                 UUID (FK→users, unique)
push_enabled            BOOLEAN (default true)
email_enabled           BOOLEAN (default true)
ticket_updates          BOOLEAN (default true)
payment_reminders       BOOLEAN (default true)
marketing_emails        BOOLEAN (default false)
created_at              TIMESTAMP
updated_at              TIMESTAMP
```

---

#### **fcm_tokens**

Firebase Cloud Messaging tokens for push notifications.

```
id                      UUID (PK)
user_id                 UUID (FK→users)
token                   TEXT (unique)
platform                TEXT ('ios' | 'android' | 'web')
is_active               BOOLEAN (default true)
created_at              TIMESTAMP
updated_at              TIMESTAMP
```

**Indexes:**
- `(user_id)` for token management during logout

---

### Storage Buckets

Three public buckets for file uploads:

1. **`machine-photos`** — Customer machine registration photos
2. **`ticket-attachments`** — Ticket conversation attachments
3. **`profile-photos`** — User profile pictures

---

## 5. Screen Inventory by Role

### Common/Auth Screens

| Screen | File | Purpose |
|--------|------|---------|
| SplashScreen | `lib/screens/splash_screen.dart` | Animated brand intro + auth routing |
| LoginPage | `lib/screens/auth/login_page.dart` | Email/password login |
| SignupPage | `lib/screens/auth/signup_page.dart` | Registration + referral code support |

### Customer Screens (28 screens)

| Screen | File | Purpose |
|--------|------|---------|
| HomePage | `lib/screens/customer/home_page.dart` | Dashboard: machines, tickets, payments, quick actions |
| ProfilePage | `lib/screens/customer/profile_page.dart` | Personal account settings |
| MyMachinesPage | `lib/screens/customer/my_machines_page.dart` | List customer machines |
| MyMachineDetailPage | `lib/screens/customer/my_machine_detail_page.dart` | Detail view of owned machine |
| MachineDetailPage | `lib/screens/customer/machine_detail_page.dart` | General machine info (catalog or owned) |
| RegisterMachinePage | `lib/screens/customer/register_machine_page.dart` | Register new machine form |
| MyInvoicesPage | `lib/screens/customer/my_invoices_page.dart` | Invoice list (paid/unpaid) |
| CustomerInvoiceDetailPage | `lib/screens/customer/customer_invoice_detail_page.dart` | Invoice detail + payment history |
| CustomerInstallmentsPage | `lib/screens/customer/customer_installments_page.dart` | Installment plan view |
| MyQuotationsPage | `lib/screens/customer/my_quotations_page.dart` | Quotation history |
| MySchedulePage | `lib/screens/customer/my_schedule_page.dart` | Upcoming service schedule |
| SupportOptionsHub | `lib/screens/customer/support_options_hub.dart` | Support entry point (tickets/knowledge) |
| SupportTicketsPage | `lib/screens/customer/support_tickets_page.dart` | Ticket list |
| CreateSupportTicketPage | `lib/screens/customer/create_support_ticket_page.dart` | New ticket form |
| TicketDetailPage | `lib/screens/customer/ticket_detail_page.dart` | Ticket detail + conversation |
| RequestServicePage | `lib/screens/customer/request_service_page.dart` | Schedule service request |
| CatalogPage | `lib/screens/customer/catalog_page.dart` | Machine catalog (laser/cnc) |
| OrderFormPage | `lib/screens/customer/order_form_page.dart` | Order inquiry form |
| KnowledgeBasePage | `lib/screens/customer/knowledge_base_page.dart` | FAQ/articles hub |
| ArticleDetailPage | `lib/screens/customer/article_detail_page.dart` | Article detail view |
| NotificationListPage | `lib/screens/customer/notification_list_page.dart` | In-app notification feed |
| NotificationSettingsPage | `lib/screens/customer/notification_settings_page.dart` | Notification preferences |
| ReferralPage | `lib/screens/customer/referral_page.dart` | Referral program dashboard |

### Engineer Screens (5 screens)

| Screen | File | Purpose |
|--------|------|---------|
| EngineerDashboard | `lib/screens/engineer/engineer_dashboard.dart` | Main dashboard: tickets, schedule, actions |
| EngineerTicketListPage | `lib/screens/engineer/engineer_ticket_list_page.dart` | Assigned tickets list |
| EngineerTicketDetailPage | `lib/screens/engineer/engineer_ticket_detail_page.dart` | Ticket detail + conversation |
| EngineerSchedulePage | `lib/screens/engineer/engineer_schedule_page.dart` | Work schedule calendar |
| EngineerProfilePage | `lib/screens/engineer/engineer_profile_page.dart` | Profile + availability settings |

### Admin Screens (31 screens)

| Screen | File | Purpose |
|--------|------|---------|
| AdminDashboard | `lib/screens/admin/admin_dashboard.dart` | Main admin hub: metrics + navigation |
| AdminSettingsPage | `lib/screens/admin/admin_settings_page.dart` | Admin settings |
| TicketsManagementPage | `lib/screens/admin/tickets_management_page.dart` | All tickets triage |
| AdminTicketDetailPage | `lib/screens/admin/admin_ticket_detail_page.dart` | Ticket admin detail |
| ServiceCalendarPage | `lib/screens/admin/service_calendar_page.dart` | All service schedules calendar |
| ScheduleDetailPage | `lib/screens/admin/schedule_detail_page.dart` | Schedule detail view |
| CreateSchedulePage | `lib/screens/admin/create_schedule_page.dart` | Schedule creation |
| AnalyticsDashboardPage | `lib/screens/admin/analytics_dashboard.dart` | Reports & analytics |
| ReferralManagementPage | `lib/screens/admin/referral_management_page.dart` | Referral program management |
| ReferralRulesPage | `lib/screens/admin/referral_rules_page.dart` | Reward rules config |
| QuotationManagementPage | `lib/screens/admin/quotation_management_page.dart` | Quotation list |
| AdminQuotationDetailPage | `lib/screens/admin/admin_quotation_detail_page.dart` | Quotation detail + approval |
| CreateQuotationPage | `lib/screens/admin/create_quotation_page.dart` | Create quotation |
| PaymentDashboardPage | `lib/screens/admin/payment_dashboard_page.dart` | Payment overview |
| AdminInvoiceDetailPage | `lib/screens/admin/admin_invoice_detail_page.dart` | Invoice detail (admin) |
| CreateInvoicePage | `lib/screens/admin/create_invoice_page.dart` | Invoice creation |
| AdminInstallmentsPage | `lib/screens/admin/admin_installments_page.dart` | Installments management |
| InstallmentDetailPage | `lib/screens/admin/installment_detail_page.dart` | Installment detail view |
| MachinesManagementPage | `lib/screens/admin/machines_management_page.dart` | Machine inventory management |
| AdminRegisterMachinePage | `lib/screens/admin/admin_register_machine_page.dart` | Register machine for customer |
| EngineerManagementPage | `lib/screens/admin/engineer_management_page.dart` | Engineer user management |
| CustomersManagementPage | `lib/screens/admin/customers_management_page.dart` | Customer list |
| CustomerDetailPage | `lib/screens/admin/customer_detail_page.dart` | Customer profile (admin) |
| InquiryManagementPage | `lib/screens/admin/inquiry_management_page.dart` | Sales inquiries list |
| InquiryDetailPage | `lib/screens/admin/inquiry_detail_page.dart` | Inquiry detail |
| InquiryChatPage | `lib/screens/admin/inquiry_chat_page.dart` | Inquiry conversation |
| TierManagementPage | `lib/screens/admin/tier_management_page.dart` | Customer tier configuration |
| BroadcastNotificationsPage | `lib/screens/admin/broadcast_notifications.dart` | Send bulk notifications |
| AssignEngineerSheet | `lib/screens/admin/assign_engineer_sheet.dart` | Engineer assignment modal |

---

## 6. Screen Details

### Common Screens

#### **SplashScreen**

- **Path:** `lib/screens/splash_screen.dart`
- **Type:** Stateful
- **Lifecycle:** Entry point; always first screen
- **Features:**
  - Animated logo (fade-in + scale, 1.5s)
  - 3-second delay before auth check
  - Checks `SupabaseConfig.client.auth.currentUser`
  - Fetches user role from `users` table
  - Registers FCM token
  - Subscribes to role topics
  - Routes to:
    - `AdminDashboard` if role = 'admin'
    - `EngineerDashboard` if role = 'engineer'
    - `HomePage` if role = 'customer'
    - `LoginPage` if no session

---

#### **LoginPage**

- **Path:** `lib/screens/auth/login_page.dart`
- **Type:** Stateful
- **Features:**
  - Email + password input fields
  - Supabase email/password authentication
  - Link to `SignupPage`
  - Error handling (invalid credentials, network)
  - Post-login: auth listener routes by role

---

#### **SignupPage**

- **Path:** `lib/screens/auth/signup_page.dart`
- **Type:** Stateful
- **Constructor:** `SignupPage({super.key, String? referralCode})`
- **Features:**
  - Email, password, full name fields
  - Optional referral code (passed via deep link)
  - Role selection (customer by default)
  - Creates user record in `users` table
  - Associates referral if code provided
  - Validates email format and password strength
  - Post-signup: auth listener handles navigation

---

### Customer Screens

#### **HomePage**

- **Path:** `lib/screens/customer/home_page.dart`
- **Type:** Stateful
- **Features:**
  - Fetches dashboard data (RPC or queries)
  - Displays:
    - Dashboard metrics (machines, tickets, payments)
    - Recent activity (last 4 items)
    - Upcoming payments (due soon)
    - Quick action cards:
      - View machines
      - Create support ticket
      - Browse catalog
      - Refer & earn
      - View notifications
      - Knowledge base
  - Realtime subscriptions for notifications and machine updates
  - Tier system integration (displays tier badge)
  - Navigation to other customer screens
  - State variables:
    - `_selectedIndex` (bottom nav)
    - `_dashboard`, `_machines`, `_recentActivity`, `_upcomingPayments`
    - `_tierData`, `_dailyLoginChecked`
  - Methods:
    - `_loadAllData()` — Initial data fetch
    - `_fetchTierInfo()` — RPC call for tier data
    - `_refreshIfStale()` — Caching guard for realtime-triggered reloads

#### **ProfilePage**

- **Path:** `lib/screens/customer/profile_page.dart`
- **Type:** Stateful
- **Features:**
  - Displays user profile
  - Editable fields: full name, phone, company
  - Profile photo upload
  - Summary tabs:
    - Recent tickets
    - My machines
  - Settings:
    - Change password
    - Language selector
    - Logout

#### **MyMachinesPage**

- **Path:** `lib/screens/customer/my_machines_page.dart`
- **Type:** Stateful
- **Features:**
  - List of customer machines (from `customer_machines`)
  - Machine cards show:
    - Machine name, brand, model
    - Serial number
    - Warranty status
    - Status badge
  - Actions per card:
    - Tap to view detail
    - Edit machine
    - Delete machine
  - Floating action button to register new machine
  - Shimmer loading state
  - Search/filter by machine name or category

#### **MyMachineDetailPage**

- **Path:** `lib/screens/customer/my_machine_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Shows owned machine details
  - Joins `customer_machines` → `machine_catalog`
  - Displays:
    - Machine specs, images
    - Purchase date, warranty end date
    - Status timeline
    - Service history (related tickets)
    - Related invoices
  - Actions:
    - Create support ticket for this machine
    - Schedule service
    - View service history
    - Edit machine (serial, warranty)

#### **MachineDetailPage**

- **Path:** `lib/screens/customer/machine_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - General machine detail (may be from catalog or owned)
  - Full-screen image gallery
  - Technical specifications
  - Availability/pricing info
  - Action buttons:
    - Add to order / Inquire
    - Download specs PDF
  - Custom icons (`LaserIcon`, `CncIcon`)

#### **RegisterMachinePage**

- **Path:** `lib/screens/customer/register_machine_page.dart`
- **Type:** Stateful
- **Features:**
  - Form to register new machine
  - Fields:
    - Machine catalog selection (dropdown)
    - Serial number
    - Purchase date
    - Warranty expiry
    - Machine photos (upload multiple)
  - Validation:
    - Serial number uniqueness check
    - Date validations
  - Storage: uploads photos to `machine-photos` bucket
  - Creates record in `customer_machines` table
  - Success: creates notification + navigates back

#### **MyInvoicesPage**

- **Path:** `lib/screens/customer/my_invoices_page.dart`
- **Type:** Stateful
- **Features:**
  - List of invoices for logged-in user
  - Filters/tabs:
    - All
    - Paid
    - Pending
    - Overdue
  - Invoice cards show:
    - Invoice number
    - Date, due date
    - Amount
    - Status badge
  - Tap card → `CustomerInvoiceDetailPage`

#### **CustomerInvoiceDetailPage**

- **Path:** `lib/screens/customer/customer_invoice_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Invoice detail
  - Sections:
    - Invoice header (number, dates, status)
    - Line items (from `invoice_items`)
    - Subtotal, tax, total
    - Payment history (from `payments`)
  - Actions (if unpaid):
    - Pay now button
    - Payment method selector
    - Link to installment plan (if available)

#### **CustomerInstallmentsPage**

- **Path:** `lib/screens/customer/customer_installments_page.dart`
- **Type:** Stateful
- **Features:**
  - Shows all active installment plans (from `installment_plans`)
  - Per plan:
    - Total amount, installments count
    - Status (active / completed / defaulted)
    - Next payment due
  - Tap plan → list of `installment_payments`
    - Due date, amount, status (pending/paid)
  - Payment button for pending installments

#### **MyQuotationsPage**

- **Path:** `lib/screens/customer/my_quotations_page.dart`
- **Type:** Stateful
- **Features:**
  - List of quotations (tickets with `sales_stage != null` or type='inquiry')
  - Quotation cards show:
    - Subject
    - Machine/product info
    - Quote amount
    - Date
    - Status
  - Modal sheet for detail view (`_QuotationDetailPage`)
  - Actions: Accept/Reject quotation

#### **MySchedulePage**

- **Path:** `lib/screens/customer/my_schedule_page.dart`
- **Type:** Stateful
- **Features:**
  - Calendar or list view of `service_schedules` where `customer_id = userId`
  - Shows:
    - Scheduled date/time
    - Duration
    - Machine
    - Assigned engineer
    - Notes
  - Filters:
    - Upcoming
    - Past
  - Actions:
    - Reschedule
    - Cancel

#### **SupportOptionsHub**

- **Path:** `lib/screens/customer/support_options_hub.dart`
- **Type:** Stateful
- **Features:**
  - Entry point for support
  - Displays:
    - Recent open tickets (last few)
    - Available customer machines (for new ticket creation)
    - Quick action buttons:
      - Create support ticket
      - Browse knowledge base
      - View all tickets
      - Request service

#### **SupportTicketsPage**

- **Path:** `lib/screens/customer/support_tickets_page.dart`
- **Type:** Stateful
- **Features:**
  - List of customer's service tickets
  - Filters/tabs:
    - Open
    - In Progress
    - Resolved
    - Closed
  - Ticket cards show:
    - Ticket number, subject
    - Machine name (if applicable)
    - Status, priority
    - Last update
  - Tap card → `TicketDetailPage`
  - Floating action button → `CreateSupportTicketPage`

#### **CreateSupportTicketPage**

- **Path:** `lib/screens/customer/create_support_ticket_page.dart`
- **Type:** Stateful
- **Features:**
  - Form to create new ticket
  - Fields:
    - Ticket type (support/service/maintenance)
    - Select machine (from `customer_machines`)
    - Subject
    - Description
    - Priority
    - Category (optional)
    - Attachments (upload to `ticket-attachments`)
  - Validation:
    - Subject required
    - Description required
    - At least description or machine
  - Creates record in `service_tickets`
  - Success: navigates to ticket detail

#### **TicketDetailPage**

- **Path:** `lib/screens/customer/ticket_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Shows ticket detail from `service_tickets`
  - Sections:
    - Ticket header (number, subject, status, priority)
    - Machine info
    - Assigned engineer (if any)
    - Description
    - Timeline of `ticket_activities`
  - Chat section:
    - Loads `chat_messages` for this ticket
    - Realtime subscription for new messages
    - Input field to send message
    - Messages are paginated (load older on scroll)
    - Attachments support
  - Actions:
    - Update status (customer can only close)
    - Add rating + feedback (if resolved)
    - Reply with message

#### **RequestServicePage**

- **Path:** `lib/screens/customer/request_service_page.dart`
- **Type:** Stateful
- **Features:**
  - Form to request scheduled service
  - Fields:
    - Select machine
    - Preferred date/time
    - Duration estimate
    - Service type (maintenance/installation/repair)
    - Notes
  - Creates `service_schedule` record
  - Success: confirmation + navigates to schedule view

#### **CatalogPage**

- **Path:** `lib/screens/customer/catalog_page.dart`
- **Type:** Stateful
- **Features:**
  - Displays `machine_catalog` grouped by category (laser/cnc)
  - Custom icons (`LaserIcon`, `CncIcon`)
  - Machine grid/list:
    - Machine name, brand, image
    - Quick spec snippet
    - Price (if available)
  - Tap card → `MachineDetailPage`
  - Filter by category
  - Floating action button → `OrderFormPage`

#### **OrderFormPage**

- **Path:** `lib/screens/customer/order_form_page.dart`
- **Type:** Stateful
- **Features:**
  - Form to place order inquiry
  - Fields:
    - Machine selection (if not prefilled)
    - Quantity
    - Expected delivery date
    - Delivery address
    - Additional requirements (JSONB metadata)
    - Attachments (photos/documents)
  - Creates `service_ticket` with `ticket_type='inquiry'` and `sales_stage='new'`
  - Success: admin notified, customer sees confirmation

#### **KnowledgeBasePage**

- **Path:** `lib/screens/customer/knowledge_base_page.dart`
- **Type:** Stateful
- **Features:**
  - Displays articles / FAQ
  - Likely fetches from a `articles` or `help_content` table (not fully visible in schema)
  - Search / filter by category
  - Article cards:
    - Title, snippet, category
  - Tap → `ArticleDetailPage`

#### **ArticleDetailPage**

- **Path:** `lib/screens/customer/article_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Full article content
  - Title, author, publish date
  - Rich text content
  - Related articles recommendation
  - Helpful/not helpful voting (optional)

#### **NotificationListPage**

- **Path:** `lib/screens/customer/notification_list_page.dart`
- **Type:** Stateful
- **Features:**
  - In-app notification feed
  - Fetches from `notifications` table where `user_id = userId`
  - Infinite scroll pagination
  - Notification items show:
    - Title, body
    - Timestamp
    - Icon by type (ticket/invoice/schedule/payment)
    - Unread badge
  - Tap notification → navigates to relevant page (ticket, invoice, etc.)
  - Mark as read on tap
  - Delete notification action

#### **NotificationSettingsPage**

- **Path:** `lib/screens/customer/notification_settings_page.dart`
- **Type:** Stateful
- **Features:**
  - Editable toggles from `notification_settings`:
    - Push notifications
    - Email notifications
    - Ticket updates
    - Payment reminders
    - Marketing emails
  - Save changes → updates `notification_settings` record
  - Unsubscribe link (if applicable)

#### **ReferralPage**

- **Path:** `lib/screens/customer/referral_page.dart`
- **Type:** Stateful
- **Features:**
  - Referral program dashboard
  - Displays:
    - Unique referral code for this user
    - Referral stats (RPC call):
      - Total referred
      - Completed referrals
      - Rewards earned
      - Commission rules
    - List of referrals (from `referrals`)
      - Referral code generated
      - Status (pending/completed/expired)
      - Reward amount (if completed)
    - Commission rules (from `referral_commission_rules`)
  - Actions:
    - Copy referral code to clipboard
    - Share via link/social
    - View referral history

---

### Engineer Screens

#### **EngineerDashboard**

- **Path:** `lib/screens/engineer/engineer_dashboard.dart`
- **Type:** Stateful
- **Features:**
  - Displays engineer's dashboard
  - Sections:
    - Quick stats (assigned tickets, upcoming schedules, pending tasks)
    - Action cards:
      - View tickets
      - View schedule
      - Profile
      - Logout
    - Recent activity feed
  - Bottom navigation or sidebar:
    - Tickets tab
    - Schedule tab
    - Profile tab
  - Realtime updates for messages/notifications
  - State variables:
    - `_profile` (engineer user data)
    - `_unreadCount` (unread messages)

#### **EngineerTicketListPage**

- **Path:** `lib/screens/engineer/engineer_ticket_list_page.dart`
- **Type:** Stateful
- **Features:**
  - Lists `service_tickets` where `assigned_to = engineerId`
  - Filters/tabs:
    - Open
    - In Progress
    - On Hold
    - Resolved
  - Ticket cards:
    - Ticket number, subject
    - Priority, category
    - Customer name
    - Machine (if applicable)
    - Last update, unread message count
  - Tap card → `EngineerTicketDetailPage`
  - Realtime subscription for new messages

#### **EngineerTicketDetailPage**

- **Path:** `lib/screens/engineer/engineer_ticket_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Detail view of assigned ticket
  - Sections:
    - Ticket header (number, subject, status)
    - Priority, escalation info
    - Customer details (from join)
    - Machine details (if applicable)
    - Metadata / description
  - Chat:
    - Messages from `chat_messages`
    - Pagination support
    - Send message (internal or visible to customer)
    - Toggle `is_internal` flag
    - Attachments
  - Timeline:
    - Recent activities
    - Status changes
  - Actions:
    - Update ticket status
    - Add internal notes
    - Mark as escalated
    - Request more info from customer
    - Close ticket
  - Realtime:
    - Subscribe to new messages
    - Push notification on new message

#### **EngineerSchedulePage**

- **Path:** `lib/screens/engineer/engineer_schedule_page.dart`
- **Type:** Stateful
- **Features:**
  - Calendar or list view of `service_schedules` where `engineer_id = engineerId`
  - Shows scheduled appointments:
    - Date, time, duration
    - Customer name
    - Machine / location
    - Status
  - Actions per schedule:
    - Mark as completed
    - Reschedule
    - View details
    - Add notes
    - Confirm receipt
  - Realtime subscriptions for schedule changes

#### **EngineerProfilePage**

- **Path:** `lib/screens/engineer/engineer_profile_page.dart`
- **Type:** Stateful
- **Features:**
  - Engineer profile
  - Fields (editable):
    - Full name
    - Profile photo
    - Phone number
    - Specializations (tags/checkboxes)
    - Availability status (available / on-leave / busy)
  - Summary:
    - Total tickets assigned
    - Completed tickets
    - Average rating
  - Settings:
    - Change password
    - Language selector
    - Logout

---

### Admin Screens

#### **AdminDashboard**

- **Path:** `lib/screens/admin/admin_dashboard.dart`
- **Type:** Stateful
- **Features:**
  - Main admin hub
  - Displays:
    - KPI cards (metrics from `DashboardStats` RPC)
      - Total customers
      - Total machines
      - Open tickets
      - Total inquiries
      - Resolved tickets
      - Urgent tickets
      - New customers this month
      - Total revenue
    - Action cards (quick navigation):
      - Manage tickets
      - Manage customers
      - Manage engineers
      - Service calendar
      - Analytics
      - Referrals
      - Payments
      - Broadcast notifications
  - Recent inquiries section (last 5)
  - Realtime notifications subscription

#### **AdminSettingsPage**

- **Path:** `lib/screens/admin/admin_settings_page.dart`
- **Type:** Stateful
- **Features:**
  - Admin account settings
  - Configuration options:
    - Admin profile (name, email, password)
    - Company settings
    - API keys / integration settings
    - System configuration
    - Logout

#### **TicketsManagementPage**

- **Path:** `lib/screens/admin/tickets_management_page.dart`
- **Type:** Stateful
- **Features:**
  - All tickets across platform (from `service_tickets`)
  - Advanced filters:
    - Status (open/in_progress/on_hold/resolved/closed)
    - Priority
    - Ticket type
    - Assigned engineer
    - Date range
    - Search by subject/number
  - Ticket list:
    - Ticket number, subject
    - Customer, machine
    - Status, priority
    - Assigned engineer
    - Created date
  - Bulk actions:
    - Assign to engineer
    - Change status
    - Mark urgent
  - Tap ticket → `AdminTicketDetailPage`

#### **AdminTicketDetailPage**

- **Path:** `lib/screens/admin/admin_ticket_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Full admin view of ticket
  - Sections:
    - Ticket info
    - Customer info
    - Machine info
    - Chat (internal + customer-visible)
    - Activities log
    - Admin notes
  - Actions:
    - Assign/reassign engineer
    - Change status
    - Escalate / de-escalate
    - Add internal note
    - Send message to customer
    - Close ticket
    - Reopen ticket
    - View all related tickets from customer
  - Audit trail visible

#### **ServiceCalendarPage**

- **Path:** `lib/screens/admin/service_calendar_page.dart`
- **Type:** Stateful
- **Features:**
  - Calendar view of `service_schedules`
  - Shows all engineer schedules
  - Can filter by:
    - Engineer
    - Location
    - Status
  - Tap event → `ScheduleDetailPage`
  - Create new schedule button
  - Drag-to-reschedule support (if interactive)

#### **ScheduleDetailPage**

- **Path:** `lib/screens/admin/schedule_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Detail of a single `service_schedule`
  - Shows:
    - Date, time, duration
    - Engineer, customer, machine
    - Location / notes
    - Status
  - Actions:
    - Change status
    - Reassign engineer
    - Reschedule (date/time picker)
    - Add notes / communication
    - Confirm schedule
    - Cancel schedule

#### **CreateSchedulePage**

- **Path:** `lib/screens/admin/create_schedule_page.dart`
- **Type:** Stateful
- **Features:**
  - Form to create new service schedule
  - Fields:
    - Select engineer (uses `AssignEngineerSheet`)
    - Select customer (uses person picker sheet)
    - Select machine (uses machine picker sheet `_MachinePickerSheet`)
    - Date picker
    - Time picker
    - Duration
    - Notes
    - Related ticket (if from ticket detail)
  - Modal sheets:
    - `_PersonPickerSheet` — search/select engineer
    - `_MachinePickerSheet` — search/select machine
  - Validation:
    - Engineer required
    - Date/time in future
    - Duration positive
  - Creates `service_schedule` record

#### **AnalyticsDashboardPage**

- **Path:** `lib/screens/admin/analytics_dashboard.dart`
- **Type:** Stateful
- **Features:**
  - Reports and charts
  - Sections:
    - Revenue metrics (total, by month, by customer)
    - Ticket metrics (volume, resolution rate, avg resolution time)
    - Customer metrics (growth, churn, tier distribution)
    - Engineer performance (tickets resolved, ratings)
    - Machine sales analytics
  - Date range filters
  - Export to CSV/PDF (optional)
  - Charts (line/bar/pie)

#### **ReferralManagementPage**

- **Path:** `lib/screens/admin/referral_management_page.dart`
- **Type:** Stateful
- **Features:**
  - Manage referral program
  - Displays:
    - All active referrals (from `referrals`)
    - Filter by status (pending/completed/expired)
    - Referral info: code, referrer, referred user, status, reward
    - List of unclaimed rewards
  - Actions:
    - Manually complete referral
    - Adjust reward amount
    - Send reminder email

#### **ReferralRulesPage**

- **Path:** `lib/screens/admin/referral_rules_page.dart`
- **Type:** Stateful
- **Features:**
  - Configure referral reward rules (from `referral_commission_rules`)
  - Editable table:
    - Rule name
    - Reward type (fixed / percentage)
    - Reward amount
    - Active toggle
  - Actions per rule:
    - Edit
    - Delete
    - Create new rule
  - Preview: how rewards calculate

#### **QuotationManagementPage**

- **Path:** `lib/screens/admin/quotation_management_page.dart`
- **Type:** Stateful
- **Features:**
  - All quotations (tickets with type='inquiry')
  - Filter by:
    - Status
    - Sales stage
    - Date range
    - Assigned to
  - Quotation cards:
    - Subject, customer
    - Quote amount
    - Sales stage
    - Days since creation
  - Tap → `AdminQuotationDetailPage`

#### **AdminQuotationDetailPage**

- **Path:** `lib/screens/admin/admin_quotation_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Full quotation detail
  - Sections:
    - Quote info (amount, date)
    - Customer info
    - Machine / product info
    - Sales stage progression
    - Communication history
  - Actions:
    - Send quote to customer
    - Update sales stage (contacted/quoted/negotiating/won)
    - Convert to order/invoice
    - Add/edit quote amount
    - Send follow-up

#### **CreateQuotationPage**

- **Path:** `lib/screens/admin/create_quotation_page.dart`
- **Type:** Stateful
- **Features:**
  - Form to create quotation
  - Fields:
    - Search customer or create new inquiry
    - Machine / product selection
    - Quantity
    - Price per unit
    - Total quote amount
    - Additional remarks
    - Delivery terms
  - Creates `service_ticket` with `type='inquiry'`
  - Success: sends notification to customer

#### **PaymentDashboardPage**

- **Path:** `lib/screens/admin/payment_dashboard_page.dart`
- **Type:** Stateful
- **Features:**
  - Payment overview
  - Metrics:
    - Total revenue
    - Pending payments
    - Overdue payments
    - Payment methods breakdown
  - Transaction list (recent payments)
  - Filters:
    - Date range
    - Status (pending/completed/failed)
    - Payment method
  - Drill-down capabilities

#### **AdminInvoiceDetailPage**

- **Path:** `lib/screens/admin/admin_invoice_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Admin invoice view
  - Displays:
    - Invoice header (number, date, status)
    - Customer info
    - Line items (from `invoice_items`)
    - Subtotal, tax, total
    - Payment records
  - Actions:
    - Change status (draft/sent/paid/overdue/cancelled)
    - Record payment (opens `RecordPaymentSheet`)
    - Send invoice email
    - Edit line items
    - Generate PDF

#### **CreateInvoicePage**

- **Path:** `lib/screens/admin/create_invoice_page.dart`
- **Type:** Stateful
- **Features:**
  - Form to create invoice
  - Sections:
    - Select customer
    - Select ticket (optional)
    - Date, due date
    - Line items (add multiple):
      - Description, quantity, unit price
    - Tax rate / amount
    - Notes
    - Attachments
  - Validation:
    - Customer required
    - At least one line item
    - Positive amounts
  - Creates `invoices` + `invoice_items`
  - PDFpreview before save
  - Success: can email to customer immediately

#### **AdminInstallmentsPage**

- **Path:** `lib/screens/admin/admin_installments_page.dart`
- **Type:** Stateful
- **Features:**
  - Installment management
  - Displays:
    - All `installment_plans`
    - Filter by status (active/completed/defaulted)
    - Plan details: customer, invoice, total, count
    - Next due date
  - Tap plan → detail view with payment schedule
  - Actions:
    - View all payments in plan
    - Record payment
    - Modify plan (extend/adjust amount)
    - Send reminder

#### **InstallmentDetailPage**

- **Path:** `lib/screens/admin/installment_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Single installment plan detail
  - Plan overview (customer, invoice, amounts)
  - Payment schedule table:
    - Due date, amount, status (pending/paid/overdue)
    - Payment history per installment
  - Actions:
    - Record payment against installment
    - Extend due date
    - Mark as paid
    - Send reminder
    - View customer communication

#### **MachinesManagementPage**

- **Path:** `lib/screens/admin/machines_management_page.dart`
- **Type:** Stateful
- **Features:**
  - Machine inventory management
  - Displays:
    - `machine_catalog` + `customer_machines` (combined view)
    - Filter by:
      - Owned vs. catalog
      - Category
      - Status
      - Customer
  - Search by machine name/brand/model
  - Machine cards/table:
    - Name, brand, model
    - Category
    - Owner (if registered)
    - Status
  - Actions per machine:
    - View detail
    - Edit catalog entry
    - Tap → detail sheet (`_MachineDetailSheet`)
    - Edit (machine editor page `MachineEditorPage`)
  - Floating action → `AdminRegisterMachinePage`

#### **AdminRegisterMachinePage**

- **Path:** `lib/screens/admin/admin_register_machine_page.dart`
- **Type:** Stateful
- **Features:**
  - Form for admin to register machine on behalf of customer
  - Fields:
    - Select customer
    - Select machine from catalog (or search)
    - Serial number
    - Purchase date
    - Warranty details
    - Photos
  - Creates `customer_machines` record
  - Success: sends notification to customer

#### **EngineerManagementPage**

- **Path:** `lib/screens/admin/engineer_management_page.dart`
- **Type:** Stateful
- **Features:**
  - Engineer user management
  - Displays:
    - List of engineers (users with `role='engineer'`)
    - Engineer cards:
      - Name, email, phone
      - Specializations
      - Availability status
      - Assigned tickets count
      - Average rating
  - Actions:
    - Send invite email to new engineer
    - Edit engineer profile
    - Deactivate/activate engineer
    - View assigned tickets

#### **CustomersManagementPage**

- **Path:** `lib/screens/admin/customers_management_page.dart`
- **Type:** Stateful
- **Features:**
  - Customer list (users with `role='customer'`)
  - Search by name, email, company
  - Filter by:
    - Tier (basic/premium/enterprise)
    - Registration date
    - Activity status
  - Customer cards:
    - Name, company, email
    - Tier, registration date
    - Total machines
    - Open tickets count
  - Tap → `CustomerDetailPage`

#### **CustomerDetailPage**

- **Path:** `lib/screens/admin/customer_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Detailed admin view of customer
  - Sections:
    - Profile info (name, email, phone, company)
    - Tier + tier expiry
    - Machines (registered list)
    - Tickets (list of all tickets)
    - Invoices (list with status)
    - Referrals (if any)
  - Actions:
    - Edit customer info
    - Change tier
    - Send message
    - Register machine on behalf
    - Create ticket for customer
  - Quick links:
    - View related invoices
    - View related tickets

#### **InquiryManagementPage**

- **Path:** `lib/screens/admin/inquiry_management_page.dart`
- **Type:** Stateful
- **Features:**
  - Sales inquiries (tickets with `ticket_type='inquiry'`)
  - Filter by:
    - Sales stage (new/contacted/quoted/negotiating/won)
    - Priority
    - Hot lead flag
    - Date range
  - Inquiry board (kanban) or list:
    - Inquiry subject
    - Customer name
    - Machine/product
    - Deal value (if set)
    - Days in current stage
  - Tap → `InquiryDetailPage`

#### **InquiryDetailPage**

- **Path:** `lib/screens/admin/inquiry_detail_page.dart`
- **Type:** Stateful
- **Features:**
  - Full inquiry detail
  - Sections:
    - Inquiry info (subject, customer, machine)
    - Sales stage workflow
    - Deal value, quote amount
    - Communication history
  - Chat section → `InquiryChatPage`
  - Actions:
    - Move sales stage
    - Add internal note
    - Mark as hot lead
    - Set follow-up date
    - Create quotation
    - Convert to order/invoice

#### **InquiryChatPage**

- **Path:** `lib/screens/admin/inquiry_chat_page.dart`
- **Type:** Stateful
- **Features:**
  - Chat interface for inquiry
  - Conversation messages from `chat_messages`
  - Real time updates
  - Message input for admin to send to customer
  - Attachments support
  - Message history pagination

#### **TierManagementPage**

- **Path:** `lib/screens/admin/tier_management_page.dart`
- **Type:** Stateful
- **Features:**
  - Customer tier configuration
  - Editable tier definitions:
    - Tier name (basic/premium/enterprise)
    - Benefits (features/discounts/support level)
    - Price / renewal cost
    - Duration
    - Perks description
  - Admin can:
    - Create tier
    - Edit tier
    - Delete tier (if no active customers)
    - View tier members
    - Bulk update customer tiers

#### **BroadcastNotificationsPage**

- **Path:** `lib/screens/admin/broadcast_notifications.dart`
- **Type:** Stateful
- **Features:**
  - Send bulk notifications
  - Form:
    - Target audience (all users / role / specific users)
    - Title
    - Body message
    - Rich formatting options
    - Schedule send (now / later with datetime)
  - Preview:
    - How notification looks on mobile
  - Sends to FCM topics
  - Logs notifications in `notifications` table
  - Success: confirmation with delivery stats

#### **AssignEngineerSheet**

- **Path:** `lib/screens/admin/assign_engineer_sheet.dart`
- **Type:** Stateful  (Modal Sheet)
- **Features:**
  - Bottom sheet to select engineer
  - Search/filter engineers by:
    - Name
    - Specialization
    - Availability status
  - Shows engineer cards:
    - Name, specializations
    - Current workload
    - Availability
  - Select engineer → returns selected ID to caller

---

## 7. Key Services & Utilities

### **SupabaseConfig** (`lib/config/supabase_config.dart`)

Singleton wrapper around Supabase client.

```dart
static SupabaseClient get client => Supabase.instance.client;
static Future<void> initialize() async { ... }
```

**Key points:**
- Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `.env`
- Initializes once
- Use `SupabaseConfig.client` throughout app (never `Supabase.instance.client` directly)

### **NotificationService** (`lib/services/notification_service.dart`)

Manages Firebase Cloud Messaging and in-app notifications.

**Key methods:**
- `initialize()` — Subscribe to FCM
- `onLogin()` — Register/refresh FCM token
- `subscribeToRoleTopics(role)` — Subscribe to role-based topics
- `getNotificationSettings(userId)` — Fetch user preferences
- `updateNotificationSettings(userId, settings)` — Save preferences
- `markNotificationAsRead(id)` — Mark notification read
- `broadcastNotification(title, body, audience)` — Send bulk notification

**Storage:**
- FCM tokens stored in `fcm_tokens` table
- User preferences in `notification_settings` table
- Notifications logged in `notifications` table

### **ThemeProvider** (`lib/providers/theme_provider.dart`)

Manages app theme (light/dark mode).

```dart
class ThemeProvider extends ChangeNotifier {
  bool get isDarkMode => _isDarkMode;
  ThemeData get lightTheme => ...
  ThemeData get darkTheme => ...
  void toggleTheme() => ...
}
```

**Usage in main.dart:**
```dart
Consumer2<ThemeProvider, LocaleProvider>(
  builder: (ctx, themeProvider, localeProvider, child) {
    return MaterialApp(
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      ...
    );
  }
)
```

### **LocaleProvider** (`lib/providers/locale_provider.dart`)

Manages multi-language support.

```dart
class LocaleProvider extends ChangeNotifier {
  static const supported = [
    Locale('en'),
    Locale('ar'),
    Locale('fr'),
    // ...
  ];
  Locale? get locale => _locale;
  Future<void> loadForUser(String userId) async { ... }
  Future<void> clearLocale() async { ... }
}
```

**Key points:**
- Uses `flutter_intl` / `flutter_gen` for generated localization
- Persists language choice per user
- Clears on logout

### **Brand Colors** (`lib/config/brand_colors.dart`)

Central color palette used throughout app.

```dart
class Brand {
  static const Color royalBlue = Color(0xFF..);
  static const Color scaffoldLight = Color(0xFFF4F6FA);
  static const Color darkBg = Color(0xFF121212);
  // ...
}
```

### **Repositories** (`lib/repositories/`)

Data access layer:

- **TicketDetailRepository** — Fetch/update tickets and messages
- **InquiryDetailRepository** — Fetch/update inquiries
- **AdminDashboardRepository** — Dashboard stats and RPC calls

**Pattern:**
```dart
Future<TicketDetail> fetchTicket(String id) async {
  final data = await SupabaseConfig.client
    .from('service_tickets')
    .select(_ticketSelect)
    .eq('id', id)
    .single();
  return TicketDetail.fromJson(data);
}
```

### **Models** (`lib/models/`)

Data transfer objects:

- **TicketDetail** — Ticket with related user/machine/engineer
- **TicketUser** — User info embedded in ticket
- **TicketMachine** — Machine info embedded in ticket
- **InquiryDetail** — Inquiry with customer/machine/counts
- **ChatMessage** — Chat message with sender info
- **DashboardStats** — Stats from RPC
- **RecentInquiry** — Quick inquiry card data

---

## 8. Handoff Checklist

### Essential Files to Review

- [ ] `lib/main.dart` — App setup, auth flow, navigation
- [ ] `lib/screens/splash_screen.dart` — Entry point
- [ ] `lib/config/supabase_config.dart` — Backend config
- [ ] `lib/services/notification_service.dart` — Push notifications
- [ ] `lib/providers/theme_provider.dart` — Theme management
- [ ] `lib/providers/locale_provider.dart` — Localization

### Role Entry Points

- [ ] `lib/screens/customer/home_page.dart` — Customer main
- [ ] `lib/screens/engineer/engineer_dashboard.dart` — Engineer main
- [ ] `lib/screens/admin/admin_dashboard.dart` — Admin main

### Database

- [ ] Review schema tables listed in **§ 4 Database Schema**
- [ ] Ensure `.env` file is created with:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
- [ ] Verify all table indexes are created
- [ ] Set up `notifications` and `fcm_tokens` for push
- [ ] Configure `notification_settings` with defaults

### Frontend

- [ ] Review `lib/l10n/` for language setup
- [ ] Check `lib/config/brand_colors.dart` for theme
- [ ] Verify all 64 screens are present
- [ ] Test deep link handling: `iconnect://ref/<code>`

### Deployment

- [ ] Build APK/AAB for Android
- [ ] Build IPA for iOS
- [ ] Test on physical device
- [ ] Firebase setup (google-services.json, GoogleService-Info.plist)
- [ ] Supabase project provisioning
- [ ] Environment variable setup in production

### Testing

- [ ] Auth flow (sign-up, login, logout)
- [ ] Role-based access (verify screens by role)
- [ ] Realtime subscriptions (messages, schedules, notifications)
- [ ] File uploads (machine photos, attachments)
- [ ] Payment/installment flows (admin invoice → customer payment)
- [ ] FCM notifications (token refresh, topic subscriptions)

---

## Summary

**iConnect** is a comprehensive multi-role Flutter app with:
- **64 total screens** (auth + 30 admin + 28 customer + 5 engineer)
- **15+ core database tables** with normalized schema
- **Real-time messaging** via Supabase
- **Push notifications** via Firebase FCM
- **Multi-language support** with localization
- **Role-based access control** at both app and database levels
- **Tier system** for customer stratification
- **Referral program** for customer acquisition
- **Sales pipeline** management (inquiries → quotes → invoices → payments)
- **Service scheduling** with engineer assignment

All data flows through Supabase REST API with proper authentication. The app uses Provider for state management and follows Material Design principles with custom theming.

