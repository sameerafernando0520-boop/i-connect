// lib/screens/admin/marketer_management_page.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import 'create_marketer_page.dart';

const Color _maAccent = StatusColors.assigned;

// 9 permission sections — keep in sync with create_marketer_page.dart
const _permSections = [
  _PermSection(
    key: 'customers',
    icon: Icons.people_rounded,
    label: 'Customer Directory',
    description: 'View customer profiles and their activity',
    color: AdminColors.info,
  ),
  _PermSection(
    key: 'referral_program',
    icon: Icons.share_rounded,
    label: 'Referral Program',
    description: 'View and manage referral rules, codes, and payouts',
    color: AdminColors.accent,
  ),
  _PermSection(
    key: 'loyalty_tiers',
    icon: Icons.star_rounded,
    label: 'Loyalty Tiers',
    description: 'Configure tier thresholds and benefits',
    color: AdminColors.warning,
  ),
  _PermSection(
    key: 'banners',
    icon: Icons.image_rounded,
    label: 'Promotional Banners',
    description: 'Create, edit, and remove promotional banners',
    color: Color(0xFFEC4899),
  ),
  _PermSection(
    key: 'knowledge_base',
    icon: Icons.menu_book_rounded,
    label: 'Knowledge Base',
    description: 'Manage articles and educational content',
    color: StatusColors.assigned,
  ),
  _PermSection(
    key: 'broadcast',
    icon: Icons.campaign_rounded,
    label: 'Broadcast Notifications',
    description: 'Send push notifications to all users',
    color: StatusColors.danger,
  ),
  _PermSection(
    key: 'analytics',
    icon: Icons.analytics_rounded,
    label: 'Analytics',
    description: 'View article views and user engagement data',
    color: AdminColors.primary,
  ),
  _PermSection(
    key: 'machine_catalog',
    icon: Icons.precision_manufacturing_rounded,
    label: 'Machine Catalog',
    description: 'Browse and view machine listings',
    color: AdminColors.info,
  ),
  _PermSection(
    key: 'point_activities',
    icon: Icons.emoji_events_rounded,
    label: 'Points & Rewards',
    description: 'View point activity and customer reward history',
    color: AdminColors.internal,
  ),
];

class _PermSection {
  final String key;
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  const _PermSection({
    required this.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
  });
}

class MarketerManagementPage extends StatefulWidget {
  const MarketerManagementPage({super.key});

  @override
  State<MarketerManagementPage> createState() => _MarketerManagementPageState();
}

