// lib/screens/admin/admin_more_page.dart

import 'package:flutter/material.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import 'customers_management_page.dart';
import 'engineer_management_page.dart';
import 'machines_management_page.dart';
import 'admin_register_machine_page.dart';
import 'service_calendar_page.dart';
import 'admin_installments_page.dart';
import 'payment_dashboard_page.dart';
import 'create_invoice_page.dart';
import 'quotation_management_page.dart';
import 'referral_management_page.dart';
import 'tier_management_page.dart';
import 'analytics_dashboard.dart' show AnalyticsDashboardPage;
import 'broadcast_notifications.dart';
import 'admin_settings_page.dart';
import 'marketer_management_page.dart';
import 'engineering_admin_management_page.dart';
import 'admin_installations_page.dart';
import 'admin_knowledge_base_page.dart';
import 'admin_hot_leads_page.dart';

class AdminMorePage extends StatelessWidget {
  const AdminMorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'More',
        accent: HeroAccent.navy,
        showBack: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _buildSection(
            context,
            isDark: isDark,
            title: 'People',
            items: [
              _MoreItem(
                icon: Icons.people_rounded,
                label: 'Customers',
                subtitle: 'Manage customer accounts',
                color: Brand.royalBlue,
                page: const CustomersManagementPage(),
              ),
              _MoreItem(
                icon: Icons.engineering_rounded,
                label: 'Engineers',
                subtitle: 'Manage field engineers',
                color: Brand.cyanAccent,
                page: const EngineerManagementPage(),
              ),
              _MoreItem(
                icon: Icons.campaign_rounded,
                label: 'Marketers',
                subtitle: 'Manage marketing team accounts',
                color: StatusColors.assigned,
                page: const MarketerManagementPage(),
              ),
              _MoreItem(
                icon: Icons.admin_panel_settings_rounded,
                label: 'Engineering Admins',
                subtitle: 'Manage engineering admin accounts',
                color: AdminColors.info,
                page: const EngineeringAdminManagementPage(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            isDark: isDark,
            title: 'Operations',
            items: [
              _MoreItem(
                icon: Icons.precision_manufacturing_rounded,
                label: 'Machines Catalog',
                subtitle: 'Browse and manage machine catalog',
                color: Brand.royalBlue,
                page: const MachinesManagementPage(),
              ),
              _MoreItem(
                icon: Icons.app_registration_rounded,
                label: 'Register Machine',
                subtitle: 'Register a machine for a customer',
                color: Brand.lightGreen,
                page: const AdminRegisterMachinePage(),
              ),
              _MoreItem(
                icon: Icons.calendar_month_rounded,
                label: 'Service Calendar',
                subtitle: 'View and manage service schedules',
                color: AdminColors.info,
                page: const ServiceCalendarPage(),
              ),
              _MoreItem(
                icon: Icons.credit_card_rounded,
                label: 'Installments',
                subtitle: 'Track installment payments',
                color: AdminColors.internal,
                page: const AdminInstallmentsPage(),
              ),
              _MoreItem(
                icon: Icons.build_rounded,
                label: 'Machine Installations',
                subtitle: 'Manage installation tasks & engineers',
                color: AdminColors.info,
                page: const AdminInstallationsPage(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            isDark: isDark,
            title: 'Finance',
            items: [
              _MoreItem(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Payment Dashboard',
                subtitle: 'Revenue and payment overview',
                color: Brand.lightGreenDark,
                page: const PaymentDashboardPage(),
              ),
              _MoreItem(
                icon: Icons.receipt_long_rounded,
                label: 'Invoice Management',
                subtitle: 'Create and manage invoices',
                color: Brand.royalBlue,
                page: const CreateInvoicePage(),
              ),
              _MoreItem(
                icon: Icons.description_rounded,
                label: 'Quotation Management',
                subtitle: 'Create and track quotations',
                color: StatusColors.assigned,
                page: const QuotationManagementPage(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            isDark: isDark,
            title: 'Growth',
            items: [
              _MoreItem(
                icon: Icons.local_fire_department_rounded,
                label: 'Hot Leads',
                subtitle:
                    'Customers at 75%+ on their next-machine journey',
                color: StatusColors.danger,
                page: const AdminHotLeadsPage(),
              ),
              _MoreItem(
                icon: Icons.group_add_rounded,
                label: 'Referral Program',
                subtitle: 'Manage referrals and rewards',
                color: const Color(0xFFEC4899),
                page: const ReferralManagementPage(),
              ),
              _MoreItem(
                icon: Icons.star_rounded,
                label: 'Loyalty Tiers',
                subtitle: 'Configure loyalty tier rules',
                color: AdminColors.warning,
                page: const TierManagementPage(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            isDark: isDark,
            title: 'Content',
            items: [
              _MoreItem(
                icon: Icons.menu_book_rounded,
                label: 'Knowledge Base',
                subtitle:
                    'Manuals, articles, testimonials, and machine videos',
                color: StatusColors.assigned,
                page: const AdminKnowledgeBasePage(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            isDark: isDark,
            title: 'Insights & Tools',
            items: [
              _MoreItem(
                icon: Icons.analytics_rounded,
                label: 'Analytics Dashboard',
                subtitle: 'Business performance insights',
                color: AdminColors.primary,
                page: const AnalyticsDashboardPage(),
              ),
              _MoreItem(
                icon: Icons.campaign_rounded,
                label: 'Broadcast Notifications',
                subtitle: 'Send messages to all users',
                color: StatusColors.assigned,
                page: const BroadcastNotificationsPage(),
              ),
              _MoreItem(
                icon: Icons.settings_rounded,
                label: 'Settings',
                subtitle: 'App and account configuration',
                color: AdminColors.textHint(context),
                page: const AdminSettingsPage(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required bool isDark,
    required String title,
    required List<_MoreItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(18)),
            border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;
              return _buildTile(context, item: item, isDark: isDark, isLast: isLast);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required _MoreItem item,
    required bool isDark,
    required bool isLast,
  }) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => item.page),
      ),
      borderRadius: isLast
          ? BorderRadius.vertical(bottom: Radius.circular(Brand.r(18)))
          : BorderRadius.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: item.color.withAlpha(isDark ? 30 : 15),
                    borderRadius: BorderRadius.circular(Brand.r(12)),
                  ),
                  child: Icon(item.icon, size: 20, color: item.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      if (item.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ],
            ),
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 70),
              child: Divider(
                height: 1,
                color: isDark ? Brand.darkBorder : Brand.borderLight,
              ),
            ),
        ],
      ),
    );
  }
}

class _MoreItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final Widget page;

  const _MoreItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.page,
  });
}
