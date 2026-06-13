// lib/screens/engineering_admin/ea_create_engineer_page.dart
// Engineering Admin Portal — Create Engineer (username + password, no email)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';

const Color _eaAccent = Color(0xFF16A34A); // sky blue

const _allSpecializations = [
  'Digital Printers',
  'Eco Solvent Printers',
  'UV Printers',
  'CNC Machines',
  'Laser Cutters',
  'CO2 Lasers',
  'Fiber Lasers',
  'Finishing Equipment',
  'General Support',
  'Installation',
  'Calibration',
];

class EaCreateEngineerPage extends StatefulWidget {
  const EaCreateEngineerPage({super.key});

  @override
  State<EaCreateEngineerPage> createState() => _EaCreateEngineerPageState();
}

class _EaCreateEngineerPageState extends State<EaCreateEngineerPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  final List<String> _selectedSpecs = [];

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'create-engineer',
        body: {
          'username': _usernameCtrl.text.trim().toLowerCase(),
          'full_name': _fullNameCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'phone_number':
              _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          'specializations': _selectedSpecs,
          'engineer_bio':
              _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        },
      );

      if (!mounted) return;

      final data = res.data;
      final success = data is Map && data['success'] == true;

      if (!success) {
        final msg =
            (data is Map ? data['error']?.toString() : null) ??
                'Failed to create engineer';
        _showError(msg);
        return;
      }

      final username = _usernameCtrl.text.trim().toLowerCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Engineer "$username" created successfully',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            Expanded(
                child: Text(msg, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: AdminColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: AppBar(
        title: Text(
          'Add Engineer',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        backgroundColor: Brand.surface(isDark),
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Create'),
                    style: TextButton.styleFrom(
                      foregroundColor: _eaAccent,
                      textStyle:
                          const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            // ── Info banner ──────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _eaAccent.withAlpha(isDark ? 25 : 15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _eaAccent.withAlpha(60)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: _eaAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Engineers log in with their username and password — '
                      'no email required. Share credentials via WhatsApp or phone.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Account Details ──────────────────────────────────────
            _sectionLabel('Account Details', isDark),
            _card(
              isDark,
              children: [
                _buildTextField(
                  controller: _usernameCtrl,
                  isDark: isDark,
                  label: 'Username',
                  hint: 'e.g. john.smith',
                  icon: Icons.alternate_email_rounded,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Username is required';
                    }
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
                  hint: 'e.g. John Smith',
                  icon: Icons.person_rounded,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Full name is required';
                    }
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
                      _obscurePassword
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: AdminColors.textHint(context),
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
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
                      _obscureConfirm
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: AdminColors.textHint(context),
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please confirm password';
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                _divider(isDark),
                _buildTextField(
                  controller: _phoneCtrl,
                  isDark: isDark,
                  label: 'Phone Number (optional)',
                  hint: 'e.g. 077 1234567',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Specializations ──────────────────────────────────────
            _sectionLabel('Specializations', isDark),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(18),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select all that apply',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allSpecializations.map((s) {
                      final isSel = _selectedSpecs.contains(s);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (isSel) {
                            _selectedSpecs.remove(s);
                          } else {
                            _selectedSpecs.add(s);
                          }
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSel
                                ? _eaAccent.withAlpha(isDark ? 38 : 31)
                                : (isDark
                                    ? Brand.darkCardElevated
                                    : Brand.royalBlueSurface),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSel
                                  ? _eaAccent.withAlpha(128)
                                  : (isDark
                                      ? Brand.darkBorder
                                      : Brand.borderLight),
                              width: isSel ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSel) ...[
                                Icon(Icons.check_rounded,
                                    size: 13, color: _eaAccent),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                s,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSel
                                      ? _eaAccent
                                      : (isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Bio ──────────────────────────────────────────────────
            _sectionLabel('Bio (Optional)', isDark),
            Container(
              decoration: BoxDecoration(
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(18),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextFormField(
                  controller: _bioCtrl,
                  maxLines: 3,
                  style: TextStyle(
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Short introduction about this engineer...',
                    prefixIcon: Icon(Icons.person_pin_rounded,
                        size: 20, color: _eaAccent),
                    border: InputBorder.none,
                    labelStyle: TextStyle(
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Brand.subtleLight,
                      fontSize: 13,
                    ),
                    hintStyle: TextStyle(
                      color: isDark
                          ? Brand.darkTextTertiary
                          : Brand.subtleLight,
                      fontSize: 14,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Username must be unique. Login: username + password. '
                'The engineer can change the password anytime.',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textHint(context),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Create Button ────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _create,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.person_add_rounded, size: 20),
                label: Text(
                  _isLoading ? 'Creating...' : 'Create Engineer Account',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _eaAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

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
         border: isDark
         ? Border.all(color: Brand.darkBorder) : null,
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Divider(
          height: 1,
          color: isDark ? Brand.darkBorder : Brand.borderLight),
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
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        textCapitalization: textCapitalization,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: TextStyle(
          color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20, color: _eaAccent),
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
}
