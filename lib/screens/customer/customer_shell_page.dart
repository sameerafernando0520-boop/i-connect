// lib/screens/customer/customer_shell_page.dart
//
// Root shell for the customer portal.
//
// Uses IndexedStack so all 5 tab pages stay alive simultaneously —
// switching tabs is instant (no Navigator animation, no data reload)
// and the single CustomerNavBar never rebuilds or animates.

import 'package:flutter/material.dart';
import '../../config/admin_theme.dart';
import '../../widgets/common/offline_banner.dart';
import '../../widgets/customer/customer_nav_bar.dart';
import '../../widgets/customer/customer_nav_controller.dart';
import 'home_page.dart';
import 'my_machines_page.dart';
import 'support_tickets_page.dart';
import 'knowledge_base_page.dart';
import 'profile_page.dart';

class CustomerShellPage extends StatefulWidget {
  /// Optional starting tab (defaults to 0 = Home).
  final int initialIndex;

  const CustomerShellPage({super.key, this.initialIndex = 0});

  @override
  State<CustomerShellPage> createState() => _CustomerShellPageState();
}

class _CustomerShellPageState extends State<CustomerShellPage> {
  // ── Tab pages ────────────────────────────────────────────────
  // Home tab is kept alive in IndexedStack for instant navigation.
  // Other tabs are built conditionally to save memory.
  late final Widget _homePage = HomePage(showNavBar: false);

  @override
  void initState() {
    super.initState();
    // Honour an explicit starting tab (e.g. deep-link opens Profile).
    if (widget.initialIndex != 0) {
      CustomerNavController.tabIndex.value = widget.initialIndex;
    }
  }

  Widget _buildCurrentTab(int index) {
    switch (index) {
      case 0:
        return _homePage;
      case 1:
        return MyMachinesPage(showNavBar: false);
      case 2:
        return SupportTicketsPage(showNavBar: false);
      case 3:
        return KnowledgeBasePage(showNavBar: false);
      case 4:
        return ProfilePage(showNavBar: false);
      default:
        return _homePage;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CustomerNavController.tabIndex,
      builder: (context, currentIndex, _) {
        return Scaffold(
          body: OfflineBanner(
            child: _buildCurrentTab(currentIndex),
          ),
          bottomNavigationBar: ValueListenableBuilder<int>(
            valueListenable: CustomerNavController.openTickets,
            builder: (context, tickets, _) {
              return CustomerNavBar(
                currentIndex: currentIndex,
                openTickets: tickets,
                onTabSelected: CustomerNavController.switchTab,
              );
            },
          ),
        );
      },
    );
  }
}
