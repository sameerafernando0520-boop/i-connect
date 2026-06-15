// lib/screens/admin/create_marketer_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';

const Color _maAccent = Color(0xFFD946EF);

// 9 permission sections — keep in sync with marketer_management_page.dart
const _permSections = [
  _PermSection(
    key: 'customers',
    icon: Icons.people_rounded,
    label: 'Customer Directory',
    description: 'View customer profiles and their activity',
    color: Color(0xFF3B82F6),
  ),
  _PermSection(
    key: 'referral_program',
    icon: Icons.share_rounded,
    label: 'Referral Program',
    description: 'View and manage referral rules, codes, and payouts',
    color: Color(0xFF10B981),
  ),
  _PermSection(
    key: 'loyalty_tiers',
    icon: Icons.star_rounded,
    label: 'Loyalty Tiers',
    description: 'Configure tier thresholds and benefits',
    color: Color(0xFFF59E0B),
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
    color: Color(0xFF8B5CF6),
  ),
  _PermSection(
    key: 'broadcast',
    icon: Icons.campaign_rounded,
    label: 'Broadcast Notifications',
    description: 'Send push notifications to all users',
    color: Color(0xFFEF4444),
  ),
  _PermSection(
    key: 'analytics',
    icon: Icons.analytics_rounded,
    label: 'Analytics',
    description: 'View article views and user engagement data',
    color: Color(0xFF6366F1),
  ),
  _PermSection(
    key: 'machine_catalog',
    icon: Icons.precision_manufacturing_rounded,
    label: 'Machine Catalog',
    description: 'Browse and view machine listings',
    color: Color(0xFF14B8A6),
  ),
  _PermSection(
    key: 'point_activities',
    icon: Icons.emoji_events_rounded,
    label: 'Points & Rewards',
    description: 'View point activity and customer reward history',
    color: Color(0xFFF97316),
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

class CreateMarketerPage extends StatefulWidget {
  const CreateMarketerPage({super.key});

  @override
  State<CreateMarketerPage> createState() => _CreateMarketerPageState();
}

class _CreateMarketerPageState extends State<CreateMarketerPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  // Permission toggles — all off by default
  final Map<String, bool> _perms = {
    for (final s in _permSections) s.key: false,
  };

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'create-marketer',
        body: {
          'username': _usernameCtrl.text.trim().toLowerCase(),
          'full_name': _fullNameCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'permissions': _perms,
        },
      );

      if (!mounted) return;

      if (res.status != 200) {
        final msg = res.data?['error'] ?? 'Failed to create marketer';
        _showError(msg.toString());
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Marketer "${_fullNameCtrl.text.trim()}" created successfully',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      Navigator.pop(context, true); // true = refresh list
    } catch (e) {
      if (!mounted) return;
      _showError('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: AdminColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Add Marketer',
        accent: HeroAccent.navy,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : TextButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                    label: const Text('Create',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            // ── Account Details ──────────────────────────────────
            _sectionLabel('Account Details', isDark),
            _card(
              isDark,
              children: [
                _buildTextField(
                  controller: _usernameCtrl,
                  isDark: isDark,
                  label: 'Username',
                  hint: 'e.g. john.doe',
                  icon: Icons.alternate_email_rounded,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Username is required';
                    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(v.trim())) {
                      return 'Only lowercase letters, numbers, dots and underscores';
                    }
                    if (v.trim().length < 3) return 'At least 3 characters';
                    return null;
                  },
                ),
                _divider(isDark),
                _buildTextField(
                  controller: _fullNameCtrl,
                  isDark: isDark,
                  label: 'Full Name',
                  hint: 'e.g. John Doe',
                  icon: Icons.person_rounded,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Full name is required';
                    if (v.trim().length < 2) return 'At least 2 characters';
                    return null;
                  },
                ),
                _divider(isDark),
                _buildTextField(
                  controller: _passwordCtrl,
                  isDark: isDark,
                  label: 'Password',
                  hint: 'Min 8 characters',
                  icon: Icons.lock_rounded,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      color: AdminColors.textHint(context),
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
                _divider(isDark),
                _buildTextField(
                  controller: _confirmCtrl,
                  isDark: isDark,
                  label: 'Confirm Password',
                  hint: 'Re-enter password',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscureConfirm,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      color: AdminColors.textHint(context),
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please confirm password';
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Username must be unique. The marketer will log in with their username — not an email address.',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textHint(context),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Permissions ──────────────────────────────────────
            _sectionLabel('Permissions', isDark),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Grant only the sections this marketer needs. You can change these at any time.',
                style: TextStyle(fontSize: 12, color: AdminColors.textHint(context)),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              isDark,
              children: List.generate(_permSections.length, (i) {
                final s = _permSections[i];
                final isLast = i == _permSections.length - 1;
                return Column(
                  children: [
                    _buildPermTile(s, isDark),
                    if (!isLast) _divider(isDark),
                  ],
                );
              }),
            ),
            const SizedBox(height: 32),

            // ── Create Button ────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _create,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.person_add_rounded, size: 20),
                label: Text(
                  _isLoading ? 'Creating...' : 'Create Marketer Account',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _maAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        ),
      ),
    );
  }

  Widget _card(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Divider(height: 1, color: isDark ? Brand.darkBorder : Brand.borderLight),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required bool isDark,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        validator: validator,
        style: TextStyle(
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20, color: _maAccent),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          labelStyle: TextStyle(
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            fontSize: 13,
          ),
          hintStyle: TextStyle(
            color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
            fontSize: 14,
          ),
          errorStyle: const TextStyle(fontSize: 11),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildPermTile(_PermSection s, bool isDark) {
    final enabled = _perms[s.key] ?? false;
    return InkWell(
      onTap: () => setState(() => _perms[s.key] = !enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: enabled ? s.color.withAlpha(isDark ? 40 : 20) : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(s.icon, size: 18, color: enabled ? s.color : AdminColors.textHint(context)),
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
            const SizedBox(width: 8),
            Switch(
              value: enabled,
              onChanged: (v) => setState(() => _perms[s.key] = v),
              activeThumbColor: s.color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}
