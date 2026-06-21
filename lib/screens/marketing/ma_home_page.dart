// lib/screens/marketing/ma_home_page.dart
//
// Premium marketing admin dashboard — matches admin_dashboard.dart design
// language with marketing-specific KPIs and module access.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../providers/permissions_provider.dart';
import '../../utils/time_utils.dart';
import '../../utils/string_utils.dart';
import '../../widgets/ds/ds_widgets.dart';
import 'ma_banners_page.dart';
import 'ma_knowledge_base_page.dart';
import 'ma_broadcast_page.dart';
import 'ma_referral_page.dart';
import 'ma_tiers_page.dart';
import 'ma_customers_page.dart';
import 'ma_catalog_page.dart';
import 'ma_points_page.dart';
import 'ma_analytics_page.dart';
import '../../utils/app_logger.dart';

// ── Module tile data class ──
class _NavTile {
  final String permKey;
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final Widget Function() pageBuilder;

  const _NavTile({
    required this.permKey,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.pageBuilder,
  });
}

final _allTiles = <_NavTile>[
  _NavTile(
    permKey: 'banners',
    icon: Icons.image_rounded,
    label: 'Banners',
    subtitle: 'Promotional banners',
    color: StatusColors.pink,
    pageBuilder: () => const MaBannersPage(),
  ),
  _NavTile(
    permKey: 'knowledge_base',
    icon: Icons.menu_book_rounded,
    label: 'Knowledge Base',
    subtitle: 'Articles & guides',
    color: StatusColors.assigned,
    pageBuilder: () => const MaKnowledgeBasePage(),
  ),
  _NavTile(
    permKey: 'broadcast',
    icon: Icons.campaign_rounded,
    label: 'Broadcast',
    subtitle: 'Send notifications',
    color: AdminColors.error,
    pageBuilder: () => const MaBroadcastPage(),
  ),
  _NavTile(
    permKey: 'referral_program',
    icon: Icons.share_rounded,
    label: 'Referral',
    subtitle: 'Referral program',
    color: StatusColors.resolved,
    pageBuilder: () => const MaReferralPage(),
  ),
  _NavTile(
    permKey: 'loyalty_tiers',
    icon: Icons.star_rounded,
    label: 'Tiers',
    subtitle: 'Loyalty tiers',
    color: AdminColors.warning,
    pageBuilder: () => const MaTiersPage(),
  ),
  _NavTile(
    permKey: 'customers',
    icon: Icons.people_rounded,
    label: 'Customers',
    subtitle: 'Customer directory',
    color: AdminColors.info,
    pageBuilder: () => const MaCustomersPage(),
  ),
  _NavTile(
    permKey: 'machine_catalog',
    icon: Icons.precision_manufacturing_rounded,
    label: 'Catalog',
    subtitle: 'Machine catalog',
    color: StatusColors.teal,
    pageBuilder: () => const MaCatalogPage(),
  ),
  _NavTile(
    permKey: 'point_activities',
    icon: Icons.emoji_events_rounded,
    label: 'Points',
    subtitle: 'Points activity',
    color: AdminColors.internal,
    pageBuilder: () => const MaPointsPage(),
  ),
  _NavTile(
    permKey: 'analytics',
    icon: Icons.analytics_rounded,
    label: 'Analytics',
    subtitle: 'KB analytics',
    color: StatusColors.indigo,
    pageBuilder: () => const MaAnalyticsPage(),
  ),
];

class MaHomePage extends StatefulWidget {
  const MaHomePage({super.key});

  @override
  State<MaHomePage> createState() => _MaHomePageState();
}

class _MaHomePageState extends State<MaHomePage> {
  // ── Profile ──
  String _name = 'Marketer';
  String? _photoUrl;

