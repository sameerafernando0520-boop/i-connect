// lib/screens/marketing/ma_profile_page.dart
//
// Premium marketing admin profile — matches customer profile_page.dart
// design language with hero card, stats, and premium card styling.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../utils/string_utils.dart';
import '../../widgets/common/language_selector_sheet.dart';
import '../../screens/auth/login_page.dart';
import '../../widgets/common/theme_style_sheet.dart';
import '../../utils/app_logger.dart';

class MaProfilePage extends StatefulWidget {
  const MaProfilePage({super.key});

  @override
  State<MaProfilePage> createState() => _MaProfilePageState();
}

class _MaProfilePageState extends State<MaProfilePage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _hasError = false;

  // ── Stats ──
  int _totalCustomers = 0;
  int _publishedArticles = 0;
  int _broadcastsSent = 0;
  int _activeReferrals = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait<dynamic>([
        // 0: profile
        SupabaseConfig.client
            .from('users')
            .select('full_name, username, email, profile_photo, created_at')
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
        // 3: broadcasts sent
        SupabaseConfig.client
            .from('notifications')
            .select('id')
            .eq('type', 'broadcast'),
        // 4: active referrals
        SupabaseConfig.client
            .from('referrals')
            .select('id')
            .inFilter('status', ['signed_up', 'cooling', 'qualified']),
      ]);

      if (!mounted) return;
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _totalCustomers = (results[1] as List).length;
        _publishedArticles = (results[2] as List).length;
        _broadcastsSent = (results[3] as List).length;
        _activeReferrals = (results[4] as List).length;
        _loading = false;
        _hasError = false;
      });
    } catch (e) {
      AppLogger.debug('MaProfilePage', 'Profile load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _logout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _buildConfirmDialog(
        icon: Icons.logout_rounded,
        iconColor: isDark ? StatusColors.softRed : Colors.red.shade400,
        title: 'Sign Out?',
        message: 'Are you sure you want to sign out\nof your account?',
        confirmText: 'Sign Out',
        confirmColor: Colors.red,
        isDark: isDark,
      ),
    );
    if (confirmed != true || !mounted) return;

    // Show loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await SupabaseConfig.client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss overlay
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss overlay
      _showError('Sign out failed');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
    ));
  }

  String _getMemberSince() {
    final raw = _profile?['created_at'] as String?;
    if (raw == null) return 'N/A';
    try {
      final d = DateTime.parse(raw);
      const m = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${m[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) return _buildLoadingState(isDark);
    if (_hasError) return _buildErrorState(isDark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Brand.canvas(isDark),
        appBar: DsPageHeader(
          title: 'Profile',
          showBack: false,
          accent: HeroAccent.violet,
        ),
        body: RefreshIndicator(
          color: isDark ? Brand.royalBlueGlow : AdminColors.primary,
          backgroundColor: Brand.surface(isDark),
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: _buildProfileHero(isDark)),
              SliverToBoxAdapter(child: _buildStatsGrid(isDark)),
              SliverToBoxAdapter(child: _buildAccountInfo(isDark)),
              SliverToBoxAdapter(child: _buildAppearanceSection(isDark)),
              SliverToBoxAdapter(child: _buildLanguageSection(isDark)),
              SliverToBoxAdapter(child: _buildLogoutSection(isDark)),
              SliverToBoxAdapter(child: _buildVersion(isDark)),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── LOADING STATE ───────────────────────────────────────────
  Widget _buildLoadingState(bool isDark) {
    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(Brand.r(22)),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: isDark ? Brand.royalBlueGlow : AdminColors.primary,
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading profile...',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── ERROR STATE ─────────────────────────────────────────────
  Widget _buildErrorState(bool isDark) {
    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: BorderRadius.circular(Brand.r(24)),
              border: isDark ? Border.all(color: Brand.darkBorder) : null,
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Brand.royalBlue.withAlpha(10),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(isDark ? 38 : 26),
                    borderRadius: BorderRadius.circular(Brand.r(22)),
                  ),
                  child: Icon(Icons.error_outline,
                      size: 36,
                      color:
                          isDark ? StatusColors.softRed : Colors.red),
                ),
                const SizedBox(height: 20),
                Text(
                  'Failed to Load Profile',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const SizedBox(height: 10),
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
                  onTap: () {
                    setState(() {
                      _loading = true;
                      _hasError = false;
                    });
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
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
                        Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Retry',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── PROFILE HERO CARD ───────────────────────────────────────
  Widget _buildProfileHero(bool isDark) {
    final name = _profile?['full_name'] as String? ?? 'Marketer';
    final username = _profile?['username'] as String? ?? '';
    final email = _profile?['email'] as String? ?? '';
    final photoUrl = _profile?['profile_photo'] as String?;
    final perms = context.watch<PermissionsProvider>();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.r(26)),
        gradient: LinearGradient(
          colors: isDark
              ? [Brand.darkCard, Brand.darkCardElevated]
              : [Brand.royalBlueDark, Brand.royalBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border:
            isDark ? Border.all(color: Brand.darkBorderLight, width: 1) : null,
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
      child: Stack(
        children: [
          // ── Decorative circles (matching customer profile hero) ──
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Brand.darkBorderLight.withAlpha(38)
                    : Colors.white.withAlpha(10),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Brand.darkBorderLight.withAlpha(26)
                    : Colors.white.withAlpha(8),
              ),
            ),
          ),
          Positioned(
            left: -15,
            bottom: 15,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Brand.darkBorderLight.withAlpha(20)
                    : Colors.white.withAlpha(5),
              ),
            ),
          ),

          // ── Content ──
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar with border
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? Brand.darkBorderLight
                              : Colors.white.withAlpha(51),
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                fit: BoxFit.cover,
                                width: 76,
                                height: 76,
                                placeholder: (_, __) =>
                                    _avatarFallback(name, isDark),
                                errorWidget: (_, __, ___) =>
                                    _avatarFallback(name, isDark),
                              )
                            : _avatarFallback(name, isDark),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            username.isNotEmpty ? '@$username' : email,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Colors.white.withAlpha(140),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // Role badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Brand.royalBlue.withAlpha(38)
                                      : Colors.white.withAlpha(31),
                                  borderRadius: BorderRadius.circular(Brand.r(20)),
                                  border: Border.all(
                                    color: isDark
                                        ? Brand.royalBlueGlow.withAlpha(51)
                                        : Colors.white.withAlpha(46),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.campaign_rounded,
                                        size: 12,
                                        color: isDark
                                            ? Brand.royalBlueGlow
                                            : Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Marketing Admin',
                                      style: TextStyle(
                                        color: isDark
                                            ? Brand.royalBlueGlow
                                            : Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // ── Info row (modules + member since) ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Brand.lightGreen.withAlpha(26)
                            : Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                        border: Border.all(
                          color: isDark
                              ? Brand.lightGreen.withAlpha(38)
                              : Colors.white.withAlpha(26),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.grid_view_rounded,
                              color: isDark
                                  ? Brand.lightGreenBright
                                  : Colors.white,
                              size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${perms.enabledCount} modules',
                            style: TextStyle(
                              color: isDark
                                  ? Brand.lightGreenBright
                                  : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Since ${_getMemberSince()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : Colors.white.withAlpha(89),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name, bool isDark) {
    return Container(
      width: 76,
      height: 76,
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
          StringUtils.getInitials(name),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 26,
          ),
        ),
      ),
    );
  }

  // ─── STATS GRID ──────────────────────────────────────────────
  Widget _buildStatsGrid(bool isDark) {
    final stats = [
      _StatItem(Icons.people_rounded, '$_totalCustomers', 'Customers',
          isDark ? Brand.royalBlueGlow : AdminColors.primary),
      _StatItem(Icons.article_rounded, '$_publishedArticles', 'Articles',
          isDark ? Brand.lightGreenBright : Brand.lightGreen),
      _StatItem(Icons.campaign_rounded, '$_broadcastsSent', 'Broadcasts',
          isDark ? StatusColors.warningLight : AdminColors.error),
      _StatItem(Icons.share_rounded, '$_activeReferrals', 'Referrals',
          StatusColors.resolved),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: stats.map((s) {
          final isLast = s == stats.last;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: isLast ? 0 : 10),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(Brand.r(18)),
                border: Border.all(
                  color: isDark ? Brand.darkBorder : s.color.withAlpha(26),
                ),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: s.color.withAlpha(13),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: s.color.withAlpha(isDark ? 31 : 20),
                      borderRadius: BorderRadius.circular(Brand.r(11)),
                      border: isDark
                          ? Border.all(color: s.color.withAlpha(38))
                          : null,
                    ),
                    child: Icon(s.icon, color: s.color, size: 19),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.value,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── ACCOUNT INFO ────────────────────────────────────────────
  Widget _buildAccountInfo(bool isDark) {
    final email = _profile?['email'] as String? ?? '';
    final username = _profile?['username'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: _premiumCardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Account Details', isDark),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.email_rounded, 'Email', email, isDark,
              color: AdminColors.primary),
          if (username.isNotEmpty) ...[
            Divider(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
                height: 1),
            _buildInfoRow(
                Icons.alternate_email_rounded, 'Username', '@$username', isDark,
                color: StatusColors.assigned),
          ],
          Divider(
              color: isDark ? Brand.darkBorder : Brand.borderLight, height: 1),
          _buildInfoRow(Icons.calendar_today_rounded, 'Member Since',
              _getMemberSince(), isDark,
              color: StatusColors.resolved),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
      IconData icon, String label, String value, bool isDark,
      {Color? color}) {
    final c = color ?? AdminColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.withAlpha(isDark ? 30 : 15),
              borderRadius: BorderRadius.circular(Brand.r(11)),
              border: isDark ? Border.all(color: c.withAlpha(38)) : null,
            ),
            child: Icon(icon, size: 18, color: c),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
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

  // ─── APPEARANCE SECTION ──────────────────────────────────────
  Widget _buildAppearanceSection(bool isDark) {
    final themeProvider = context.watch<ThemeProvider>();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: _premiumCardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Appearance', isDark),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: StatusColors.indigo.withAlpha(isDark ? 30 : 15),
                  borderRadius: BorderRadius.circular(Brand.r(13)),
                  border: isDark
                      ? Border.all(
                          color: StatusColors.indigo.withAlpha(51))
                      : null,
                ),
                child: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  size: 22,
                  color: StatusColors.indigo,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dark Mode',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDark ? 'Currently enabled' : 'Currently disabled',
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
              Switch(
                value: themeProvider.isDarkMode,
                onChanged: (_) => themeProvider.toggleTheme(),
                activeThumbColor: StatusColors.indigo,
                activeTrackColor: StatusColors.indigo.withAlpha(77),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const SizedBox(
              width: 44,
              child: Icon(Icons.style_rounded,
                  size: 22, color: StatusColors.indigo),
            ),
            title: Text(
              'Dark style',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color:
                    isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                ThemeProvider.styleName(themeProvider.darkStyle),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? Brand.darkTextSecondary
                      : Brand.subtleLight,
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark
                      ? Brand.darkTextTertiary
                      : Brand.subtleLight),
            ]),
            onTap: () => ThemeStyleSheet.show(context),
          ),
        ],
      ),
    );
  }

  // ─── LANGUAGE SECTION ────────────────────────────────────────
  Widget _buildLanguageSection(bool isDark) {
    final localeProvider = context.watch<LocaleProvider>();

    return GestureDetector(
      onTap: () => showLanguageSelector(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(20),
        decoration: _premiumCardDecoration(isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Language', isDark),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: StatusColors.teal.withAlpha(isDark ? 30 : 15),
                    borderRadius: BorderRadius.circular(Brand.r(13)),
                    border: isDark
                        ? Border.all(
                            color: StatusColors.teal.withAlpha(51))
                        : null,
                  ),
                  child: const Icon(Icons.language_rounded,
                      size: 22, color: StatusColors.teal),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localeProvider.currentLanguageName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to change language',
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
                Icon(Icons.chevron_right_rounded,
                    size: 22,
                    color:
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── LOGOUT SECTION ──────────────────────────────────────────
  Widget _buildLogoutSection(bool isDark) {
    return GestureDetector(
      onTap: _logout,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(22)),
          border: isDark
              ? Border.all(color: Colors.red.withAlpha(38))
              : Border.all(color: Colors.red.withAlpha(20)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.red.withAlpha(8),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(isDark ? 30 : 15),
                borderRadius: BorderRadius.circular(Brand.r(13)),
                border: isDark
                    ? Border.all(color: Colors.red.withAlpha(51))
                    : null,
              ),
              child: Icon(Icons.logout_rounded,
                  size: 22,
                  color: isDark ? StatusColors.softRed : Colors.red),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sign Out',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? StatusColors.softRed : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sign out of your account',
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
                size: 22,
                color: isDark
                    ? StatusColors.softRed.withAlpha(128)
                    : Colors.red.withAlpha(128)),
          ],
        ),
      ),
    );
  }

  // ─── VERSION ─────────────────────────────────────────────────
  Widget _buildVersion(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: Column(
          children: [
            Text(
              'iFrontiers Connect',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Brand.darkTextTertiary
                    : Brand.subtleLight.withAlpha(128),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Marketing Admin • v1.0.0',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? Brand.darkTextTertiary.withAlpha(128)
                    : Brand.subtleLight.withAlpha(89),
              ),
            ),
          ],
        ),
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

  // ─── PREMIUM CARD DECORATION ─────────────────────────────────
  BoxDecoration _premiumCardDecoration(bool isDark) {
    return BoxDecoration(
      color: isDark ? Brand.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(Brand.r(22)),
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
    );
  }

  // ─── CONFIRM DIALOG ──────────────────────────────────────────
  Widget _buildConfirmDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
    required bool isDark,
  }) {
    return Dialog(
      backgroundColor: Brand.surface(isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(24))),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: iconColor.withAlpha(isDark ? 31 : 26),
                borderRadius: BorderRadius.circular(Brand.r(20)),
                border: isDark
                    ? Border.all(color: iconColor.withAlpha(38))
                    : null,
              ),
              child: Icon(icon, color: iconColor, size: 34),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildDialogButton(
                    'Cancel',
                    isDark ? Brand.darkBorderLight : Brand.borderLight,
                    isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    false,
                    () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDialogButton(
                    confirmText,
                    confirmColor,
                    Colors.white,
                    true,
                    () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogButton(
    String text,
    Color bg,
    Color fg,
    bool filled,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? bg : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border: filled ? null : Border.all(color: bg),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: bg.withAlpha(89),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Helper data class ──
class _StatItem {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem(this.icon, this.value, this.label, this.color);
}
