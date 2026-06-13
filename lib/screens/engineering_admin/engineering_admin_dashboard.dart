// lib/screens/engineering_admin/engineering_admin_dashboard.dart
// Engineering Admin Portal — Shell with bottom navigation (v22)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../repositories/engineering_admin_repository.dart';
import '../../utils/time_utils.dart';
import '../../widgets/ds/ds_widgets.dart';
import 'ea_engineer_list_page.dart';
import 'ea_ticket_list_page.dart';
import 'ea_ticket_chat_page.dart';
import 'ea_attendance_page.dart';
import 'ea_job_records_page.dart';
import 'ea_leave_management_page.dart';
import 'ea_performance_dashboard.dart';
import 'ea_installation_page.dart';
import 'ea_schedule_page.dart';
import 'ea_profile_page.dart';
import 'ea_notifications_page.dart';
import 'ea_settings_page.dart';
import 'ea_reports_page.dart';
import 'ea_create_engineer_page.dart';
import 'ea_broadcast_page.dart';
import 'ea_pending_approvals_page.dart';
import '../admin/create_schedule_page.dart';
import '../../widgets/common/offline_banner.dart';

const Color _eaAccent = Color(0xFF16A34A);
const Color _eaGreen  = Color(0xFF22C55E);
const Color _eaRed    = Color(0xFFEF4444);
const Color _eaAmber  = Color(0xFFF59E0B);

// ═══════════════════════════════════════════════════════════════════════════
//  SHELL — manages the bottom nav + per-tab navigator stack
// ═══════════════════════════════════════════════════════════════════════════

class EngineeringAdminDashboard extends StatefulWidget {
  const EngineeringAdminDashboard({super.key});

  @override
  State<EngineeringAdminDashboard> createState() =>
      _EngineeringAdminDashboardState();
}