  // ── Dashboard stats ──
  int _totalCustomers = 0;
  int _publishedArticles = 0;
  int _activeBanners = 0;
  int _broadcastsSent = 0;
  int _activeReferrals = 0;
  int _totalPointsDistributed = 0;
  int _totalCatalogItems = 0;
  int _newCustomersThisMonth = 0;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _loadDashboard(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = _totalCustomers == 0 && _publishedArticles == 0;
        _isRefreshing = !_isLoading;
        _error = null;
      });
    }

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toUtc().toIso8601String();

      final results = await Future.wait<dynamic>([
        // 0: profile
        SupabaseConfig.client
            .from('users')
            .select('full_name, profile_photo')
            .eq('id', user.id)
            .maybeSingle(),
        // 1: total customers
        SupabaseConfig.client
            .from('users')
            .select('id')
            .eq('role', 'customer'),
        // 2: published articles
        SupabaseConfig.client
            .from('knowledge_base')
            .select('id')
            .eq('is_published', true),
        // 3: active banners
        SupabaseConfig.client
            .from('promotional_banners')
            .select('id')
            .eq('is_active', true),
        // 4: broadcasts sent
        SupabaseConfig.client
            .from('notifications')
            .select('id')
            .eq('type', 'broadcast'),
        // 5: active referrals (pending or signed up)
        SupabaseConfig.client
            .from('referrals')
            .select('id')
            .inFilter('status', ['signed_up', 'cooling', 'qualified']),
        // 6: total points distributed
        SupabaseConfig.client
            .from('point_activities')
            .select('final_points'),
        // 7: catalog items
        SupabaseConfig.client
            .from('machine_catalog')
            .select('id'),
        // 8: new customers this month
        SupabaseConfig.client
            .from('users')
            .select('id')
            .eq('role', 'customer')
            .gte('created_at', monthStart),
      ]);

      if (!mounted) return;

      final profile = results[0] as Map<String, dynamic>?;
      final customers = results[1] as List;
      final articles = results[2] as List;
      final banners = results[3] as List;
      final broadcasts = results[4] as List;
      final referrals = results[5] as List;
      final pointsList = results[6] as List;
      final catalog = results[7] as List;
      final newCustomers = results[8] as List;

      int totalPoints = 0;
      for (final p in pointsList) {
        final v = p['final_points'];
        if (v is num) totalPoints += v.toInt();
      }

      setState(() {
        _name = profile?['full_name'] as String? ?? 'Marketer';
        _photoUrl = profile?['profile_photo'] as String?;
        _totalCustomers = customers.length;
        _publishedArticles = articles.length;
        _activeBanners = banners.length;
        _broadcastsSent = broadcasts.length;
        _activeReferrals = referrals.length;
        _totalPointsDistributed = totalPoints;
        _totalCatalogItems = catalog.length;
        _newCustomersThisMonth = newCustomers.length;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      AppLogger.debug('MaHomePage', 'Marketing dashboard error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _error = e.toString();
      });
    }
  }

  void _navigateTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) {
      if (mounted) _loadDashboard(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final perms = context.watch<PermissionsProvider>();
    final visibleTiles =
        _allTiles.where((t) => perms.check(t.permKey)).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The navy hero sits behind the status bar in both modes.
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: SafeArea(
          top: false,
          bottom: false,
          child: _isLoading
              ? _buildSkeleton(isDark)
              : _error != null && _totalCustomers == 0
                  ? _buildErrorState(isDark)
                  : RefreshIndicator(
                      onRefresh: _loadDashboard,
                      color: AdminColors.primary,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (_isRefreshing)
                            SliverToBoxAdapter(
                                child: _buildRefreshIndicator(isDark)),
                          SliverToBoxAdapter(child: _buildHeader(isDark)),
                          SliverToBoxAdapter(child: _buildHeroCard(isDark)),
                          SliverToBoxAdapter(child: _buildStatsGrid(isDark)),
                          SliverToBoxAdapter(
                              child: _buildQuickActions(isDark, visibleTiles)),
                          SliverToBoxAdapter(
                              child: _buildModulesSection(
                                  isDark, visibleTiles, perms)),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 100)),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  // ─── SKELETON ────────────────────────────────────────────────
  Widget _buildSkeleton(bool isDark) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _skBox(52, 52, 16, isDark),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skBox(90, 12, 6, isDark),
                  const SizedBox(height: 8),
                  _skBox(150, 20, 8, isDark),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _skBox(double.infinity, 180, 22, isDark),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _skBox(double.infinity, 92, 18, isDark)),
            const SizedBox(width: 10),
            Expanded(child: _skBox(double.infinity, 92, 18, isDark)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _skBox(double.infinity, 92, 18, isDark)),
            const SizedBox(width: 10),
            Expanded(child: _skBox(double.infinity, 92, 18, isDark)),
          ]),
          const SizedBox(height: 28),
          _skBox(130, 18, 8, isDark),
          const SizedBox(height: 14),
          _skBox(double.infinity, 74, 16, isDark),
          const SizedBox(height: 10),
          _skBox(double.infinity, 74, 16, isDark),
          const SizedBox(height: 10),
          _skBox(double.infinity, 74, 16, isDark),
        ],
      ),
    );
  }

  Widget _skBox(double w, double h, double r, bool isDark) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: isDark
              ? Brand.darkBorderLight.withAlpha(77)
              : Brand.royalBlue.withAlpha(13),
          borderRadius: BorderRadius.circular(r),
        ),
      );

  // ─── REFRESHING INDICATOR ────────────────────────────────────
  Widget _buildRefreshIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AdminColors.primary.withAlpha(isDark ? 31 : 20),
            borderRadius: BorderRadius.circular(Brand.r(20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Brand.royalBlueGlow : AdminColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Updating...',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Brand.royalBlueGlow : AdminColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ERROR STATE ─────────────────────────────────────────────
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
                color: AdminColors.error.withAlpha(isDark ? 31 : 20),
                borderRadius: BorderRadius.circular(Brand.r(24)),
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
                color: isDark ? Brand.darkTextPrimary : AdminColors.primaryDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _loadDashboard,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  color: AdminColors.primary,
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  boxShadow: [
                    BoxShadow(
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
                    Text('Retry',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOP HEADER ──────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return DsHero(
      greeting: TimeUtils.getGreeting(),
      title: _name,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          onPressed: _loadDashboard,
          icon: const Icon(Icons.refresh_rounded,
              size: 20, color: Brand.subtleLight),
        ),
        DsHeroAvatar(
          initials: StringUtils.getInitials(_name),
          color: StatusColors.assigned,
          photoUrl: _photoUrl,
        ),
      ]),
      actionCard: DsHeroCard(
        icon: Icons.campaign_rounded,
        iconColor: StatusColors.lavender,
        label: 'Marketing studio',
        title: 'Banners, broadcasts & loyalty',
        onTap: () {},
      ),
    );
  }

  // ─── HERO DASHBOARD CARD ─────────────────────────────────────
  Widget _buildHeroCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.r(22)),
        color: isDark ? Brand.darkCard : Colors.white,
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          // Top accent bar
          Container(
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(Brand.r(22)),
                topRight: Radius.circular(Brand.r(22)),
              ),
              gradient: LinearGradient(
                colors: isDark
                    ? [Brand.royalBlue, Brand.royalBlueLight]
                    : [AdminColors.primary, Brand.royalBlueLight],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge row
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.royalBlue.withAlpha(38)
                          : Brand.royalBlueSurface,
                      borderRadius: BorderRadius.circular(Brand.r(20)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.campaign_rounded,
                          color: isDark
                              ? Brand.royalBlueGlow
                              : AdminColors.primary,
                          size: 13),
                      const SizedBox(width: 5),
                      Text(
                        'Marketing Dashboard',
                        style: TextStyle(
                          color: isDark
                              ? Brand.royalBlueGlow
                              : AdminColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ]),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.lightGreen.withAlpha(26)
                          : Brand.lightGreenSurface,
                      borderRadius: BorderRadius.circular(Brand.r(20)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle,
                          color: isDark
                              ? Brand.lightGreenBright
                              : Brand.lightGreen,
                          size: 7),
                      const SizedBox(width: 5),
                      Text(
                        'Active',
                        style: TextStyle(
                          color: isDark
                              ? Brand.lightGreenBright
                              : Brand.lightGreenDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 22),

                // Stats row
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
                                : Brand.subtleLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_totalCustomers',
                          style: TextStyle(
                            color: isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark,
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
                      '+$_newCustomersThisMonth',
                      'This Month',
                      isDark ? Brand.lightGreenBright : Brand.lightGreen,
                      isDark,
                    ),
                    const SizedBox(width: 14),
                    _buildCardStat(
                      Icons.article_rounded,
                      '$_publishedArticles',
                      'Articles',
                      isDark ? Brand.royalBlueGlow : AdminColors.info,
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Content coverage bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Content Coverage',
                      style: TextStyle(
                        color:
                            isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '$_activeBanners active banner${_activeBanners == 1 ? '' : 's'}',
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
                        : Brand.borderLight,
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: Stack(children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                          begin: 0,
                          end: _publishedArticles > 0
                              ? (_publishedArticles / (_publishedArticles + 5))
                                  .clamp(0.1, 1.0)
                              : 0.0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return FractionallySizedBox(
                          widthFactor: value.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isDark
                                    ? [Brand.lightGreenBright, Brand.lightGreen]
                                    : [Brand.lightGreen, Brand.lightGreenBright],
                              ),
                              borderRadius: BorderRadius.circular(Brand.r(10)),
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
          borderRadius: BorderRadius.circular(Brand.r(14)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: TextStyle(
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      Text(
        label,
        style: TextStyle(
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ]);
  }

  // ─── STATS GRID ──────────────────────────────────────────────
  Widget _buildStatsGrid(bool isDark) {
    final cards = [
      _KpiData(
        icon: Icons.campaign_rounded,
        color: AdminColors.error,
        label: 'Broadcasts',
        value: '$_broadcastsSent',
        badge: 'Sent',
      ),
      _KpiData(
        icon: Icons.people_alt_rounded,
        color: StatusColors.resolved,
        label: 'Referrals',
        value: '$_activeReferrals',
        badge: 'Active',
      ),
      _KpiData(
        icon: Icons.emoji_events_rounded,
        color: AdminColors.internal,
        label: 'Points Given',
        value: _formatCompact(_totalPointsDistributed),
        badge: 'Total',
      ),
      _KpiData(
        icon: Icons.precision_manufacturing_rounded,
        color: StatusColors.teal,
        label: 'Catalog Items',
        value: '$_totalCatalogItems',
        badge: 'Machines',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Overview', isDark),
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
            itemBuilder: (_, i) => _buildKpiCard(isDark, cards[i]),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(bool isDark, _KpiData k) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
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
              borderRadius: BorderRadius.circular(Brand.r(12)),
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
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
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
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
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
    );
  }

  // ─── QUICK ACTIONS (matches admin_dashboard.dart pattern) ─────
  Widget _buildQuickActions(bool isDark, List<_NavTile> visibleTiles) {
    // Show top 4 accessible modules as quick-action icons
    final actions = visibleTiles.take(4).toList();
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Quick Actions', isDark),
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
            itemBuilder: (_, i) =>
                _buildQuickActionItem(actions[i], isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem(_NavTile tile, bool isDark) {
    return GestureDetector(
      onTap: () => _navigateTo(tile.pageBuilder()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tile.color.withAlpha(isDark ? 28 : 15),
              borderRadius: BorderRadius.circular(Brand.r(16)),
              border: isDark
                  ? Border.all(color: tile.color.withAlpha(51), width: 1)
                  : null,
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: tile.color.withAlpha(15),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Icon(tile.icon, color: tile.color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            tile.label,
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

  // ─── MODULES SECTION ─────────────────────────────────────────
  Widget _buildModulesSection(
      bool isDark, List<_NavTile> visibleTiles, PermissionsProvider perms) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionTitle('Your Modules', isDark),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? AdminColors.primary.withAlpha(26)
                      : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                child: Text(
                  '${perms.enabledCount} of 9',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.royalBlueGlow : AdminColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (visibleTiles.isEmpty)
            _buildNoAccess(isDark)
          else
            ...visibleTiles.map((tile) => _buildModuleTile(tile, isDark)),
        ],
      ),
    );
  }

  Widget _buildModuleTile(_NavTile tile, bool isDark) {
    return GestureDetector(
      onTap: () => _navigateTo(tile.pageBuilder()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: isDark ? Border.all(color: Brand.darkBorder) : null,
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
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tile.color.withAlpha(isDark ? 30 : 15),
                borderRadius: BorderRadius.circular(Brand.r(13)),
                border: isDark
                    ? Border.all(color: tile.color.withAlpha(51), width: 1)
                    : null,
              ),
              child: Icon(tile.icon, size: 22, color: tile.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tile.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tile.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAccess(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 16,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AdminColors.primary.withAlpha(isDark ? 30 : 15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_outline_rounded,
                size: 32,
                color: isDark ? Brand.royalBlueGlow : AdminColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'No modules enabled',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Contact your admin to grant access to marketing modules.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight),
          ),
        ],
      ),
    );
  }

  // ─── SECTION TITLE ───────────────────────────────────────────
  Widget _buildSectionTitle(String title, bool isDark) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Brand.darkIconActive, Brand.royalBlueGlow]
                  : [AdminColors.primary, Brand.royalBlueLight],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(Brand.r(2)),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────
  String _formatCompact(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }
}

// ── KPI Data Class ──
class _KpiData {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? badge;

  const _KpiData({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.badge,
  });
}
