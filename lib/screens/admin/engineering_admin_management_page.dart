// lib/screens/admin/engineering_admin_management_page.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import 'create_engineering_admin_page.dart';

const Color _eaAccent = Color(0xFF0EA5E9); // sky blue

class EngineeringAdminManagementPage extends StatefulWidget {
  const EngineeringAdminManagementPage({super.key});

  @override
  State<EngineeringAdminManagementPage> createState() =>
      _EngineeringAdminManagementPageState();
}

class _EngineeringAdminManagementPageState
    extends State<EngineeringAdminManagementPage> {
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, email, profile_photo, created_at')
          .eq('role', 'engineering_admin')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _admins = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Extracts the username from the synthetic email.
  /// e.g. "egadmin@engineering.iconnect.lk" → "egadmin"
  String _usernameFrom(String email) {
    final at = email.indexOf('@');
    return at == -1 ? email : email.substring(0, at);
  }

  Future<void> _confirmDelete(Map<String, dynamic> admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: Brand.surface(isDark),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Remove Engineering Admin',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          content: Text(
            'Remove "${admin['full_name'] ?? ''}"? They will no longer be able to log in.',
            style: TextStyle(
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Brand.subtleLight)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove',
                  style: TextStyle(
                      color: AdminColors.error,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      // Delete auth user via admin API (service role handled by edge fn)
      await SupabaseConfig.client.functions.invoke(
        'delete-user',
        body: {'user_id': admin['id']},
      );
    } catch (_) {
      // Fallback: just delete the public.users row
    }

    // Always delete public.users row (RLS allows admin)
    try {
      await SupabaseConfig.client
          .from('users')
          .delete()
          .eq('id', admin['id'] as String);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to remove: $e'),
        backgroundColor: AdminColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white),
        const SizedBox(width: 10),
        Text('"${admin['full_name'] ?? ''}" removed',
            style: const TextStyle(color: Colors.white)),
      ]),
      backgroundColor: AdminColors.success,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Engineering Admins',
        accent: HeroAccent.navy,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () async {
                final refreshed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateEngineeringAdminPage(),
                  ),
                );
                if (refreshed == true) _load();
              },
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              label: const Text('Add',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(isDark)
              : _admins.isEmpty
                  ? _buildEmpty(isDark)
                  : _buildList(isDark),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: AdminColors.error),
            const SizedBox(height: 12),
            Text('Failed to load',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                )),
            const SizedBox(height: 6),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isDark
                        ? Brand.darkTextSecondary
                        : Brand.subtleLight)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _eaAccent.withAlpha(isDark ? 30 : 20),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.admin_panel_settings_rounded,
                  size: 34, color: _eaAccent),
            ),
            const SizedBox(height: 16),
            Text(
              'No Engineering Admins',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add an engineering admin account\nto get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Brand.darkTextSecondary
                      : Brand.subtleLight),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final refreshed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateEngineeringAdminPage(),
                  ),
                );
                if (refreshed == true) _load();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Engineering Admin'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _eaAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Header count
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '${_admins.length} admin${_admins.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Brand.surface(isDark),
              borderRadius: BorderRadius.circular(18),
              border: isDark ? Border.all(color: Brand.darkBorder) : null,
            ),
            child: Column(
              children: _admins.asMap().entries.map((entry) {
                final i = entry.key;
                final admin = entry.value;
                final isLast = i == _admins.length - 1;
                return _buildAdminTile(admin, isDark, isLast);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminTile(
      Map<String, dynamic> admin, bool isDark, bool isLast) {
    final name = (admin['full_name'] ?? '—') as String;
    final email = (admin['email'] ?? '') as String;
    final username = _usernameFrom(email);
    final photo = admin['profile_photo'] as String?;
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _eaAccent.withAlpha(isDark ? 40 : 20),
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: photo != null && photo.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photo,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Center(
                          child: Text(initial,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _eaAccent)),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Text(initial,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _eaAccent)),
                        ),
                      )
                    : Center(
                        child: Text(initial,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: _eaAccent)),
                      ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.alternate_email_rounded,
                            size: 13,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight),
                        const SizedBox(width: 4),
                        Text(
                          username,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Role badge + delete
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _eaAccent.withAlpha(isDark ? 30 : 18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'EA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _eaAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 20, color: AdminColors.error),
                    onPressed: () => _confirmDelete(admin),
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Divider(
                height: 1,
                color: isDark ? Brand.darkBorder : Brand.borderLight),
          ),
      ],
    );
  }
}
