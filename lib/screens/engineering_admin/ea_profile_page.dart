// lib/screens/engineering_admin/ea_profile_page.dart
// Engineering Admin Portal — Profile, settings & logout

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../widgets/common/language_selector_sheet.dart';
import '../auth/login_page.dart';
import '../../widgets/common/theme_style_sheet.dart';

const Color _eaAccent = Color(0xFF16A34A);

class EaProfilePage extends StatefulWidget {
  const EaProfilePage({super.key});

  @override
  State<EaProfilePage> createState() => _EaProfilePageState();
}

class _EaProfilePageState extends State<EaProfilePage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) {
        setState(() => _loading = false);
        return;
      }
      final data = await SupabaseConfig.client
          .from('users')
          .select(
              'id, full_name, email, phone_number, role, profile_photo, '
              'employee_id, date_joined, specializations')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _profile = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _signingOut = true);
    try {
      await SupabaseConfig.client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign-out failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: AppBar(
        backgroundColor: isDark ? Brand.darkCard : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'My Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextPrimary : const Color(0xFF0F172A),
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _eaAccent))
          : RefreshIndicator(
              onRefresh: _load,
              color: _eaAccent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Avatar + name banner ──────────────────────────────
                  _buildProfileBanner(isDark),
                  const SizedBox(height: 20),

                  // ── Info section ──────────────────────────────────────
                  _buildSection(
                    isDark: isDark,
                    title: 'Account Information',
                    children: [
                      _buildInfoRow(
                        isDark: isDark,
                        icon: Icons.person_outline_rounded,
                        label: 'Full Name',
                        value: _profile?['full_name'] as String? ?? '—',
                      ),
                      _buildInfoRow(
                        isDark: isDark,
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: _profile?['email'] as String? ?? '—',
                      ),
                      _buildInfoRow(
                        isDark: isDark,
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: _profile?['phone_number'] as String? ?? '—',
                      ),
                      _buildInfoRow(
                        isDark: isDark,
                        icon: Icons.badge_outlined,
                        label: 'Employee ID',
                        value: _profile?['employee_id'] as String? ?? '—',
                      ),
                      _buildInfoRow(
                        isDark: isDark,
                        icon: Icons.calendar_today_outlined,
                        label: 'Date Joined',
                        value: _profile?['date_joined'] != null
                            ? _formatDate(_profile!['date_joined'] as String)
                            : '—',
                        isLast: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Specializations ───────────────────────────────────
                  if ((_profile?['specializations'] as List?)?.isNotEmpty ==
                      true) ...[
                    _buildSection(
                      isDark: isDark,
                      title: 'Specializations',
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s
                                  in (_profile!['specializations'] as List))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _eaAccent.withAlpha(isDark ? 40 : 22),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: _eaAccent.withAlpha(
                                            isDark ? 80 : 50)),
                                  ),
                                  child: Text(
                                    s.toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _eaAccent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Preferences ───────────────────────────────────────
                  _buildSection(
                    isDark: isDark,
                    title: 'Preferences',
                    children: [
                      _buildThemeToggle(isDark),
                      Divider(
                          height: 1,
                          color: isDark ? Brand.darkBorder : Brand.borderLight),
                      _buildDarkStyleTile(isDark),
                      Divider(
                          height: 1,
                          color: isDark ? Brand.darkBorder : Brand.borderLight),
                      _buildLanguageTile(isDark),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── App info ──────────────────────────────────────────
                  _buildSection(
                    isDark: isDark,
                    title: 'About',
                    children: [
                      _buildInfoRow(
                        isDark: isDark,
                        icon: Icons.info_outline_rounded,
                        label: 'Role',
                        value: 'Engineering Admin',
                      ),
                      _buildInfoRow(
                        isDark: isDark,
                        icon: Icons.business_outlined,
                        label: 'Company',
                        value: 'iFrontiers (Pvt) Ltd',
                        isLast: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Sign out button ────────────────────────────────────
                  _buildSignOutButton(isDark),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── Profile banner ─────────────────────────────────────────────────────────

  Widget _buildProfileBanner(bool isDark) {
    final name = _profile?['full_name'] as String? ?? 'Engineering Admin';
    final email = _profile?['email'] as String? ?? '';
    final photo = _profile?['profile_photo'] as String?;
    final empId = _profile?['employee_id'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 10,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _eaAccent.withAlpha(100), width: 2.5),
            ),
            child: ClipOval(
              child: photo != null && photo.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: _eaAccent.withAlpha(30),
                        child: Icon(Icons.person_rounded,
                            color: _eaAccent, size: 36),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: _eaAccent.withAlpha(30),
                        child: Icon(Icons.person_rounded,
                            color: _eaAccent, size: 36),
                      ),
                    )
                  : Container(
                      color: _eaAccent.withAlpha(30),
                      child:
                          Icon(Icons.person_rounded, color: _eaAccent, size: 36),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 13,
                    color: AdminColors.textSub(context),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _eaAccent.withAlpha(isDark ? 45 : 25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _eaAccent.withAlpha(isDark ? 80 : 50)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 12, color: _eaAccent),
                          const SizedBox(width: 5),
                          Text(
                            'Engineering Admin',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _eaAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (empId != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '#$empId',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textHint(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card ───────────────────────────────────────────────────────────

  Widget _buildSection({
    required bool isDark,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AdminColors.textHint(context),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
             border: isDark
             ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withAlpha(6),
                        blurRadius: 10,
                        offset: const Offset(0, 2))
                  ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ── Info row ───────────────────────────────────────────────────────────────

  Widget _buildInfoRow({
    required bool isDark,
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: _eaAccent),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: AdminColors.textSub(context),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              height: 1,
              indent: 46,
              color: isDark ? Brand.darkBorder : Brand.borderLight),
      ],
    );
  }

  // ── Theme toggle ───────────────────────────────────────────────────────────

  Widget _buildThemeToggle(bool isDark) {
    return Consumer<ThemeProvider>(
      builder: (ctx, tp, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(
              tp.isDarkMode
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              size: 18,
              color: _eaAccent,
            ),
            const SizedBox(width: 12),
            Text(
              'Dark Mode',
              style: TextStyle(
                fontSize: 14,
                color: AdminColors.textSub(ctx),
              ),
            ),
            const Spacer(),
            Switch.adaptive(
              value: tp.isDarkMode,
              onChanged: (_) => tp.toggleTheme(),
              activeThumbColor: _eaAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkStyleTile(bool isDark) {
    return Consumer<ThemeProvider>(
      builder: (ctx, tp, _) => InkWell(
        onTap: () => ThemeStyleSheet.show(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.style_rounded, size: 18, color: _eaAccent),
              const SizedBox(width: 12),
              Text(
                'Dark style',
                style: TextStyle(
                  fontSize: 14,
                  color: AdminColors.textSub(ctx),
                ),
              ),
              const Spacer(),
              Text(
                ThemeProvider.styleName(tp.darkStyle),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.text(ctx),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AdminColors.textHint(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Language tile ──────────────────────────────────────────────────────────

  Widget _buildLanguageTile(bool isDark) {
    return Consumer<LocaleProvider>(
      builder: (ctx, lp, _) => InkWell(
        onTap: () => showLanguageSelector(ctx),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.language_outlined, size: 18, color: _eaAccent),
              const SizedBox(width: 12),
              Text(
                'Language',
                style: TextStyle(
                  fontSize: 14,
                  color: AdminColors.textSub(ctx),
                ),
              ),
              const Spacer(),
              Text(
                lp.currentLanguageName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? Brand.darkTextPrimary
                      : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AdminColors.textHint(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sign-out button ────────────────────────────────────────────────────────

  Widget _buildSignOutButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _signingOut ? null : _signOut,
        icon: _signingOut
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.logout_rounded, size: 18),
        label: Text(_signingOut ? 'Signing out…' : 'Sign Out'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade600,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.red.shade300,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return iso;
    }
  }
}
