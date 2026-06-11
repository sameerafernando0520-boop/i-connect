// lib/screens/admin/admin_settings_page.dart
//
// ═══════════════════════════════════════════════════════════
//  CHANGES (v14 i18n):
//   [i18n-1] Added language selector tile (AppLocalizations + LocaleProvider)
//   [i18n-2] authLogout key used on logout button
//   [i18n-3] settingsLanguage key used on language tile
// ═══════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
// FIX-1: correct import path for generated localizations
import '../../l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
// FIX-2: type-only import is acceptable per rules
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/string_utils.dart';
import '../../utils/upload_validator.dart';
import '../../widgets/common/language_selector_sheet.dart';
import '../auth/login_page.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  // ─── State ─────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isUploading = false;

  // Profile
  String _fullName = '';
  String _email = '';
  String _phone = '';
  String? _profilePhotoUrl;

  // Notification settings
  bool _pushEnabled = true;
  bool _emailEnabled = true;
  bool _ticketUpdates = true;
  bool _newMessages = true;
  bool _promotions = false;

  // Support contacts
  List<Map<String, dynamic>> _supportContacts = [];

  // ─── Theme-aware color helpers ─────────────────────────────
  Color _scaffoldBg(bool d) => d ? Brand.darkBg : Brand.scaffoldLight;
  Color _cardBg(bool d) => d ? Brand.darkCard : Brand.cardLight;
  Color _textPrimary(bool d) =>
      d ? Brand.darkTextPrimary : const Color(0xFF1A1A2E);
  Color _textSecondary(bool d) =>
      d ? Brand.darkTextSecondary : Colors.grey.shade600;
  Color _textMuted(bool d) => d ? Brand.darkTextTertiary : Brand.subtleLight;
  Color _borderColor(bool d) => d ? Brand.darkBorder : Brand.borderLight;
  Color _dividerColor(bool d) =>
      d ? Brand.darkBorderLight : Colors.grey.shade100;
  Color _sheetBg(bool d) => d ? Brand.darkCard : Colors.white;
  Color _handleColor(bool d) =>
      d ? Brand.darkBorderLight : Colors.grey.shade300;

  List<BoxShadow> _cardShadow(bool d) => d
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ];

  List<BoxShadow> _softShadow(bool d) => d
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  // ─── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // FIX-3: explicit <dynamic> type on Future.wait
      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('users')
            .select('full_name, email, phone_number, profile_photo')
            .eq('id', userId)
            .single(),
        _loadNotificationSettings(userId),
      ]);

      if (!mounted) return;

      // FIX-4: explicit casts since Future.wait<dynamic> loses types
      final profile = results[0] as Map<String, dynamic>;
      final notifSettings = results[1] as Map<String, dynamic>;

      setState(() {
        _fullName = (profile['full_name'] as String?) ?? '';
        _email = (profile['email'] as String?) ?? '';
        _phone = (profile['phone_number'] as String?) ?? '';
        _profilePhotoUrl = profile['profile_photo'] as String?;

        _pushEnabled = (notifSettings['push_enabled'] as bool?) ?? true;
        _emailEnabled = (notifSettings['email_enabled'] as bool?) ?? true;
        _ticketUpdates = (notifSettings['ticket_updates'] as bool?) ?? true;
        _newMessages = (notifSettings['new_messages'] as bool?) ?? true;
        _promotions = (notifSettings['promotions'] as bool?) ?? false;

        _isLoading = false;
      });

      // Load support contacts (non-blocking)
      _loadSupportContacts();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Failed to load settings: $e', isError: true);
    }
  }

  Future<void> _loadSupportContacts() async {
    try {
      final rows = await SupabaseConfig.client
          .from('support_contacts')
          .select('*')
          .order('display_order');
      if (!mounted) return;
      setState(() {
        _supportContacts = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      debugPrint('Support contacts load failed: $e');
    }
  }

  Future<Map<String, dynamic>> _loadNotificationSettings(String userId) async {
    try {
      final data = await SupabaseConfig.client
          .from('notification_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null) return Map<String, dynamic>.from(data);

      // FIX-5: spread copy to avoid direct map mutation
      const defaults = <String, dynamic>{
        'push_enabled': true,
        'email_enabled': true,
        'ticket_updates': true,
        'new_messages': true,
        'promotions': false,
      };

      await SupabaseConfig.client
          .from('notification_settings')
          .insert({...defaults, 'user_id': userId});

      return Map<String, dynamic>.from(defaults);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  // ─── Storage Cleanup Helper ────────────────────────────────
  String? _extractStoragePath(String? url) {
    if (url == null || url.isEmpty) return null;
    const marker = '/profile-photos/';
    final idx = url.indexOf(marker);
    if (idx == -1) return null;
    return url.substring(idx + marker.length);
  }

  Future<void> _deleteStorageFile(String? url) async {
    final path = _extractStoragePath(url);
    if (path == null) return;
    try {
      await SupabaseConfig.client.storage.from('profile-photos').remove([path]);
    } catch (_) {}
  }

  // ─── Profile Photo ─────────────────────────────────────────
  void _showPhotoOptions(bool isDark) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _sheetBg(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _handleColor(isDark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Profile Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textPrimary(isDark),
              ),
            ),
            const SizedBox(height: 20),
            _buildPhotoOption(
              Icons.camera_alt_rounded,
              'Take Photo',
              Brand.royalBlue,
              isDark,
              () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.camera);
              },
            ),
            _buildPhotoOption(
              Icons.photo_library_rounded,
              'Choose from Gallery',
              Brand.lightGreen,
              isDark,
              () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_profilePhotoUrl != null)
              _buildPhotoOption(
                Icons.delete_outline_rounded,
                'Remove Photo',
                Colors.red,
                isDark,
                () {
                  Navigator.pop(sheetCtx);
                  _removePhoto();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoOption(
    IconData icon,
    String label,
    Color color,
    bool isDark,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 31 : 15),
          borderRadius: BorderRadius.circular(14),
          border: isDark ? Border.all(color: color.withAlpha(38)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(isDark ? 46 : 26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _textPrimary(isDark),
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: _textMuted(isDark)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;

      setState(() => _isUploading = true);

      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isUploading = false);
        return;
      }

      final bytes = await File(picked.path).readAsBytes();

      // Validate before touching storage
      final validation = UploadValidator.validate(
        bytes: bytes,
        filename: picked.path.split('/').last,
        category: UploadCategory.profilePhoto,
      );
      if (!validation.ok) {
        if (!mounted) return;
        setState(() => _isUploading = false);
        _showSnackBar(validation.error!, isError: true);
        return;
      }

      final ext = picked.path.split('.').last.toLowerCase();
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      // Delete old photo from storage first
      await _deleteStorageFile(_profilePhotoUrl);

      await SupabaseConfig.client.storage.from('profile-photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = SupabaseConfig.client.storage
          .from('profile-photos')
          .getPublicUrl(path);

      await SupabaseConfig.client.from('users').update({
        'profile_photo': publicUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      if (!mounted) return;
      setState(() {
        _profilePhotoUrl = publicUrl;
        _isUploading = false;
      });
      _showSnackBar('Profile photo updated', icon: Icons.check_circle_rounded);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      _showSnackBar('Upload failed: $e', isError: true);
    }
  }

  Future<void> _removePhoto() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      await _deleteStorageFile(_profilePhotoUrl);

      await SupabaseConfig.client.from('users').update({
        'profile_photo': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      if (!mounted) return;
      setState(() => _profilePhotoUrl = null);
      _showSnackBar('Photo removed', icon: Icons.check_circle_rounded);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to remove photo: $e', isError: true);
    }
  }

  // ─── Edit Profile ──────────────────────────────────────────
  void _showEditProfile(bool isDark) {
    final nameCtrl = TextEditingController(text: _fullName);
    final phoneCtrl = TextEditingController(text: _phone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _sheetBg(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _handleColor(isDark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary(isDark),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Full Name',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary(isDark),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: _textPrimary(isDark)),
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration('Enter your name', isDark),
              ),
              const SizedBox(height: 18),
              Text(
                'Phone Number',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary(isDark),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: _textPrimary(isDark)),
                decoration: _inputDecoration('Enter phone number', isDark),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    _showSnackBar('Name cannot be empty', isError: true);
                    return;
                  }

                  try {
                    final userId = SupabaseConfig.client.auth.currentUser?.id;
                    if (userId == null) return;

                    await SupabaseConfig.client.from('users').update({
                      'full_name': name,
                      'phone_number': phoneCtrl.text.trim(),
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    }).eq('id', userId);

                    // FIX-6: check sheetCtx.mounted before pop
                    if (!sheetCtx.mounted) return;
                    Navigator.pop(sheetCtx);

                    // FIX-7: check mounted after async gap
                    if (!mounted) return;
                    setState(() {
                      _fullName = name;
                      _phone = phoneCtrl.text.trim();
                    });
                    _showSnackBar('Profile updated',
                        icon: Icons.check_circle_rounded);
                  } catch (e) {
                    if (!mounted) return;
                    _showSnackBar('Update failed: $e', isError: true);
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Brand.royalBlueDark, Brand.royalBlueLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Brand.royalBlue.withAlpha(89),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: const Center(
                    child: Text(
                      'Save Changes',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textMuted(isDark), fontSize: 14),
      filled: true,
      fillColor: isDark ? Brand.darkCardElevated : Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _borderColor(isDark)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _borderColor(isDark)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Brand.royalBlue, width: 1.5),
      ),
    );
  }

  // ─── Notification Settings ─────────────────────────────────
  Future<void> _updateNotifSetting(String key, bool value) async {
    // Optimistic update
    if (!mounted) return;
    setState(() {
      switch (key) {
        case 'push_enabled':
          _pushEnabled = value;
          break;
        case 'email_enabled':
          _emailEnabled = value;
          break;
        case 'ticket_updates':
          _ticketUpdates = value;
          break;
        case 'new_messages':
          _newMessages = value;
          break;
        case 'promotions':
          _promotions = value;
          break;
      }
    });

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      await SupabaseConfig.client
          .from('notification_settings')
          .update({key: value}).eq('user_id', userId);
    } catch (e) {
      // Revert on failure
      if (!mounted) return;
      setState(() {
        switch (key) {
          case 'push_enabled':
            _pushEnabled = !value;
            break;
          case 'email_enabled':
            _emailEnabled = !value;
            break;
          case 'ticket_updates':
            _ticketUpdates = !value;
            break;
          case 'new_messages':
            _newMessages = !value;
            break;
          case 'promotions':
            _promotions = !value;
            break;
        }
      });
      _showSnackBar('Failed to update: $e', isError: true);
    }
  }

  // ─── Change Password ──────────────────────────────────────
  void _showChangePassword(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _sheetBg(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _handleColor(isDark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Brand.royalBlue.withAlpha(isDark ? 38 : 26),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.lock_reset_rounded,
                  color: Brand.royalBlue, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Change Password',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textPrimary(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A password reset link will be sent to\n$_email',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSecondary(isDark)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(sheetCtx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: _borderColor(isDark)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _textSecondary(isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        await SupabaseConfig.client.auth
                            .resetPasswordForEmail(
                          _email,
                          redirectTo: 'iconnect://password-reset',
                        );
                        if (!mounted) return;
                        _showSnackBar(
                          'Reset link sent to $_email',
                          icon: Icons.email_rounded,
                        );
                      } catch (e) {
                        if (!mounted) return;
                        _showSnackBar('Failed: $e', isError: true);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Brand.royalBlue,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'Send Link',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ─── Logout ────────────────────────────────────────────────
  Future<void> _handleLogout(bool isDark) async {
    // FIX-8: safe null-aware access instead of force-unwrap
    final t = S.of(context);
    if (t == null || !mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _sheetBg(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _handleColor(isDark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(isDark ? 31 : 20),
                borderRadius: BorderRadius.circular(22),
              ),
              child:
                  const Icon(Icons.logout_rounded, color: Colors.red, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              'Sign Out',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _textPrimary(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to sign out of the admin panel?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _textSecondary(isDark)),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(sheetCtx, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: _borderColor(isDark), width: 1.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: _textSecondary(isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(sheetCtx, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFE53935),
                            Color(0xFFEF5350),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withAlpha(89),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          t.authLogout,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(sheetCtx).padding.bottom + 8),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final ns = NotificationService();
      await ns.unsubscribeFromAllTopics();
      await ns.onLogout();
      await SupabaseConfig.client.auth.signOut();

      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading dialog
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading dialog
      _showSnackBar('Sign out failed: $e', isError: true);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────
  void _showSnackBar(
    String message, {
    bool isError = false,
    IconData? icon,
  }) {
    if (!mounted) return;

    final effectiveIcon =
        icon ?? (isError ? Icons.error_outline_rounded : null);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (effectiveIcon != null) ...[
              Icon(effectiveIcon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade400 : Brand.royalBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showComingSoon(String feature) {
    _showSnackBar('$feature — coming soon!', icon: Icons.construction_rounded);
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _scaffoldBg(isDark),
      body: SafeArea(
        child: _isLoading
            ? _buildSettingsSkeleton(isDark)
            : Column(
                children: [
                  _buildHeader(isDark),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      color: Brand.lightGreen,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 40),
                        children: [
                          _buildProfileCard(isDark),
                          _buildSectionTitle('Appearance', isDark),
                          _buildThemeSelector(isDark),
                          _buildSectionTitle('Language', isDark),
                          _buildLanguageSelector(isDark),
                          _buildSectionTitle('Notifications', isDark),
                          _buildNotificationSettings(isDark),
                          _buildSectionTitle('Account', isDark),
                          _buildAccountSettings(isDark),
                          _buildSectionTitle('Support Contacts', isDark),
                          _buildSupportContactsSection(isDark),
                          _buildSectionTitle('About', isDark),
                          _buildAboutSection(isDark),
                          const SizedBox(height: 24),
                          _buildLogoutButton(isDark),
                          const SizedBox(height: 16),
                          _buildAppVersion(isDark),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ─── SKELETON LOADING ──────────────────────────────────────
  Widget _buildSettingsSkeleton(bool isDark) {
    return Column(
      children: [
        _buildHeader(isDark),
        Expanded(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                height: 240,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [Brand.darkCard, Brand.darkCardElevated]
                        : [Colors.grey.shade200, Colors.grey.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _skeletonCircle(88, isDark),
                    const SizedBox(height: 16),
                    _skeletonBox(140, 18, isDark),
                    const SizedBox(height: 8),
                    _skeletonBox(180, 13, isDark),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _skeletonSectionTitle(isDark),
              _skeletonCard(70, isDark),
              const SizedBox(height: 24),
              _skeletonSectionTitle(isDark),
              _skeletonCard(280, isDark),
              const SizedBox(height: 24),
              _skeletonSectionTitle(isDark),
              _skeletonCard(130, isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _skeletonCircle(double size, bool isDark) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            isDark ? Colors.white.withAlpha(13) : Colors.white.withAlpha(102),
      ),
    );
  }

  Widget _skeletonBox(double width, double height, bool isDark) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withAlpha(13) : Colors.white.withAlpha(128),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }

  Widget _skeletonSectionTitle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        width: 100,
        height: 14,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _skeletonCard(double height, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: height,
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _cardBg(isDark),
                borderRadius: BorderRadius.circular(12),
                border: isDark ? Border.all(color: _borderColor(isDark)) : null,
                boxShadow: _softShadow(isDark),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Brand.royalBlue, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: isDark ? Brand.darkTextPrimary : AdminColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  // ─── SECTION TITLE ─────────────────────────────────────────
  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Brand.royalBlue,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ─── PROFILE CARD ──────────────────────────────────────────
  Widget _buildProfileCard(bool isDark) {
    final initials =
        _fullName.isEmpty ? 'A' : StringUtils.getInitials(_fullName);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Brand.royalBlueDark, Brand.royalBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(89),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showPhotoOptions(isDark),
            child: Stack(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white.withAlpha(77), width: 3),
                    color: Colors.white.withAlpha(38),
                  ),
                  child: _isUploading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : _profilePhotoUrl != null
                          ? ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: _profilePhotoUrl!,
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white.withAlpha(128),
                                    strokeWidth: 2,
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Brand.lightGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _fullName.isNotEmpty ? _fullName : 'Admin',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _email,
            style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(179)),
          ),
          if (_phone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _phone,
              style:
                  TextStyle(fontSize: 12, color: Colors.white.withAlpha(128)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(38),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.white70, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Admin',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _showEditProfile(isDark),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Brand.lightGreen.withAlpha(77),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_rounded,
                          color: Colors.white.withAlpha(230), size: 13),
                      const SizedBox(width: 4),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: Colors.white.withAlpha(230),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── THEME SELECTOR ────────────────────────────────────────
  Widget _buildThemeSelector(bool isDark) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentIsDark = themeProvider.isDarkMode;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: _borderColor(isDark)) : null,
        boxShadow: _cardShadow(isDark),
      ),
      child: Row(
        children: [
          _buildThemeOption(
            icon: Icons.light_mode_rounded,
            label: 'Light',
            isSelected: !currentIsDark,
            isDark: isDark,
            onTap: () {
              HapticFeedback.selectionClick();
              themeProvider.setDarkMode(false);
            },
          ),
          _buildThemeOption(
            icon: Icons.dark_mode_rounded,
            label: 'Dark',
            isSelected: currentIsDark,
            isDark: isDark,
            onTap: () {
              HapticFeedback.selectionClick();
              themeProvider.setDarkMode(true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? Brand.royalBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Brand.royalBlue.withAlpha(77),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? Colors.white : _textMuted(isDark),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : _textSecondary(isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── LANGUAGE SELECTOR ─────────────────────────────────────
  Widget _buildLanguageSelector(bool isDark) {
    // FIX-9: safe null-aware access for localizations
    final t = S.of(context);
    // FIX-10: use localeProvider.locale.languageCode instead of
    //         non-existent currentLanguageCode
    final localeProvider = Provider.of<LocaleProvider>(context);
    final langCode = localeProvider.locale.languageCode;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: _borderColor(isDark)) : null,
        boxShadow: _cardShadow(isDark),
      ),
      child: GestureDetector(
        onTap: () => showLanguageSelector(context),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Brand.royalBlue.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.translate_rounded,
                    color: Brand.royalBlue, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // FIX-11: fallback if t is null
                      t?.settingsLanguage ?? 'Language',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary(isDark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      localeProvider.currentLanguageName,
                      style: TextStyle(
                          fontSize: 12, color: _textSecondary(isDark)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Brand.darkCardElevated
                      : Brand.royalBlue.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      isDark ? Border.all(color: Brand.darkBorderLight) : null,
                ),
                child: Text(
                  // FIX-12: use langCode from locale.languageCode
                  langCode.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: _textMuted(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── NOTIFICATION SETTINGS ─────────────────────────────────
  Widget _buildNotificationSettings(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: _borderColor(isDark)) : null,
        boxShadow: _cardShadow(isDark),
      ),
      child: Column(
        children: [
          _buildToggleTile(
            icon: Icons.notifications_active_rounded,
            color: Brand.royalBlue,
            title: 'Push Notifications',
            subtitle: 'Receive push notifications on this device',
            value: _pushEnabled,
            isDark: isDark,
            onChanged: (v) => _updateNotifSetting('push_enabled', v),
            isFirst: true,
          ),
          _buildTileDivider(isDark),
          _buildToggleTile(
            icon: Icons.email_rounded,
            color: const Color(0xFF3B82F6),
            title: 'Email Notifications',
            subtitle: 'Receive updates via email',
            value: _emailEnabled,
            isDark: isDark,
            onChanged: (v) => _updateNotifSetting('email_enabled', v),
          ),
          _buildTileDivider(isDark),
          _buildToggleTile(
            icon: Icons.confirmation_number_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Ticket Updates',
            subtitle: 'Status changes & new assignments',
            value: _ticketUpdates,
            isDark: isDark,
            onChanged: (v) => _updateNotifSetting('ticket_updates', v),
          ),
          _buildTileDivider(isDark),
          _buildToggleTile(
            icon: Icons.chat_bubble_rounded,
            color: Brand.lightGreen,
            title: 'New Messages',
            subtitle: 'Chat messages from engineers & customers',
            value: _newMessages,
            isDark: isDark,
            onChanged: (v) => _updateNotifSetting('new_messages', v),
          ),
          _buildTileDivider(isDark),
          _buildToggleTile(
            icon: Icons.campaign_rounded,
            color: const Color(0xFF8B5CF6),
            title: 'Promotions',
            subtitle: 'Marketing & promotional content',
            value: _promotions,
            isDark: isDark,
            onChanged: (v) => _updateNotifSetting('promotions', v),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required bool isDark,
    required ValueChanged<bool> onChanged,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 10, 16, isLast ? 16 : 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withAlpha(isDark ? 38 : 26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: _textMuted(isDark)),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Brand.lightGreen,
            inactiveThumbColor: isDark ? Brand.darkTextTertiary : null,
            inactiveTrackColor: isDark ? Brand.darkBorder : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTileDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 68),
      child: Divider(height: 1, color: _dividerColor(isDark)),
    );
  }

  // ─── ACCOUNT SETTINGS ──────────────────────────────────────
  Widget _buildAccountSettings(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: _borderColor(isDark)) : null,
        boxShadow: _cardShadow(isDark),
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.lock_reset_rounded,
            color: Brand.royalBlue,
            title: 'Change Password',
            subtitle: 'Send a password reset link',
            isDark: isDark,
            onTap: () => _showChangePassword(isDark),
            isFirst: true,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(16, isFirst ? 16 : 12, 16, isLast ? 16 : 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withAlpha(isDark ? 38 : 26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: _textMuted(isDark)),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: _textMuted(isDark)),
          ],
        ),
      ),
    );
  }

  // ─── SUPPORT CONTACTS SECTION ───────────────────────────────
  Widget _buildSupportContactsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: _borderColor(isDark)) : null,
        boxShadow: _cardShadow(isDark),
      ),
      child: Column(
        children: [
          if (_supportContacts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.contact_phone_outlined,
                      size: 36,
                      color: isDark
                          ? Brand.darkTextTertiary
                          : Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'No support contacts yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: _textSecondary(isDark),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._supportContacts.asMap().entries.map((entry) {
              final i = entry.key;
              final c = entry.value;
              final type = c['contact_type'] as String? ?? 'call';
              final label = c['label'] as String? ?? '';
              final value = c['value'] as String? ?? '';
              final isActive = c['is_active'] as bool? ?? true;

              IconData icon;
              Color color;
              switch (type) {
                case 'call':
                  icon = Icons.phone_rounded;
                  color = const Color(0xFF4CAF50);
                  break;
                case 'whatsapp':
                  icon = Icons.chat_rounded;
                  color = const Color(0xFF25D366);
                  break;
                case 'email':
                  icon = Icons.email_rounded;
                  color = const Color(0xFFE91E63);
                  break;
                case 'web':
                  icon = Icons.public_rounded;
                  color = Brand.royalBlue;
                  break;
                default:
                  icon = Icons.contact_page;
                  color = Colors.grey;
              }

              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withAlpha(isDark ? 30 : 20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    title: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary(isDark),
                      ),
                    ),
                    subtitle: Text(
                      value,
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary(isDark),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('INACTIVE',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: Colors.orange)),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.edit_rounded,
                              size: 18, color: _textMuted(isDark)),
                          onPressed: () => _editContact(c),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18, color: Color(0xFFEF4444)),
                          onPressed: () => _deleteContact(c),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                  if (i < _supportContacts.length - 1)
                    _buildTileDivider(isDark),
                ],
              );
            }),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: () => _editContact(null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Contact',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Brand.royalBlue,
                  side: BorderSide(color: Brand.royalBlue.withAlpha(100)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editContact(Map<String, dynamic>? existing) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNew = existing == null;
    final labelCtrl =
        TextEditingController(text: existing?['label'] as String? ?? '');
    final valueCtrl =
        TextEditingController(text: existing?['value'] as String? ?? '');
    String type = existing?['contact_type'] as String? ?? 'call';
    bool isActive = existing?['is_active'] as bool? ?? true;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSS) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: _sheetBg(isDark),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _handleColor(isDark),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isNew ? 'Add Support Contact' : 'Edit Support Contact',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Type selector
                  Text('Contact Type',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textSecondary(isDark))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _contactTypeChip('call', 'Call', Icons.phone_rounded,
                          const Color(0xFF4CAF50), type, isDark, (v) {
                        setSS(() => type = v);
                      }),
                      _contactTypeChip(
                          'whatsapp',
                          'WhatsApp',
                          Icons.chat_rounded,
                          const Color(0xFF25D366),
                          type,
                          isDark, (v) {
                        setSS(() => type = v);
                      }),
                      _contactTypeChip('email', 'Email', Icons.email_rounded,
                          const Color(0xFFE91E63), type, isDark, (v) {
                        setSS(() => type = v);
                      }),
                      _contactTypeChip('web', 'Web', Icons.public_rounded,
                          Brand.royalBlue, type, isDark, (v) {
                        setSS(() => type = v);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Label
                  Text('Label',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textSecondary(isDark))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: labelCtrl,
                    style: TextStyle(color: _textPrimary(isDark)),
                    decoration: InputDecoration(
                      hintText: 'e.g. Main Office, Support',
                      hintStyle: TextStyle(color: _textMuted(isDark)),
                      filled: true,
                      fillColor: isDark
                          ? Brand.darkCardElevated
                          : Brand.scaffoldLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Value
                  Text(
                      type == 'call'
                          ? 'Phone Number'
                          : type == 'whatsapp'
                              ? 'WhatsApp Number (with country code)'
                              : type == 'email'
                                  ? 'Email Address'
                                  : 'URL',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textSecondary(isDark))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: valueCtrl,
                    style: TextStyle(color: _textPrimary(isDark)),
                    keyboardType: type == 'email'
                        ? TextInputType.emailAddress
                        : type == 'web'
                            ? TextInputType.url
                            : TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: type == 'call'
                          ? '0777123456'
                          : type == 'whatsapp'
                              ? '94777123456'
                              : type == 'email'
                                  ? 'support@example.com'
                                  : 'https://example.com',
                      hintStyle: TextStyle(color: _textMuted(isDark)),
                      filled: true,
                      fillColor: isDark
                          ? Brand.darkCardElevated
                          : Brand.scaffoldLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Active toggle
                  Row(
                    children: [
                      Expanded(
                        child: Text('Active (visible to customers)',
                            style: TextStyle(
                                fontSize: 13, color: _textPrimary(isDark))),
                      ),
                      Switch(
                        value: isActive,
                        onChanged: (v) => setSS(() => isActive = v),
                        activeThumbColor: Brand.lightGreen,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () {
                        if (labelCtrl.text.trim().isEmpty ||
                            valueCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            const SnackBar(
                              content: Text('Label and value are required'),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(sheetCtx, true);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Brand.royalBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(isNew ? 'Add Contact' : 'Save Changes',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result != true) {
      labelCtrl.dispose();
      valueCtrl.dispose();
      return;
    }

    try {
      final data = {
        'contact_type': type,
        'label': labelCtrl.text.trim(),
        'value': valueCtrl.text.trim(),
        'is_active': isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (isNew) {
        data['display_order'] = _supportContacts.length + 1;
        await SupabaseConfig.client.from('support_contacts').insert(data);
      } else {
        await SupabaseConfig.client
            .from('support_contacts')
            .update(data)
            .eq('id', existing['id']);
      }

      _showSnackBar(isNew ? 'Contact added' : 'Contact updated');
      _loadSupportContacts();
    } catch (e) {
      _showSnackBar('Failed: $e', isError: true);
    }

    labelCtrl.dispose();
    valueCtrl.dispose();
  }

  Widget _contactTypeChip(String value, String label, IconData icon,
      Color color, String selected, bool isDark, ValueChanged<String> onTap) {
    final isSel = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? color.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? color : _borderColor(isDark),
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSel ? color : _textMuted(isDark)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                  color: isSel ? color : _textSecondary(isDark),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteContact(Map<String, dynamic> contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text(
            'Remove "${contact['label']}" from support contacts?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await SupabaseConfig.client
          .from('support_contacts')
          .delete()
          .eq('id', contact['id']);
      _showSnackBar('Contact deleted');
      _loadSupportContacts();
    } catch (e) {
      _showSnackBar('Failed: $e', isError: true);
    }
  }

  // ─── ABOUT SECTION ─────────────────────────────────────────
  Widget _buildAboutSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: _borderColor(isDark)) : null,
        boxShadow: _cardShadow(isDark),
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.help_outline_rounded,
            color: const Color(0xFF3B82F6),
            title: 'Help & Support',
            subtitle: 'Get help with iFrontiers Connect',
            isDark: isDark,
            onTap: () => _showComingSoon('Help & Support'),
            isFirst: true,
          ),
          _buildTileDivider(isDark),
          _buildSettingsTile(
            icon: Icons.privacy_tip_outlined,
            color: const Color(0xFF8B5CF6),
            title: 'Privacy Policy',
            subtitle: 'View our privacy policy',
            isDark: isDark,
            onTap: () => _showComingSoon('Privacy Policy'),
          ),
          _buildTileDivider(isDark),
          _buildSettingsTile(
            icon: Icons.description_outlined,
            color: const Color(0xFFF59E0B),
            title: 'Terms of Service',
            subtitle: 'View terms and conditions',
            isDark: isDark,
            onTap: () => _showComingSoon('Terms of Service'),
            isLast: true,
          ),
        ],
      ),
    );
  }

  // ─── LOGOUT BUTTON ─────────────────────────────────────────
  Widget _buildLogoutButton(bool isDark) {
    // FIX-13: safe null-aware access — no force unwrap
    final t = S.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => _handleLogout(isDark),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(isDark ? 26 : 15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withAlpha(38), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 20),
              const SizedBox(width: 10),
              Text(
                // FIX-14: null-safe fallback for localization
                t?.authLogout ?? 'Sign Out',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── APP VERSION ───────────────────────────────────────────
  Widget _buildAppVersion(bool isDark) {
    return Column(
      children: [
        Text(
          'iFrontiers Connect',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textMuted(isDark),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Version 1.0.0',
          style: TextStyle(fontSize: 12, color: _textMuted(isDark)),
        ),
        const SizedBox(height: 2),
        Text(
          '© ${DateTime.now().year} iFrontiers (Pvt) Ltd',
          style: TextStyle(fontSize: 12, color: _textMuted(isDark)),
        ),
      ],
    );
  }
}