class _MarketerManagementPageState extends State<MarketerManagementPage> {
  List<Map<String, dynamic>> _marketers = [];
  bool _isLoading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await SupabaseConfig.client
          .from('users')
          .select('*, marketer_permissions(*)')
          .eq('role', 'marketing_admin')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _marketers = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.trim().isEmpty) return _marketers;
    final q = _search.toLowerCase();
    return _marketers.where((m) {
      final name = (m['full_name'] ?? '').toString().toLowerCase();
      final username = (m['username'] ?? '').toString().toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
  }

  // ── Permissions Sheet ──────────────────────────────────────────────────────
  void _showPermissionsSheet(Map<String, dynamic> marketer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final permsData = marketer['marketer_permissions'] as Map<String, dynamic>?;
    final localPerms = <String, bool>{
      for (final s in _permSections)
        s.key: (permsData?[s.key] as bool?) ?? false,
    };
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle + Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                            borderRadius: BorderRadius.circular(Brand.r(2)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _maAccent.withAlpha(isDark ? 30 : 15),
                                borderRadius: BorderRadius.circular(Brand.r(12)),
                              ),
                              child: const Icon(Icons.tune_rounded, color: _maAccent, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Edit Permissions',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                                    ),
                                  ),
                                  Text(
                                    marketer['full_name'] ?? '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(color: isDark ? Brand.darkBorder : Brand.borderLight, height: 1),
                      ],
                    ),
                  ),
                  // Permission list
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _permSections.length,
                      separatorBuilder: (_, __) => Padding(
                        padding: const EdgeInsets.only(left: 72),
                        child: Divider(height: 1, color: isDark ? Brand.darkBorder : Brand.borderLight),
                      ),
                      itemBuilder: (_, i) {
                        final s = _permSections[i];
                        final enabled = localPerms[s.key] ?? false;
                        return InkWell(
                          onTap: () => setSheetState(() => localPerms[s.key] = !enabled),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: enabled ? s.color.withAlpha(isDark ? 40 : 20) : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
                                    borderRadius: BorderRadius.circular(Brand.r(10)),
                                  ),
                                  child: Icon(s.icon, size: 18, color: enabled ? s.color : AdminColors.textHint(sheetCtx)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.label,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        s.description,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: enabled,
                                  onChanged: (v) => setSheetState(() => localPerms[s.key] = v),
                                  activeThumbColor: s.color,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Save button
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                setSheetState(() => saving = true);
                                try {
                                  await SupabaseConfig.client
                                      .from('marketer_permissions')
                                      .update(localPerms)
                                      .eq('user_id', marketer['id']);

                                  if (!mounted || !sheetCtx.mounted) return;
                                  Navigator.pop(sheetCtx);
                                  _load();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Permissions updated', style: TextStyle(color: Colors.white)),
                                      backgroundColor: AdminColors.success,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  setSheetState(() => saving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed: $e', style: const TextStyle(color: Colors.white)),
                                      backgroundColor: AdminColors.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _maAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
                          elevation: 0,
                        ),
                        child: saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Permissions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Reset Password Sheet ───────────────────────────────────────────────────
  void _showResetPasswordSheet(Map<String, dynamic> marketer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pwCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscurePw = true;
    bool obscureConfirm = true;
    bool saving = false;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Brand.darkBorderLight : Brand.borderLight,
                        borderRadius: BorderRadius.circular(Brand.r(2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Reset Password',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Set a new password for ${marketer['full_name'] ?? ''}',
                    style: TextStyle(fontSize: 13, color: AdminColors.textHint(sheetCtx)),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: pwCtrl,
                    obscureText: obscurePw,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      hintText: 'Min 8 characters',
                      prefixIcon: Icon(Icons.lock_rounded, color: _maAccent, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePw ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 20),
                        onPressed: () => setSheetState(() => obscurePw = !obscurePw),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
                      filled: true,
                      fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 8) return 'At least 8 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: _maAccent, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 20),
                        onPressed: () => setSheetState(() => obscureConfirm = !obscureConfirm),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
                      filled: true,
                      fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                    ),
                    validator: (v) {
                      if (v != pwCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setSheetState(() => saving = true);
                              try {
                                final res = await SupabaseConfig.client.functions.invoke(
                                  'update-marketer-password',
                                  body: {'marketer_id': marketer['id'], 'new_password': pwCtrl.text},
                                );
                                if (!mounted || !sheetCtx.mounted) return;
                                if (res.status != 200) {
                                  final err = res.data?['error'] ?? 'Failed';
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(err.toString(), style: const TextStyle(color: Colors.white)),
                                    backgroundColor: AdminColors.error,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
                                  ));
                                  setSheetState(() => saving = false);
                                  return;
                                }
                                Navigator.pop(sheetCtx);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: const Text('Password updated', style: TextStyle(color: Colors.white)),
                                  backgroundColor: AdminColors.success,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
                                ));
                              } catch (e) {
                                if (!mounted) return;
                                setSheetState(() => saving = false);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
                                  backgroundColor: AdminColors.error,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
                                ));
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _maAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
                        elevation: 0,
                      ),
                      child: saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Update Password', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Deactivate / Reactivate ────────────────────────────────────────────────
  Future<void> _toggleActive(Map<String, dynamic> marketer) async {
    final isActive = marketer['date_terminated'] == null;
    final action = isActive ? 'deactivate' : 'reactivate';
    final name = marketer['full_name'] ?? 'this marketer';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${isActive ? 'Deactivate' : 'Reactivate'} Marketer'),
        content: Text(
          isActive
              ? 'Deactivating $name will immediately block their login access. You can reactivate at any time.'
              : 'Reactivating $name will restore their login access immediately.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: isActive ? AdminColors.error : AdminColors.success),
            child: Text(isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await SupabaseConfig.client.functions.invoke(
        '$action-marketer',
        body: {'marketer_id': marketer['id']},
      );
      if (!mounted) return;
      if (res.status != 200) {
        final err = res.data?['error'] ?? 'Failed';
        _showSnackError(err.toString());
        return;
      }
      _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${isActive ? 'Deactivated' : 'Reactivated'} $name', style: const TextStyle(color: Colors.white)),
        backgroundColor: isActive ? AdminColors.warning : AdminColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
      ));
    } catch (e) {
      if (!mounted) return;
      _showSnackError(e.toString());
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> _delete(Map<String, dynamic> marketer) async {
    final name = marketer['full_name'] ?? 'this marketer';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Marketer'),
        content: Text(
          'Permanently delete $name? This cannot be undone. Their account, login credentials, and all activity logs will be removed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AdminColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'delete-marketer',
        body: {'marketer_id': marketer['id']},
      );
      if (!mounted) return;
      if (res.status != 200) {
        final err = res.data?['error'] ?? 'Failed';
        _showSnackError(err.toString());
        return;
      }
      _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$name deleted', style: const TextStyle(color: Colors.white)),
        backgroundColor: AdminColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
      ));
    } catch (e) {
      if (!mounted) return;
      _showSnackError(e.toString());
    }
  }

  void _showSnackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_rounded, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
        ],
      ),
      backgroundColor: AdminColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Marketers',
        accent: HeroAccent.navy,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.person_add_rounded, color: Colors.white),
              tooltip: 'Add Marketer',
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateMarketerPage()),
                );
                if (result == true) _load();
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _maAccent,
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search by name or username…',
                  prefixIcon: Icon(Icons.search_rounded, color: AdminColors.textHint(context)),
                  filled: true,
                  fillColor: Brand.surface(isDark),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    borderSide: BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    borderSide: BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    borderSide: const BorderSide(color: _maAccent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _maAccent))
                  : _error != null
                      ? _buildError(isDark)
                      : _filtered.isEmpty
                          ? _buildEmpty(isDark)
                          : _buildList(isDark),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateMarketerPage()),
          );
          if (result == true) _load();
        },
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Marketer', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _maAccent,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: AdminColors.error),
          const SizedBox(height: 12),
          Text(
            'Failed to load marketers',
            style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _maAccent.withAlpha(isDark ? 30 : 15),
                  borderRadius: BorderRadius.circular(Brand.r(20)),
                ),
                child: const Icon(Icons.campaign_rounded, size: 36, color: _maAccent),
              ),
              const SizedBox(height: 16),
              Text(
                _search.isEmpty ? 'No marketers yet' : 'No results for "$_search"',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _search.isEmpty ? 'Add your first marketing team member.' : 'Try a different search term.',
                style: TextStyle(fontSize: 13, color: AdminColors.textHint(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildCard(_filtered[i], isDark),
    );
  }

  Widget _buildCard(Map<String, dynamic> m, bool isDark) {
    final isActive = m['date_terminated'] == null;
    final photoUrl = m['profile_photo'] as String?;
    final name = m['full_name'] ?? 'Unknown';
    final username = m['username'] ?? '';
    final permsData = m['marketer_permissions'] as Map<String, dynamic>?;
    final activePerms = _permSections.where((s) => (permsData?[s.key] as bool?) == true).toList();

    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: _maAccent.withAlpha(isDark ? 40 : 20),
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: photoUrl,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const SizedBox(),
                                errorWidget: (_, __, ___) => Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'M',
                                  style: const TextStyle(color: _maAccent, fontWeight: FontWeight.w700, fontSize: 18),
                                ),
                              ),
                            )
                          : Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'M',
                              style: const TextStyle(color: _maAccent, fontWeight: FontWeight.w700, fontSize: 18),
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isActive ? AdminColors.success : AdminColors.textHint(context),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Brand.surface(isDark),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isActive ? AdminColors.success : AdminColors.textHint(context)).withAlpha(isDark ? 30 : 20),
                    borderRadius: BorderRadius.circular(Brand.r(8)),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActive ? AdminColors.success : AdminColors.textHint(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Active permissions chips
          if (activePerms.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: activePerms.map((s) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: s.color.withAlpha(isDark ? 30 : 15),
                    borderRadius: BorderRadius.circular(Brand.r(8)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.icon, size: 12, color: s.color),
                      const SizedBox(width: 4),
                      Text(
                        s.label,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: s.color),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: AdminColors.textHint(context)),
                  const SizedBox(width: 6),
                  Text(
                    'No permissions granted',
                    style: TextStyle(fontSize: 12, color: AdminColors.textHint(context)),
                  ),
                ],
              ),
            ),
          ],
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                _actionBtn(
                  icon: Icons.tune_rounded,
                  label: 'Permissions',
                  color: _maAccent,
                  isDark: isDark,
                  onTap: () => _showPermissionsSheet(m),
                ),
                const SizedBox(width: 8),
                _actionBtn(
                  icon: Icons.lock_reset_rounded,
                  label: 'Password',
                  color: AdminColors.info,
                  isDark: isDark,
                  onTap: () => _showResetPasswordSheet(m),
                ),
                const SizedBox(width: 8),
                _actionBtn(
                  icon: isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                  label: isActive ? 'Deactivate' : 'Activate',
                  color: isActive ? AdminColors.warning : AdminColors.success,
                  isDark: isDark,
                  onTap: () => _toggleActive(m),
                ),
                const SizedBox(width: 8),
                _actionBtn(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: AdminColors.error,
                  isDark: isDark,
                  onTap: () => _delete(m),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.r(10)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(isDark ? 25 : 12),
            borderRadius: BorderRadius.circular(Brand.r(10)),
            border: Border.all(color: color.withAlpha(isDark ? 50 : 30)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
