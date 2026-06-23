// lib/screens/marketing/marketing_admin_dashboard.dart
//
// Root scaffold for the marketing_admin portal.
// 5-tab layout: Dashboard · Customers · Analytics · Broadcast · Profile
// Uses IndexedStack so each tab keeps its state.
// Navigation tiles are driven by PermissionsProvider.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../providers/permissions_provider.dart';
import '../../widgets/common/offline_banner.dart';
import 'ma_home_page.dart';
import 'ma_customers_page.dart';
import 'ma_analytics_page.dart';
import 'ma_broadcast_page.dart';
import 'ma_profile_page.dart';

class MarketingAdminDashboard extends StatefulWidget {
  const MarketingAdminDashboard({super.key});

  @override
  State<MarketingAdminDashboard> createState() =>
      _MarketingAdminDashboardState();
}

class _MarketingAdminDashboardState extends State<MarketingAdminDashboard> {
  int _currentIndex = 0;

  // Individual Navigator keys so each tab has its own back-stack.
  final _navKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  // Roots for each tab — constant so IndexedStack keeps them alive.
  static const _tabRoots = <Widget>[
    MaHomePage(),
    MaCustomersPage(),
    MaAnalyticsPage(),
    MaBroadcastPage(),
    MaProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    // Load permissions if not already loaded (e.g. deep-link entry).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PermissionsProvider>();
      if (!provider.isLoaded && !provider.isLoading) {
        provider.load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = _navKeys[_currentIndex].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                systemNavigationBarColor: Brand.darkCard,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                systemNavigationBarColor: Colors.white,
              ),
        child: Scaffold(
          body: OfflineBanner(
            child: IndexedStack(
              index: _currentIndex,
              children: List.generate(
                _tabRoots.length,
                (i) => Navigator(
                  key: _navKeys[i],
                  onGenerateRoute: (_) => MaterialPageRoute(
                    builder: (_) => _tabRoots[i],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: _buildBottomNav(isDark),
        ),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(Brand.r(24)),
          topRight: Radius.circular(Brand.r(24)),
        ),
        border: isDark
            ? Border(
                top: BorderSide(color: Brand.darkBorder, width: 1))
            : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withAlpha(60)
                : Brand.royalBlue.withAlpha(12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
          if (!isDark)
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _buildNavItem(
                  index: 0,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 1,
                  icon: Icons.people_outline_rounded,
                  activeIcon: Icons.people_rounded,
                  label: 'Customers',
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 2,
                  icon: Icons.analytics_outlined,
                  activeIcon: Icons.analytics_rounded,
                  label: 'Analytics',
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 3,
                  icon: Icons.campaign_outlined,
                  activeIcon: Icons.campaign_rounded,
                  label: 'Broadcast',
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 4,
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Profile',
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isDark,
  }) {
    final isSelected = _currentIndex == index;
    final activeColor = isDark ? Brand.royalBlueGlow : AdminColors.primary;
    final inactiveColor =
        isDark ? Brand.darkTextTertiary : Colors.grey.shade400;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_currentIndex == index) {
          // Tap active tab → pop to root within that tab's navigator.
          _navKeys[index].currentState?.popUntil((r) => r.isFirst);
        } else {
          setState(() => _currentIndex = index);
        }
      },
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                        ? Brand.royalBlue.withAlpha(38)
                        : AdminColors.primary.withAlpha(26))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(Brand.r(12)),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                size: 24,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
