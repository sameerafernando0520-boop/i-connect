// lib/screens/admin/admin_dashboard.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../models/dashboard_stats.dart';
import '../../repositories/admin_dashboard_repository.dart';
import '../../utils/time_utils.dart';
import '../../utils/string_utils.dart';
import '../../widgets/common/nav_badge_indicator.dart';
import '../../widgets/common/ic_icons.dart';
import '../../widgets/common/app_logo.dart';
import '../../widgets/admin/shimmer_loading.dart';
import '../../widgets/admin/inquiry_card.dart';
import '../../widgets/admin/customer_card.dart';
import '../../widgets/admin/section_header.dart';
import '../../widgets/admin/empty_state.dart';
import '../../widgets/common/offline_banner.dart';
import '../customer/notification_list_page.dart';
import 'inquiry_management_page.dart';
import 'inquiry_detail_page.dart';
import 'tickets_management_page.dart';
import 'machines_management_page.dart';
import 'customers_management_page.dart';
import 'customer_detail_page.dart';
import 'engineer_management_page.dart';
import 'broadcast_notifications.dart';
import 'analytics_dashboard.dart';
import 'admin_settings_page.dart';
import 'admin_installments_page.dart';
import 'admin_register_machine_page.dart';
import 'create_invoice_page.dart';
import 'referral_management_page.dart';
import 'admin_more_page.dart';
import 'create_quotation_page.dart';
import 'create_schedule_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with WidgetsBindingObserver {
  final _repository = AdminDashboardRepository();
  final _scrollController = ScrollController();

  // ── Tab navigation (0=Dashboard 1=Inquiries 3=Tickets 4=More) ──
  int _selectedIndex = 0;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  String _adminName = 'Admin';
  String? _adminPhotoUrl;

  DashboardStats _stats = DashboardStats.empty;
  List<RecentInquiry> _recentInquiries = [];
  List<RecentCustomer> _recentCustomers = [];
  int _escalatedCount = 0;
  int _overdueInstallments = 0;
  int _pendingReferralCount = 0;

  // Business Hub KPIs
  double _hubRevenueThisMonth = 0;
  double _hubOutstandingReceivables = 0;
  int _hubPendingQuotations = 0;
  int _hubOverdueInstallments = 0;

  // Realtime: store subscription for disposal
  StreamSubscription? _ticketSubscription;
  Timer? _refreshTimer;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboardData();
    _setupRealtimeSubscription();
    _setupAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticketSubscription?.cancel();
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDashboardData(forceRefresh: true);
    }
  }

  void _setupRealtimeSubscription() {
    // Using .stream() returns a StreamSubscription — cancelled in dispose ✅
    _ticketSubscription = SupabaseConfig.client
        .from('service_tickets')
        .stream(primaryKey: ['id']).listen(
      (_) {
        // Debounce to avoid rapid successive reloads
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          if (mounted) {
            _loadDashboardData(forceRefresh: true, silent: true);
          }
        });
      },
      onError: (e) {
        debugPrint('Dashboard stream error: $e');
      },
    );
  }

  void _setupAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) {
        _loadDashboardData(forceRefresh: true, silent: true);
      }
    });
  }

  Future<void> _loadDashboardData({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = _stats == DashboardStats.empty;
        _isRefreshing = !_isLoading;
        _error = null;
      });
    }

    try {
      // FIX: explicit <dynamic> type required
      // Note: notifications unread count is now owned by NavBadgeIndicator
      // (realtime). Removed fetchUnreadNotificationCount from this batch.
      final results = await Future.wait<dynamic>([
        _repository.getAdminName(),
        _repository.fetchStats(forceRefresh: forceRefresh),
        _repository.fetchRecentInquiries(forceRefresh: forceRefresh),
        _repository.fetchRecentCustomers(forceRefresh: forceRefresh),
        _fetchEscalatedCount(),
        _fetchOverdueInstallmentCount(),
        _fetchAdminPhoto(),
        _fetchPendingReferralCount(),
        _fetchBusinessHubStats(),
      ]);

      if (!mounted) return;

      setState(() {
        _adminName = results[0] as String;
        _stats = results[1] as DashboardStats;
        _recentInquiries = results[2] as List<RecentInquiry>;
        _recentCustomers = results[3] as List<RecentCustomer>;
        _escalatedCount = results[4] as int;
        _overdueInstallments = results[5] as int;
        _adminPhotoUrl = results[6] as String?;
        _pendingReferralCount = results[7] as int;
        final hub = results[8] as Map<String, dynamic>;
        _hubRevenueThisMonth = (hub['revenue'] as num).toDouble();
        _hubOutstandingReceivables = (hub['outstanding'] as num).toDouble();
        _hubPendingQuotations = hub['pendingQuotations'] as int;
        _hubOverdueInstallments = hub['overdueInstallments'] as int;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      debugPrint('Dashboard load error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _error = e.toString();
      });

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to load dashboard data',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: AdminColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadDashboardData(forceRefresh: true),
            ),
          ),
        );
      }
    }
  }

  Future<int> _fetchEscalatedCount() async {
    try {
      final data = await SupabaseConfig.client
          .from('service_tickets')
          .select('id')
          .eq('escalated', true)
          .eq('is_deleted', false)
          .inFilter('status',
              ['open', 'assigned', 'in_progress', 'waiting_customer']);
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, dynamic>> _fetchBusinessHubStats() async {
    final result = <String, dynamic>{
      'revenue': 0.0,
      'outstanding': 0.0,
      'pendingQuotations': 0,
      'overdueInstallments': 0,
    };
    try {
      final now = DateTime.now();
      final monthStart =
          DateTime(now.year, now.month, 1).toIso8601String().substring(0, 10);
      final today = now.toIso8601String().substring(0, 10);

      final responses = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('invoices')
            .select('total_amount, paid_date')
            .gte('paid_date', monthStart),
        SupabaseConfig.client
            .from('invoices')
            .select('balance_due, status')
            .neq('status', 'paid'),
        SupabaseConfig.client
            .from('quotations')
            .select('id')
            .eq('status', 'sent')
            .gte('valid_until', today),
        SupabaseConfig.client
            .from('installment_payments')
            .select('id')
            .or('status.eq.overdue,and(status.eq.pending,due_date.lt.$today)'),
      ]);

      double revenue = 0;
      for (final row in (responses[0] as List)) {
        final v = row['total_amount'];
        if (v is num) revenue += v.toDouble();
      }
      double outstanding = 0;
      for (final row in (responses[1] as List)) {
        final v = row['balance_due'];
        if (v is num) outstanding += v.toDouble();
      }
      result['revenue'] = revenue;
      result['outstanding'] = outstanding;
      result['pendingQuotations'] = (responses[2] as List).length;
      result['overdueInstallments'] = (responses[3] as List).length;
    } catch (e) {
      debugPrint('Business Hub stats error: $e');
    }
    return result;
  }

  Future<int> _fetchOverdueInstallmentCount() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final response = await SupabaseConfig.client
          .from('installment_payments')
          .select('id')
          .or('status.eq.overdue,and(status.eq.pending,due_date.lt.$today)');
      return (response as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<String?> _fetchAdminPhoto() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return null;
      final data = await SupabaseConfig.client
          .from('users')
          .select('profile_photo')
          .eq('id', userId)
          .single();
      return data['profile_photo'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<int> _fetchPendingReferralCount() async {
    try {
      final response = await SupabaseConfig.client
          .from('referrals')
          .select('id')
          .inFilter('status', ['signed_up', 'cooling']);
      return (response as List).length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      // Prevent accidental back-press from blanking the screen.
      // If on a non-dashboard tab, go back to Dashboard; otherwise block pop.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark
            ? SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark
                .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
          body: Column(
            children: [
              Expanded(child: _buildTabBody(isDark)),
              _buildBottomNav(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody(bool isDark) {
    return IndexedStack(
      sizing: StackFit.expand,
      index: _selectedIndex,
      children: [
        _buildDashboardTab(isDark),
        const InquiryManagementPage(),
        const SizedBox.shrink(),
        const TicketsManagementPage(),
        const AdminMorePage(),
      ],
    );
  }

  Widget _buildDashboardTab(bool isDark) {
    return OfflineBanner(
      child: SafeArea(
        top: false,
        bottom: false,
        child: _isLoading
            ? const DashboardSkeleton()
            : _error != null && _stats == DashboardStats.empty
                ? _buildErrorState(isDark)
                : RefreshIndicator(
                    onRefresh: () => _loadDashboardData(forceRefresh: true),
                    color: AdminColors.accent,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (_isRefreshing)
                          SliverToBoxAdapter(
                              child: _buildRefreshingIndicator(isDark)),
                        SliverToBoxAdapter(child: _buildTopHeader(isDark)),
                        SliverToBoxAdapter(child: _buildDashboardCard(isDark)),
                        if (_escalatedCount > 0)
                          SliverToBoxAdapter(
                              child: _buildEscalationAlert(isDark)),
                        if (_overdueInstallments > 0)
                          SliverToBoxAdapter(child: _buildOverdueAlert(isDark)),
                        SliverToBoxAdapter(child: _buildStatsGrid(isDark)),
                        SliverToBoxAdapter(child: _buildQuickActions(isDark)),
                        SliverToBoxAdapter(child: _buildBusinessHub(isDark)),
                        SliverToBoxAdapter(
                            child: _buildRecentInquiriesSection(isDark)),
                        SliverToBoxAdapter(
                            child: _buildRecentCustomersSection(isDark)),
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ─── REFRESHING INDICATOR ────────────────────────────────
  Widget _buildRefreshingIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            // FIX: .withOpacity() → .withAlpha()
            color: AdminColors.accent
                .withAlpha(isDark ? 31 : 20), // 0.12→31, 0.08→20
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Brand.lightGreenBright : AdminColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Updating...',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Brand.lightGreenBright : AdminColors.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ERROR STATE ─────────────────────────────────────────
  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                // FIX: .withOpacity() → .withAlpha()
                color: AdminColors.error.withAlpha(isDark ? 31 : 20),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.cloud_off_rounded,
                  size: 40, color: AdminColors.error),
            ),
            const SizedBox(height: 20),
            Text(
              'Unable to Load Dashboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Brand.darkTextPrimary : AdminColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => _loadDashboardData(forceRefresh: true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  color: AdminColors.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      // Already using .withAlpha() ✅
                      color: AdminColors.primary.withAlpha(89),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Retry',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOP HEADER (matches customer dashboard style) ─────
  Widget _buildTopHeader(bool isDark) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A5F), Color(0xFF12294A)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 16, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: AppLogo.wordmark(height: 24, dark: true),
          ),
          Row(
            children: [
              // Admin avatar — gradient container with glow shadow
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: isDark
                    ? [Brand.darkIconActive, Brand.royalBlueGlow]
                    : [AdminColors.primary, Brand.royalBlueLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Brand.darkIconActive.withAlpha(64)
                      : AdminColors.primary.withAlpha(89),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _adminPhotoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: _adminPhotoUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _adminAvatarFallback(isDark),
                      errorWidget: (_, __, ___) => _adminAvatarFallback(isDark),
                    )
                  : _adminAvatarFallback(isDark),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TimeUtils.getGreeting(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _adminName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Notification bell — live count via realtime subscription
          NavBadgeIndicator(
            badgeType: NavBadgeType.notifications,
            builder: (_, count) => _buildHeaderIcon(
              Icons.notifications_outlined,
              isDark: isDark,
              badgeCount: count,
              onTap: () =>
                  _navigateTo(const NotificationListPage(userRole: 'admin')),
            ),
          ),
          const SizedBox(width: 10),
          // Settings gear
          _buildHeaderIcon(
            Icons.settings_outlined,
            isDark: isDark,
            onTap: () => _navigateTo(const AdminSettingsPage()),
          ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _adminAvatarFallback(bool isDark) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [Brand.darkIconActive, Brand.royalBlueGlow]
                : [AdminColors.primary, Brand.royalBlueLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            StringUtils.getInitials(_adminName),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
        ),
      );

  Widget _buildHeaderIcon(
    IconData icon, {
    required bool isDark,
    VoidCallback? onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: isDark
                  ? Border.all(color: Brand.darkBorder)
                  : null,
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Brand.royalBlue.withAlpha(12),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                      BoxShadow(
                        color: Colors.black.withAlpha(6),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: Icon(
              icon,
              color: isDark ? Brand.darkTextSecondary : AdminColors.primary,
              size: 22,
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AdminColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    // FIX: AdminColors.background → Brand.scaffoldLight
                    color: isDark ? Brand.darkBg : Brand.scaffoldLight,
                    width: 2,
                  ),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Center(
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── DASHBOARD CARD (premium corporate hero) ────────────
  Widget _buildDashboardCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: isDark
              ? [Brand.darkCard, Brand.darkCardElevated]
              : [const Color(0xFF1A56DB), const Color(0xFF3B82F6)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(89),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned(
              right: -35,
              top: -35,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(10),
                ),
              ),
            ),
            Positioned(
              right: 25,
              bottom: -20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(7),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Badge Row ──
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.admin_panel_settings_rounded,
                          color: Colors.white,
                          size: 13),
                      const SizedBox(width: 5),
                      Text(
                        'Admin Dashboard',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ]),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Brand.lightGreen.withAlpha(26),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle,
                          color: Brand.lightGreenBright,
                          size: 7),
                      const SizedBox(width: 5),
                      Text(
                        'Active',
                        style: TextStyle(
                          color: Brand.lightGreenBright,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 22),

                // ── Stats Row ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Customers',
                          style: TextStyle(
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Colors.white.withAlpha(160),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_stats.totalCustomers}',
                          style: TextStyle(
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                            letterSpacing: -2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _buildCardStat(
                      Icons.trending_up_rounded,
                      '+${_stats.newCustomersThisMonth}',
                      'This Month',
                      isDark ? Brand.lightGreenBright : Brand.lightGreen,
                      isDark,
                    ),
                    const SizedBox(width: 14),
                    _buildCardStat(
                      Icons.warning_amber_rounded,
                      '${_stats.urgentTickets}',
                      'Urgent',
                      AdminColors.warning,
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // ── Resolution Progress ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ticket Resolution Rate',
                      style: TextStyle(
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Colors.white.withAlpha(160),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${_stats.resolutionPercentage}%',
                      style: TextStyle(
                        color: isDark
                            ? Brand.lightGreenBright
                            : Brand.lightGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkBorderLight.withAlpha(77)
                        : Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _stats.resolutionRate),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return FractionallySizedBox(
                          widthFactor: value.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isDark
                                    ? [
                                        Brand.lightGreenBright,
                                        Brand.lightGreen
                                      ]
                                    : [
                                        Brand.lightGreen,
                                        Brand.lightGreenBright
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                    ),
                  ]),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStat(
      IconData icon, String value, String label, Color color, bool isDark) {
    return Column(children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 30 : 18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: TextStyle(
          color: isDark ? Brand.darkTextPrimary : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      Text(
        label,
        style: TextStyle(
          color: isDark ? Brand.darkTextSecondary : Colors.white.withAlpha(160),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ]);
  }

  // ─── ESCALATION ALERT ────────────────────────────────────
  Widget _buildEscalationAlert(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: () => _navigateTo(const TicketsManagementPage()),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // FIX: .withOpacity() → .withAlpha()
            color: Colors.orange.withAlpha(isDark ? 26 : 15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withAlpha(64)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  // FIX: .withOpacity() → .withAlpha()
                  color: Colors.orange.withAlpha(38),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.warning_rounded,
                    color: Colors.orange[700], size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_escalatedCount Escalated Ticket${_escalatedCount == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange[700]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Engineers have flagged these for your attention',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isDark ? Brand.darkTextSecondary : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── OVERDUE INSTALLMENTS ALERT ──────────────────────────
  Widget _buildOverdueAlert(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: GestureDetector(
        onTap: () => _navigateTo(const AdminInstallmentsPage()),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // FIX: .withOpacity() → .withAlpha()
            color: AdminColors.error.withAlpha(isDark ? 26 : 15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminColors.error.withAlpha(64)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  // Already .withAlpha() ✅
                  color: AdminColors.error.withAlpha(38),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.payments_rounded,
                    color: AdminColors.error, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_overdueInstallments Overdue Payment${_overdueInstallments == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.error),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Customers have missed installment due dates',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isDark ? Brand.darkTextSecondary : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── STATS GRID ──────────────────────────────────────────
  Widget _buildStatsGrid(bool isDark) {
    final cards = [
      _OverviewKpi(
        iconWidget: (c) =>
            Icon(Icons.precision_manufacturing_rounded, color: c, size: 24),
        color: isDark ? Brand.lightGreenBright : AdminColors.accent,
        label: 'Machines',
        value: '${_stats.totalMachines}',
        onTap: () => _navigateTo(const MachinesManagementPage()),
      ),
      _OverviewKpi(
        iconWidget: (c) => Icon(Icons.people_rounded, color: c, size: 24),
        color: isDark ? Brand.royalBlueGlow : AdminColors.primary,
        label: 'Customers',
        value: '${_stats.totalCustomers}',
        badge: _stats.newCustomersThisMonth > 0
            ? '+${_stats.newCustomersThisMonth} new'
            : null,
        onTap: () => _navigateTo(const CustomersManagementPage()),
      ),
      _OverviewKpi(
        iconWidget: (c) => IcChatGearIcon(color: c, size: 24),
        color: AdminColors.warning,
        label: 'Open Tickets',
        value: '${_stats.openTickets}',
        onTap: () => _navigateTo(const TicketsManagementPage()),
      ),
      _OverviewKpi(
        iconWidget: (c) => Icon(Icons.mail_rounded, color: c, size: 24),
        color: AdminColors.info,
        label: 'Inquiries',
        value: '${_stats.totalInquiries}',
        badge: _stats.pendingInquiries > 0
            ? '${_stats.pendingInquiries} pending'
            : null,
        onTap: () => _navigateTo(const InquiryManagementPage()),
      ),
      if (_pendingReferralCount > 0)
        _OverviewKpi(
          iconWidget: (c) => Icon(Icons.people_alt_rounded, color: c, size: 24),
          color: const Color(0xFF06B6D4),
          label: 'Pending Referrals',
          value: '$_pendingReferralCount',
          badge: 'Awaiting review',
          onTap: () => _navigateTo(const ReferralManagementPage()),
        ),
      if (_overdueInstallments > 0)
        _OverviewKpi(
          iconWidget: (c) => Icon(Icons.payments_rounded, color: c, size: 24),
          color: AdminColors.error,
          label: 'Overdue Payments',
          value: '$_overdueInstallments',
          badge: 'Action needed',
          onTap: () => _navigateTo(const AdminInstallmentsPage()),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Overview'),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 92,
            ),
            itemCount: cards.length,
            itemBuilder: (_, i) => _buildOverviewCard(isDark, cards[i]),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(bool isDark, _OverviewKpi k) {
    return GestureDetector(
      onTap: k.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: k.color.withAlpha(28),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: k.iconWidget(k.color)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    k.value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    k.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (k.badge != null)
                    Text(
                      k.badge!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: k.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── QUICK ACTIONS ───────────────────────────────────────
  Widget _buildQuickActions(bool isDark) {
    final actions = [
      _QuickAction(
        'Machines',
        Icons.precision_manufacturing_rounded,
        isDark ? Brand.lightGreenBright : AdminColors.accent,
        () => _navigateTo(const MachinesManagementPage()),
      ),
      _QuickAction(
        'Engineers',
        Icons.engineering_rounded,
        const Color(0xFF00B4D8),
        () => _navigateTo(const EngineerManagementPage()),
      ),
      _QuickAction(
        'Analytics',
        Icons.analytics_rounded,
        const Color(0xFF8B5CF6),
        () => _navigateTo(const AnalyticsDashboardPage()),
      ),
      _QuickAction(
        'Broadcast',
        Icons.campaign_rounded,
        const Color(0xFFAB47BC),
        () => _navigateTo(const BroadcastNotificationsPage()),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Quick Actions'),
          const SizedBox(height: 14),
          GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: actions.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) =>
                _buildQuickActionItem(actions[index], isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem(_QuickAction action, bool isDark) {
    return GestureDetector(
      onTap: action.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: action.color.withAlpha(isDark ? 28 : 15),
                  borderRadius: BorderRadius.circular(16),
                  border: isDark
                      ? Border.all(
                          color: action.color.withAlpha(51),
                          width: 1,
                        )
                      : null,
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: action.color.withAlpha(15),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Icon(action.icon, color: action.color, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            action.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: isDark ? Brand.darkTextSecondary : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  FINANCIAL SNAPSHOT
  // ═══════════════════════════════════════════════════════════
  Widget _buildBusinessHub(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Brand.royalBlue.withAlpha(26)
                      : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.account_balance_wallet_rounded,
                    color: isDark
                        ? Brand.royalBlueGlow
                        : Brand.royalBlue,
                    size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Financial Snapshot',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    Text(
                      'Revenue, receivables & outstanding items',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildHubKpiGrid(isDark),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _formatCompactCurrency(double v) {
    if (v >= 1000000) return 'Rs. ${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return 'Rs. ${(v / 1000).toStringAsFixed(1)}K';
    return 'Rs. ${v.toStringAsFixed(0)}';
  }

  Widget _buildHubKpiGrid(bool isDark) {
    final cards = [
      _HubKpi(
        icon: Icons.trending_up_rounded,
        color: Brand.lightGreen,
        label: 'Revenue (This Month)',
        value: _formatCompactCurrency(_hubRevenueThisMonth),
      ),
      _HubKpi(
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFFF59E0B),
        label: 'Outstanding',
        value: _formatCompactCurrency(_hubOutstandingReceivables),
      ),
      _HubKpi(
        icon: Icons.request_quote_rounded,
        color: const Color(0xFF8B5CF6),
        label: 'Pending Quotations',
        value: '$_hubPendingQuotations',
      ),
      _HubKpi(
        icon: Icons.schedule_rounded,
        color: AdminColors.error,
        label: 'Overdue Installments',
        value: '$_hubOverdueInstallments',
      ),
    ];

    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 92,
      ),
      children: cards
          .map((k) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: isDark
                      ? Border.all(color: Brand.darkBorder)
                      : null,
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Brand.royalBlue.withAlpha(10),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.black.withAlpha(6),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: k.color.withAlpha(28),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(k.icon, color: k.color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            k.value,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            k.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ─── RECENT INQUIRIES ────────────────────────────────────
  Widget _buildRecentInquiriesSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        children: [
          SectionHeader(
            title: 'Recent Inquiries',
            actionLabel: 'View All',
            badgeCount: _stats.pendingInquiries,
            onActionTap: () => _navigateTo(const InquiryManagementPage()),
          ),
          const SizedBox(height: 14),
          if (_recentInquiries.isEmpty)
            const AdminEmptyState(
              message: 'No inquiries yet',
              icon: Icons.mail_outline_rounded,
            )
          else
            ...List.generate(
              _recentInquiries.length,
              (i) => InquiryCard(
                inquiry: _recentInquiries[i],
                onTap: () => _navigateTo(
                    InquiryDetailPage(inquiryId: _recentInquiries[i].id)),
              ),
            ),
        ],
      ),
    );
  }

  // ─── RECENT CUSTOMERS ────────────────────────────────────
  Widget _buildRecentCustomersSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        children: [
          SectionHeader(
            title: 'Recent Customers',
            actionLabel: 'View All',
            onActionTap: () => _navigateTo(const CustomersManagementPage()),
          ),
          const SizedBox(height: 14),
          if (_recentCustomers.isEmpty)
            const AdminEmptyState(
              message: 'No customers yet',
              icon: Icons.people_outline_rounded,
            )
          else
            ...List.generate(
              _recentCustomers.length,
              (i) => CustomerCard(
                customer: _recentCustomers[i],
                onTap: () => _navigateTo(
                    CustomerDetailPage(customerId: _recentCustomers[i].id)),
              ),
            ),
        ],
      ),
    );
  }

  // ─── BOTTOM NAVIGATION ───────────────────────────────────
  Widget _buildBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: isDark
            ? const Border(top: BorderSide(color: Brand.darkBorder, width: 1))
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
                  (c) => Icon(Icons.dashboard_rounded, color: c, size: 24),
                  'Dashboard',
                  0,
                  null,
                  isDark,
                ),
              ),
              Expanded(
                child: NavBadgeIndicator(
                  badgeType: NavBadgeType.inquiries,
                  builder: (_, count) => _buildNavItem(
                    (c) => Icon(Icons.mail_rounded, color: c, size: 24),
                    'Inquiries',
                    1,
                    const InquiryManagementPage(),
                    isDark,
                    badgeCount: count,
                  ),
                ),
              ),
              _buildNavCenterItem(isDark),
              Expanded(
                // Live badge: count of unread chat messages NOT sent by
                // the admin. Drops to 0 the moment the admin opens the
                // ticket and markMessagesAsRead runs.
                child: NavBadgeIndicator(
                  badgeType: NavBadgeType.tickets,
                  builder: (_, count) => _buildNavItem(
                    (c) => IcTicketIcon(color: c, size: 24),
                    'Tickets',
                    3,
                    const TicketsManagementPage(),
                    isDark,
                    badgeCount: count,
                  ),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  (c) => Icon(Icons.grid_view_rounded, color: c, size: 24),
                  'More',
                  4,
                  const AdminMorePage(),
                  isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavCenterItem(bool isDark) {
    return GestureDetector(
      onTap: () => _showQuickCreateSheet(isDark),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [Brand.royalBlue, Brand.royalBlueLight]
                : [AdminColors.primary, Brand.royalBlueLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Brand.royalBlue : AdminColors.primary)
                  .withAlpha(102),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
      ),
    );
  }

  void _showQuickCreateSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.55,
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.cardLight,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.darkBorder
                            : Colors.grey.withAlpha(77),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Quick Create',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _quickCreateTile(
                    sheetCtx,
                    isDark,
                    Icons.receipt_long_rounded,
                    'Create Invoice',
                    Brand.royalBlue,
                    () => _navigateTo(const CreateInvoicePage()),
                  ),
                  _quickCreateTile(
                    sheetCtx,
                    isDark,
                    Icons.description_rounded,
                    'Create Quotation',
                    const Color(0xFF8B5CF6),
                    () => _navigateTo(const CreateQuotationPage()),
                  ),
                  _quickCreateTile(
                    sheetCtx,
                    isDark,
                    Icons.precision_manufacturing_rounded,
                    'Register Machine',
                    Brand.lightGreen,
                    () => _navigateTo(const AdminRegisterMachinePage()),
                  ),
                  _quickCreateTile(
                    sheetCtx,
                    isDark,
                    Icons.calendar_month_rounded,
                    'Create Schedule',
                    const Color(0xFF14B8A6),
                    () => _navigateTo(const CreateSchedulePage()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _quickCreateTile(
    BuildContext sheetCtx,
    bool isDark,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: () {
        // L4: Guard the dismiss in case the sheet was already popped (e.g.
        // barrier-tap or back-press between render and tap), so we don't
        // throw from trying to pop an empty stack.
        final sheetNav = Navigator.of(sheetCtx);
        if (sheetNav.canPop()) sheetNav.pop();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkBg : Brand.scaffoldLight,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withAlpha(isDark ? 30 : 15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                size: 20,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    Widget Function(Color) iconBuilder,
    String label,
    int index,
    Widget? page,
    bool isDark, {
    int badgeCount = 0,
  }) {
    final isSelected = _selectedIndex == index;
    final iconColor = isSelected
        ? (isDark ? Brand.royalBlueGlow : AdminColors.primary)
        : (isDark ? Brand.darkTextTertiary : Colors.grey.shade400);

    return GestureDetector(
      onTap: () {
        if (_selectedIndex == index) {
          // Already on this tab — scroll to top on dashboard
          if (index == 0) {
            _scrollController.animateTo(0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut);
          }
          return;
        }
        setState(() {
          _selectedIndex = index;
        });
        // Refresh dashboard data when returning to it
        if (index == 0) _loadDashboardData(forceRefresh: true, silent: true);
      },
      behavior: HitTestBehavior.opaque,
      // FIX: full-width transparent hit area so taps anywhere in the
      // Expanded cell register — Column(mainAxisSize.min) alone gives
      // GestureDetector a tap area only as wide as the icon+label,
      // making side-edges of the cell unresponsive.
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: iconBuilder(iconColor),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AdminColors.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          // FIX: AdminColors.surface → Brand.cardLight
                          color: isDark ? Brand.darkCard : Brand.cardLight,
                          width: 1.5,
                        ),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Center(
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
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
                color: isSelected
                    ? (isDark ? Brand.royalBlueGlow : AdminColors.primary)
                    : (isDark ? Brand.darkTextTertiary : Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── NAVIGATION HELPER ───────────────────────────────────
  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) {
      if (mounted) _loadDashboardData(forceRefresh: true, silent: true);
    });
  }
}

// ─── BUSINESS HUB KPI DATA CLASS ─────────────────────────
class _HubKpi {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _HubKpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
}

// ─── OVERVIEW KPI DATA CLASS ─────────────────────────────
class _OverviewKpi {
  final Widget Function(Color) iconWidget;
  final Color color;
  final String label;
  final String value;
  final String? badge;
  final VoidCallback onTap;

  const _OverviewKpi({
    required this.iconWidget,
    required this.color,
    required this.label,
    required this.value,
    this.badge,
    required this.onTap,
  });
}

// ─── QUICK ACTION DATA CLASS ─────────────────────────────
class _QuickAction {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction(
    this.title,
    this.icon,
    this.color,
    this.onTap,
  );
}