class _EngineeringAdminDashboardState
    extends State<EngineeringAdminDashboard> {
  int _currentIndex = 0;

  // One navigator key per tab so each tab keeps its own back-stack
  final List<GlobalKey<NavigatorState>> _navKeys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const _tabs = [
    (label: 'Dashboard', icon: Icons.dashboard_outlined,           activeIcon: Icons.dashboard_rounded),
    (label: 'Engineers', icon: Icons.engineering_outlined,         activeIcon: Icons.engineering_rounded),
    (label: 'Tickets',   icon: Icons.confirmation_number_outlined, activeIcon: Icons.confirmation_number_rounded),
    (label: 'HR',        icon: Icons.badge_outlined,               activeIcon: Icons.badge_rounded),
    (label: 'Installs',  icon: Icons.build_circle_outlined,        activeIcon: Icons.build_circle_rounded),
  ];

  // Root widget shown when a tab is first opened
  Widget _tabRoot(int i) {
    switch (i) {
      case 0: return const _EaDashboardTab();
      case 1: return const EaEngineerListPage();
      case 2: return const EaTicketListPage();
      case 3: return const _EaHrHubPage();
      case 4: return const EaInstallationPage();
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final key = _navKeys[_currentIndex];
        if (key.currentState?.canPop() == true) {
          key.currentState!.pop();
        } else if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: IndexedStack(
          index: _currentIndex,
          children: List.generate(
            5,
            (i) => Navigator(
              key: _navKeys[i],
              onGenerateRoute: (_) =>
                  MaterialPageRoute(builder: (_) => _tabRoot(i)),
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNav(isDark),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    final unselectedColor =
        isDark ? Brand.darkTextSecondary : Brand.subtleLight;

    return NavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: (i) {
        if (i == _currentIndex) {
          // Double-tap current tab → pop to root
          _navKeys[i].currentState?.popUntil((r) => r.isFirst);
        } else {
          setState(() => _currentIndex = i);
        }
      },
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      indicatorColor: _eaAccent.withAlpha(isDark ? 45 : 28),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: List.generate(_tabs.length, (i) {
        final sel   = _currentIndex == i;
        final color = sel ? _eaAccent : unselectedColor;
        return NavigationDestination(
          icon:         Icon(_tabs[i].icon,       color: color),
          selectedIcon: Icon(_tabs[i].activeIcon, color: _eaAccent),
          label:        _tabs[i].label,
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 0 — DASHBOARD OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════

class _EaDashboardTab extends StatefulWidget {
  const _EaDashboardTab();

  @override
  State<_EaDashboardTab> createState() => _EaDashboardTabState();
}

class _EaDashboardTabState extends State<_EaDashboardTab> {
  final _repo = EngineeringAdminRepository();

  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _todaysTickets    = [];
  List<Map<String, dynamic>> _availabilityStrip = [];
  List<Map<String, dynamic>> _recentActivity   = [];
  List<Map<String, dynamic>> _alerts           = [];
  Map<String, dynamic>? _profile;

  bool   _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([
        _repo.getDashboardStats(),
        _repo.getTodaysTickets(),
        _repo.getEngineerAvailabilityToday(),
        _repo.getRecentActivity(),
        _repo.getAlerts(),
        _repo.getCurrentProfile(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats             = results[0] as Map<String, int>;
        _todaysTickets     = results[1] as List<Map<String, dynamic>>;
        _availabilityStrip = results[2] as List<Map<String, dynamic>>;
        _recentActivity    = results[3] as List<Map<String, dynamic>>;
        _alerts            = results[4] as List<Map<String, dynamic>>;
        _profile           = results[5] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final firstName = (_profile?['full_name'] as String? ?? 'Admin')
        .split(' ')
        .first;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: _buildAppBar(isDark),
      body: OfflineBanner(
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: _eaAccent))
          : _error != null
              ? _buildErrorState(isDark)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _eaAccent,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // ── Greeting banner ──────────────────────────────
                      SliverToBoxAdapter(
                        child: _buildGreetingBanner(firstName, isDark),
                      ),

                      // ── Quick Actions strip (v24) ─────────────────
                      SliverToBoxAdapter(
                        child: _buildQuickActions(isDark),
                      ),

                      // ── KPI grid ─────────────────────────────────────
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 110,
                          ),
                          delegate: SliverChildListDelegate(
                              _buildKpiTiles(isDark)),
                        ),
                      ),

                      // ── Alerts ────────────────────────────────────────
                      if (_alerts.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _sectionLabel(
                              '⚡  ACTIVE ALERTS', isDark,
                              color: _eaRed),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildAlertTile(_alerts[i], isDark),
                              ),
                              childCount: _alerts.length,
                            ),
                          ),
                        ),
                      ],

                      // ── Availability strip ────────────────────────────
                      SliverToBoxAdapter(
                        child: _sectionLabel('👷  ENGINEER STATUS', isDark),
                      ),
                      SliverToBoxAdapter(
                        child: _buildAvailabilityStrip(isDark),
                      ),

                      // ── Today's tickets ───────────────────────────────
                      SliverToBoxAdapter(
                        child: _sectionLabel(
                          '🎫  TODAY\'S TICKETS',
                          isDark,
                          trailing: Text(
                            '${_todaysTickets.length} active',
                            style: TextStyle(
                              fontSize: 12,
                              color: AdminColors.textHint(context),
                            ),
                          ),
                        ),
                      ),
                      _todaysTickets.isEmpty
                          ? SliverToBoxAdapter(
                              child: _emptyState(
                                  'No active tickets today', isDark),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 8),
                                    child: _buildTicketCard(
                                        _todaysTickets[i], isDark),
                                  ),
                                  childCount: _todaysTickets.length > 5
                                      ? 5
                                      : _todaysTickets.length,
                                ),
                              ),
                            ),

                      // ── Recent activity ───────────────────────────────
                      SliverToBoxAdapter(
                        child:
                            _sectionLabel('📋  RECENT ACTIVITY', isDark),
                      ),
                      _recentActivity.isEmpty
                          ? SliverToBoxAdapter(
                              child:
                                  _emptyState('No recent activity', isDark),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 80),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => _buildActivityItem(
                                      _recentActivity[i], isDark),
                                  childCount: _recentActivity.length,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
      ),
    );
  }

  // ── Quick Actions strip (v24) ──────────────────────────────────────────
  Widget _buildQuickActions(bool isDark) {
    final actions = <_QuickAction>[
      _QuickAction(
        icon: Icons.person_add_alt_1_rounded,
        label: 'Add Engineer',
        color: _eaAccent,
        onTap: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const EaCreateEngineerPage()),
          );
          if (created == true) _load();
        },
      ),
      _QuickAction(
        icon: Icons.event_available_rounded,
        label: 'New Schedule',
        color: const Color(0xFF3B82F6),
        onTap: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const CreateSchedulePage()),
          );
          if (created == true) _load();
        },
      ),
      _QuickAction(
        icon: Icons.build_circle_rounded,
        label: 'New Installation',
        color: const Color(0xFF8B5CF6),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EaInstallationPage()),
        ).then((_) => _load()),
      ),
      _QuickAction(
        icon: Icons.campaign_rounded,
        label: 'Broadcast',
        color: const Color(0xFFF59E0B),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EaBroadcastPage()),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: actions
              .map((a) => Expanded(child: _quickActionTile(a, isDark)))
              .toList(),
        ),
      ),
    );
  }

  Widget _quickActionTile(_QuickAction a, bool isDark) {
    return InkWell(
      onTap: a.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    a.color.withAlpha(isDark ? 60 : 35),
                    a.color.withAlpha(isDark ? 30 : 15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(a.icon, color: a.color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              a.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: isDark
                    ? Brand.darkTextPrimary
                    : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────

  AppBar _buildAppBar(bool isDark) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      title: CachedNetworkImage(
        imageUrl: isDark
            ? 'https://res.cloudinary.com/dlqzqponw/image/upload/q_auto/f_auto/v1775711293/Logo-04_gwnmsr.png'
            : 'https://res.cloudinary.com/dlqzqponw/image/upload/q_auto/f_auto/v1775711293/Logo-03_cswnru.png',
        height: 30,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        placeholder:   (_, __)    => _logoFallback(isDark),
        errorWidget:   (_, __, ___) => _logoFallback(isDark),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.notifications_outlined,
            size: 22,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
          tooltip: 'Notifications',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const EaNotificationsPage()),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.refresh_rounded,
            size: 20,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
          onPressed: _load,
          tooltip: 'Refresh',
        ),
        PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert_rounded,
            size: 20,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onSelected: (val) {
            switch (val) {
              case 'profile':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const EaProfilePage()));
                break;
              case 'schedules':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const EaSchedulePage()));
                break;
              case 'broadcast':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const EaBroadcastPage()));
                break;
              case 'approvals':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const EaPendingApprovalsPage()));
                break;
              case 'reports':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const EaReportsPage()));
                break;
              case 'settings':
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const EaSettingsPage()));
                break;
            }
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(
              value: 'profile',
              child: Row(children: [
                Icon(Icons.person_rounded, size: 18),
                SizedBox(width: 10),
                Text('Profile'),
              ]),
            ),
            PopupMenuItem(
              value: 'schedules',
              child: Row(children: [
                Icon(Icons.calendar_month_rounded, size: 18),
                SizedBox(width: 10),
                Text('Schedules'),
              ]),
            ),
            PopupMenuItem(
              value: 'broadcast',
              child: Row(children: [
                Icon(Icons.campaign_rounded, size: 18),
                SizedBox(width: 10),
                Text('Broadcast'),
              ]),
            ),
            PopupMenuItem(
              value: 'approvals',
              child: Row(children: [
                Icon(Icons.rule_rounded, size: 18),
                SizedBox(width: 10),
                Text('Pending Approvals'),
              ]),
            ),
            PopupMenuItem(
              value: 'reports',
              child: Row(children: [
                Icon(Icons.bar_chart_rounded, size: 18),
                SizedBox(width: 10),
                Text('Reports'),
              ]),
            ),
            PopupMenuItem(
              value: 'settings',
              child: Row(children: [
                Icon(Icons.settings_rounded, size: 18),
                SizedBox(width: 10),
                Text('Settings'),
              ]),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(
          height: 0.5,
          color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  Widget _logoFallback(bool isDark) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _eaAccent.withAlpha(isDark ? 40 : 20),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.engineering_rounded,
                color: _eaAccent, size: 16),
          ),
          const SizedBox(width: 8),
          Text(
            'TRI Engineering',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
        ],
      );

  // ── Greeting banner ────────────────────────────────────────────────────

  Widget _buildGreetingBanner(String firstName, bool isDark) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return DsHero(
      greeting: '$greeting,',
      title: firstName,
      trailing: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _eaGreen,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withAlpha(64), width: 2),
        ),
        child: const Icon(Icons.engineering_rounded,
            color: Colors.white, size: 19),
      ),
      actionCard: DsHeroCard(
        icon: Icons.engineering_rounded,
        iconColor: const Color(0xFF5ED38A),
        label: 'Engineering admin portal',
        title: 'Team, dispatch & schedules',
        onTap: () {},
      ),
    );
  }

  // ── KPI tiles ─────────────────────────────────────────────────────────

  List<Widget> _buildKpiTiles(bool isDark) {
    return [
      _kpiTile(
        isDark: isDark,
        icon:  Icons.people_alt_rounded,
        label: 'Present Today',
        value: _stats['present_today'] ?? 0,
        color: _eaGreen,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EaAttendancePage())),
      ),
      _kpiTile(
        isDark: isDark,
        icon:  Icons.assignment_late_rounded,
        label: 'Unassigned',
        value: _stats['unassigned_tickets'] ?? 0,
        color: _eaRed,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EaTicketListPage())),
      ),
      _kpiTile(
        isDark: isDark,
        icon:  Icons.work_rounded,
        label: 'Jobs In Progress',
        value: _stats['jobs_in_progress'] ?? 0,
        color: _eaAccent,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EaJobRecordsPage())),
      ),
      _kpiTile(
        isDark: isDark,
        icon:  Icons.beach_access_rounded,
        label: 'Pending Leaves',
        value: _stats['pending_leaves'] ?? 0,
        color: _eaAmber,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => const EaLeaveManagementPage())),
      ),
      _kpiTile(
        isDark: isDark,
        icon:  Icons.build_circle_rounded,
        label: 'Installations',
        value: _stats['active_installations'] ?? 0,
        color: const Color(0xFF8B5CF6),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EaInstallationPage())),
      ),
      _kpiTile(
        isDark: isDark,
        icon:  Icons.group_rounded,
        label: 'Total Engineers',
        value: _stats['total_engineers'] ?? _availabilityStrip.length,
        color: _eaAccent,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => const EaEngineerListPage())),
      ),
    ];
  }

  Widget _kpiTile({
    required bool         isDark,
    required IconData     icon,
    required String       label,
    required int          value,
    required Color        color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(5),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Icon + chevron row ──────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withAlpha(isDark ? 45 : 38),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: AdminColors.textHint(context).withAlpha(128),
                ),
              ],
            ),
            // ── Value + label ───────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AdminColors.textHint(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────

  Widget _sectionLabel(String title, bool isDark,
      {Color? color, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: color ??
                  (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing],
        ],
      ),
    );
  }

  // ── Availability strip ────────────────────────────────────────────────

  Widget _buildAvailabilityStrip(bool isDark) {
    if (_availabilityStrip.isEmpty) {
      return _emptyState('No engineers found', isDark);
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _availabilityStrip.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final eng       = _availabilityStrip[i];
          final status    = eng['attendance_status'] as String? ?? 'absent';
          final activeJobs = eng['active_jobs_today'] as int? ?? 0;
          final photo     = eng['profile_photo'] as String?;
          final name      = eng['full_name'] as String? ?? '';
          final firstName = name.split(' ').first;

          Color  ringColor;
          String ringLabel;
          switch (status) {
            case 'present':
            case 'late':
            case 'half_day':
              ringColor = activeJobs >= 3 ? const Color(0xFFF97316) : _eaGreen;
              ringLabel = activeJobs >= 3 ? 'Busy' : 'Free';
              break;
            case 'on_leave':
              ringColor = _eaAccent;
              ringLabel = 'Leave';
              break;
            default:
              ringColor = _eaRed;
              ringLabel = 'Away';
          }

          return GestureDetector(
            onTap: () => _showEngineerQuickView(eng),
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: ringColor, width: 2.5),
                      ),
                      child: ClipOval(
                        child: photo != null && photo.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.cover,
                                placeholder:
                                    (_, __) => _avatarFallback(),
                                errorWidget:
                                    (_, __, ___) => _avatarFallback(),
                              )
                            : _avatarFallback(),
                      ),
                    ),
                    if (activeJobs > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: ringColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? Brand.darkBg
                                  : Brand.scaffoldLight,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$activeJobs',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  firstName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : Brand.subtleLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  ringLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ringColor,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _avatarFallback() => Container(
        color: _eaAccent.withAlpha(30),
        child: const Icon(Icons.person_rounded,
            color: _eaAccent, size: 24),
      );

  void _showEngineerQuickView(Map<String, dynamic> eng) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        final name      = eng['full_name'] as String? ?? 'Engineer';
        final status    = eng['attendance_status'] as String? ?? 'unknown';
        final zone      = eng['assigned_zone'] as String? ?? '—';
        final checkIn   = eng['check_in_time'] as String?;
        final activeJobs = eng['active_jobs_today'] as int? ?? 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _eaAccent.withAlpha(isDark ? 40 : 20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.engineering_rounded,
                        color: _eaAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _qvRow(Icons.circle_rounded, 'Status',
                  _statusLabel(status), isDark),
              const Divider(height: 16),
              _qvRow(Icons.location_on_outlined, 'Zone', zone, isDark),
              const Divider(height: 16),
              _qvRow(
                Icons.login_rounded,
                'Check-in',
                checkIn != null
                    ? TimeUtils.formatTime(
                        DateTime.tryParse(checkIn) ?? DateTime.now())
                    : 'Not checked in',
                isDark,
              ),
              const Divider(height: 16),
              _qvRow(Icons.work_outline_rounded, 'Active Jobs',
                  '$activeJobs', isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _qvRow(
      IconData icon, String label, String value, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _eaAccent),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(
              fontSize: 12, color: AdminColors.textSub(context)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark
                ? Brand.darkTextPrimary
                : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // ── Ticket card ───────────────────────────────────────────────────────

  Widget _buildTicketCard(Map<String, dynamic> t, bool isDark) {
    final customer    = t['customer'] as Map<String, dynamic>?;
    final engineer    = t['engineer'] as Map<String, dynamic>?;
    final machine     = t['machine']  as Map<String, dynamic>?;
    final catalog     = machine?['catalog'] as Map<String, dynamic>?;

    final ticketId    = t['id'] as String? ?? '';
    final title       = t['subject'] as String? ?? 'Untitled';
    final ticketNum   = t['ticket_number'] as String? ?? '';
    final status      = t['status'] as String? ?? 'new';
    final customerName = customer?['full_name'] as String? ?? 'Unknown';
    final engineerName = engineer?['full_name'] as String?;
    // FIXED: catalog column is machine_name; customer_machines uses machine_nickname
    final machineName = catalog?['machine_name'] as String?
        ?? machine?['machine_nickname'] as String?
        ?? '—';

    final isUnassigned = engineer == null;
    final statusColor  = _statusColor(status);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              EaTicketChatPage(ticketId: ticketId, ticketTitle: title),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnassigned
                ? _eaRed.withAlpha(isDark ? 100 : 60)
                : (isDark ? Brand.darkBorder : const Color(0xFFE2E8F0)),
            width: isUnassigned ? 1.5 : 1,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(5),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Priority strip
            Container(
              width: 3,
              height: 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(isDark ? 35 : 20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ticketNum,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$customerName · $machineName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: AdminColors.textSub(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isUnassigned)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _eaRed.withAlpha(isDark ? 30 : 15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Unassigned',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _eaRed),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Icon(Icons.engineering_rounded,
                      size: 12, color: _eaAccent),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 72,
                    child: Text(
                      engineerName ?? '',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _eaAccent,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Alert tile ────────────────────────────────────────────────────────

  Widget _buildAlertTile(Map<String, dynamic> alert, bool isDark) {
    final type     = alert['type']     as String? ?? '';
    final title    = alert['title']    as String? ?? '';
    final subtitle = alert['subtitle'] as String? ?? '';
    final severity = alert['severity'] as String? ?? 'medium';

    final alertColor = severity == 'high' ? _eaRed : _eaAmber;

    IconData alertIcon;
    switch (type) {
      case 'expired_offer':   alertIcon = Icons.timer_off_rounded;    break;
      case 'not_checked_in':  alertIcon = Icons.person_off_rounded;   break;
      case 'cert_expiry':     alertIcon = Icons.verified_outlined;    break;
      default:                alertIcon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: alertColor.withAlpha(isDark ? 20 : 10),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: alertColor.withAlpha(isDark ? 60 : 45)),
      ),
      child: Row(
        children: [
          Icon(alertIcon, size: 18, color: alertColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: alertColor)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.textSub(context))),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: AdminColors.textHint(context)),
        ],
      ),
    );
  }

  // ── Activity item ─────────────────────────────────────────────────────

  Widget _buildActivityItem(Map<String, dynamic> event, bool isDark) {
    final type      = event['event_type'] as String? ?? '';
    final eventTime = event['event_time'] as String?;
    final dt        = eventTime != null ? DateTime.tryParse(eventTime) : null;
    final timeAgo   = dt != null ? TimeUtils.getTimeAgo(dt) : '';

    String    title;
    IconData  icon;
    Color     iconColor = _eaAccent;

    switch (type) {
      case 'installation_updated':
        final customer   = event['customer'] as Map<String, dynamic>?;
        final instTitle  = event['location'] as String? ?? 'Installation';
        final instStatus = event['status']  as String? ?? '';
        title = 'Installation: $instTitle'
            '${customer != null ? ' — ${customer['full_name']}' : ''}';
        if (instStatus.isNotEmpty) title += ' [$instStatus]';
        icon      = Icons.build_circle_rounded;
        iconColor = _eaGreen;
        break;
      case 'checkin':
        final eng        = event['engineer']     as Map<String, dynamic>?;
        final checkInTime = event['check_in_time'] as String?;
        final cDt = checkInTime != null
            ? DateTime.tryParse(checkInTime)
            : null;
        title = '${eng?['full_name'] ?? 'Engineer'} checked in'
            '${cDt != null ? ' at ${TimeUtils.formatTime(cDt)}' : ''}';
        icon      = Icons.login_rounded;
        iconColor = _eaGreen;
        break;
      case 'ticket_new':
        title     = 'New ticket: ${event['subject'] ?? ''}';
        icon      = Icons.confirmation_number_rounded;
        iconColor = _eaAccent;
        break;
      default:
        title = 'Activity recorded';
        icon  = Icons.timeline_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(isDark ? 35 : 18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              Container(
                width: 1.5,
                height: 22,
                color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : const Color(0xFF374151),
                      )),
                  const SizedBox(height: 2),
                  Text(timeAgo,
                      style: TextStyle(
                          fontSize: 11,
                          color: AdminColors.textHint(context))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty / error states ──────────────────────────────────────────────

  Widget _emptyState(String msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Center(
        child: Text(msg,
            style: TextStyle(
                fontSize: 13, color: AdminColors.textHint(context))),
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: _eaRed.withAlpha(200)),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Brand.darkTextSecondary
                    : Brand.subtleLight),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _eaAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'new':
      case 'open':             return const Color(0xFF3B82F6);
      case 'assigned':         return _eaAccent;
      case 'in_progress':      return _eaGreen;
      case 'waiting_customer': return _eaAmber;
      case 'resolved':
      case 'closed':
      case 'completed':        return const Color(0xFF6B7280);
      default:                 return const Color(0xFF9CA3AF);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'present':   return 'Present';
      case 'late':      return 'Late';
      case 'half_day':  return 'Half Day';
      case 'on_leave':  return 'On Leave';
      case 'absent':    return 'Absent';
      default:          return status;
    }
  }
}

// ── Quick action descriptor (v24) ──────────────────────────────────────────
class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 3 — HR HUB  (four navigation cards)
// ═══════════════════════════════════════════════════════════════════════════

class _EaHrHubPage extends StatelessWidget {
  const _EaHrHubPage();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'HR',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
            height: 0.5,
            color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
        children: [
          _MoreModuleCard(
            icon:      Icons.calendar_month_rounded,
            iconColor: _eaGreen,
            title:     'Attendance',
            subtitle:  'Daily check-ins, absences, and status tracking',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const EaAttendancePage())),
          ),
          const SizedBox(height: 12),
          _MoreModuleCard(
            icon:      Icons.work_history_rounded,
            iconColor: _eaAccent,
            title:     'Job Records',
            subtitle:  'Engineer task records, hours worked, and status',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const EaJobRecordsPage())),
          ),
          const SizedBox(height: 12),
          _MoreModuleCard(
            icon:      Icons.beach_access_rounded,
            iconColor: _eaAmber,
            title:     'Leave Requests',
            subtitle:  'Review and approve engineer leave applications',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const EaLeaveManagementPage())),
          ),
          const SizedBox(height: 12),
          _MoreModuleCard(
            icon:      Icons.insights_rounded,
            iconColor: const Color(0xFF8B5CF6),
            title:     'Performance',
            subtitle:  'Engineer KPIs, ratings, and team analytics',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const EaPerformanceDashboard())),
          ),
        ],
      ),
    );
  }
}

// ── Module card (shared by More hub and HR hub) ────────────────────────────

class _MoreModuleCard extends StatelessWidget {
  final IconData    icon;
  final Color       iconColor;
  final String      title;
  final String      subtitle;
  final VoidCallback onTap;

  const _MoreModuleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? Brand.darkBorder : const Color(0xFFE2E8F0),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: iconColor.withAlpha(isDark ? 45 : 25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textSub(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: AdminColors.textHint(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
