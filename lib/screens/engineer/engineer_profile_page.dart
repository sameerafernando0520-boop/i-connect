// lib/screens/engineer/engineer_profile_page.dart

import 'package:i_connect/l10n/s.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../services/notification_service.dart';
import '../../utils/string_utils.dart';
import '../../utils/upload_validator.dart';
import '../../utils/time_utils.dart';
import '../auth/login_page.dart';

import '../../widgets/common/language_selector_sheet.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/common/theme_style_sheet.dart';

// ── Engineer accent (per handoff §26 — NOT in Brand class) ──
const Color _engAccent = Color(0xFF00B4D8);
const Color _engAccentDark = Color(0xFF0096B7);

// All specializations an engineer can have
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

class EngineerProfilePage extends StatefulWidget {
  const EngineerProfilePage({super.key});

  @override
  State<EngineerProfilePage> createState() => _EngineerProfilePageState();
}

class _EngineerProfilePageState extends State<EngineerProfilePage> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isUploadingImage = false;

  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _stats = {};

  // Edit controllers
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  List<String> _selectedSpecs = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _bioCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // ═══════════════════════════════════════════════════════════
  //  DATA
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) return;

      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('users')
            .select(
              'full_name, email, phone_number, company_name, profile_photo, '
              'engineer_bio, specializations, availability_status, '
              'avg_rating, total_resolved, created_at, city, address',
            )
            .eq('id', uid)
            .single(),
        SupabaseConfig.client
            .from('service_tickets')
            .select(
              'id, status, priority, closed_at, customer_rating, ticket_type',
            )
            .eq('assigned_to', uid)
            .eq('is_deleted', false),
      ]);

      if (!mounted) return;

      final profileRes = results[0] as Map<String, dynamic>;
      final ticketRes = results[1] as List;
      final tickets =
          ticketRes.map((t) => Map<String, dynamic>.from(t as Map)).toList();

      // Build stats
      int total = tickets.length, resolved = 0, open = 0, urgent = 0;
      double rSum = 0;
      int rCount = 0;
      for (final t in tickets) {
        final s = t['status'] as String? ?? '';
        final r = t['customer_rating'];
        if (['resolved', 'closed'].contains(s)) resolved++;
        if (['open', 'assigned', 'in_progress'].contains(s)) open++;
        if (t['priority'] == 'urgent') urgent++;
        if (r != null) {
          rSum += (r as num).toDouble();
          rCount++;
        }
      }
      final avgRating = rCount > 0 ? rSum / rCount : 0.0;

      setState(() {
        _profile = Map<String, dynamic>.from(profileRes);
        _stats = {
          'total_assigned': total,
          'resolved': resolved,
          'open': open,
          'urgent_total': urgent,
          'avg_rating': double.parse(avgRating.toStringAsFixed(1)),
          'rated_count': rCount,
        };
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Engineer profile load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _enterEditMode() {
    _nameCtrl.text = _profile['full_name'] as String? ?? '';
    _phoneCtrl.text = _profile['phone_number'] as String? ?? '';
    _companyCtrl.text = _profile['company_name'] as String? ?? '';
    _bioCtrl.text = _profile['engineer_bio'] as String? ?? '';
    _cityCtrl.text = _profile['city'] as String? ?? '';
    _addressCtrl.text = _profile['address'] as String? ?? '';
    _selectedSpecs = List<String>.from(
      (_profile['specializations'] as List?)?.cast<String>() ?? [],
    );
    setState(() => _isEditing = true);
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnackBar('Name cannot be empty', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) return;

      await SupabaseConfig.client.from('users').update({
        'full_name': _nameCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'company_name': _companyCtrl.text.trim(),
        'engineer_bio': _bioCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'specializations': _selectedSpecs,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);

      if (!mounted) return;

      await _loadProfile();
      if (!mounted) return;

      setState(() => _isEditing = false);
      _showSnackBar(
        'Profile updated successfully!',
        icon: Icons.check_circle_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  STORAGE HELPERS
  // ═══════════════════════════════════════════════════════════

  String? _extractStoragePath(String? url) {
    if (url == null || url.isEmpty) return null;

    // Extract storage path from Supabase URL
    // Expected format: https://{project}.supabase.co/storage/v1/object/public/profile-photos/{path}
    // or (for signed URLs): https://{project}.supabase.co/storage/v1/object/authenticated/profile-photos/{path}
    const marker = '/profile-photos/';
    final idx = url.indexOf(marker);
    if (idx == -1) {
      AppLogger.warn('ProfilePage', 'Storage URL format unexpected — path extraction skipped: $url');
      return null;
    }
    return url.substring(idx + marker.length);
  }

  Future<void> _deleteStorageFile(String? url) async {
    final path = _extractStoragePath(url);
    if (path == null) return;
    try {
      await SupabaseConfig.client.storage.from('profile-photos').remove([path]);
    } catch (e) {
      debugPrint('⚠️ Storage cleanup failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  PROFILE PHOTO
  // ═══════════════════════════════════════════════════════════

  void _showPhotoOptions() {
    final isDark = _isDark;
    final photo = _profile['profile_photo'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(Brand.r(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Profile Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 20),
            _buildPhotoOption(
              Icons.camera_alt_rounded,
              'Take Photo',
              _engAccent,
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
            if (photo != null && photo.isNotEmpty)
              _buildPhotoOption(
                Icons.delete_outline_rounded,
                'Remove Photo',
                StatusColors.danger,
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
          color: color.withAlpha(((isDark ? 0.1 : 0.06) * 255).toInt()),
          borderRadius: BorderRadius.circular(Brand.r(14)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(((0.1) * 255).toInt()),
                borderRadius: BorderRadius.circular(Brand.r(12)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
            ),
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

      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      setState(() => _isUploadingImage = true);

      final bytes = await File(picked.path).readAsBytes();
      if (!mounted) return;

      // Validate before touching storage
      final validation = UploadValidator.validate(
        bytes: bytes,
        filename: picked.path.split('/').last,
        category: UploadCategory.profilePhoto,
      );
      if (!validation.ok) {
        setState(() => _isUploadingImage = false);
        _showSnackBar(validation.error!, isError: true);
        return;
      }

      final ext = picked.path.split('.').last;
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      // Delete old photo from storage before uploading new one
      final oldUrl = _profile['profile_photo'] as String?;
      await _deleteStorageFile(oldUrl);
      if (!mounted) return;

      await SupabaseConfig.client.storage.from('profile-photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      if (!mounted) return;

      final publicUrl = SupabaseConfig.client.storage
          .from('profile-photos')
          .getPublicUrl(path);

      await SupabaseConfig.client.from('users').update({
        'profile_photo': publicUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      if (!mounted) return;
      setState(() {
        _profile = {..._profile, 'profile_photo': publicUrl};
        _isUploadingImage = false;
      });
      _showSnackBar(
        'Profile photo updated',
        icon: Icons.check_circle_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingImage = false);
      _showSnackBar('Upload failed: $e', isError: true);
    }
  }

  Future<void> _removePhoto() async {
    final oldUrl = _profile['profile_photo'] as String?;
    if (oldUrl == null || oldUrl.isEmpty) return;

    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isUploadingImage = true);
    try {
      await _deleteStorageFile(oldUrl);
      if (!mounted) return;

      await SupabaseConfig.client.from('users').update({
        'profile_photo': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      if (!mounted) return;
      setState(() {
        _profile = {..._profile, 'profile_photo': null};
        _isUploadingImage = false;
      });
      _showSnackBar('Photo removed', icon: Icons.check_circle_rounded);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingImage = false);
      _showSnackBar('Failed to remove photo: $e', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  LOGOUT
  // ═══════════════════════════════════════════════════════════

  Future<void> _logout() async {
    final isDark = _isDark;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkBorderLight : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(Brand.r(2)),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: StatusColors.danger.withAlpha(20),
                borderRadius: BorderRadius.circular(Brand.r(22)),
              ),
              child: Icon(
                Icons.logout_rounded,
                color: StatusColors.danger,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Sign Out',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to sign out?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
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
                        border: Border.all(
                          color: isDark
                              ? Brand.darkBorderLight
                              : Brand.borderLight,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
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
                          colors: [Color(0xFFE53935), Color(0xFFEF5350)],
                        ),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        boxShadow: [
                          BoxShadow(
                            color: StatusColors.danger.withAlpha(89),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'Sign Out',
                          style: TextStyle(
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

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final ns = NotificationService();
      await ns.onLogout();
      if (!mounted) return;

      await SupabaseConfig.client.auth.signOut();
      if (!mounted) return;

      Navigator.of(context).pop(); // dismiss loading
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      // Ensure spinner is dismissed even if signOut throws
      try {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      } catch (_) {
        // Ignore navigation errors during cleanup
      }

      if (!mounted) return;
      _showSnackBar('Sign out failed: $e', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════

  Color _availColor(String s) {
    switch (s) {
      case 'available':
        return Brand.lightGreenBright;
      case 'busy':
        return const Color(0xFFFFB74D);
      default:
        return Brand.darkTextSecondary;
    }
  }

  void _showSnackBar(String message, {bool isError = false, IconData? icon}) {
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
        backgroundColor: isError ? StatusColors.danger : _engAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;

    // ── Locale / i18n ──────────────────────────────────────
    final t = S.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context);
    // ───────────────────────────────────────────────────────

    return SafeArea(
      child: _isLoading
          ? _skeleton(isDark)
          : _isEditing
              ? _buildEditView(isDark)
              : _buildViewMode(isDark, t, localeProvider),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  VIEW MODE
  // ═══════════════════════════════════════════════════════════

  Widget _buildViewMode(
    bool isDark,
    S t,
    LocaleProvider localeProvider,
  ) {
    final name = _profile['full_name'] as String? ?? '';
    final email = _profile['email'] as String? ?? '';
    final phone = _profile['phone_number'] as String? ?? '';
    final photo = _profile['profile_photo'] as String?;
    final bio = _profile['engineer_bio'] as String?;
    final avail = _profile['availability_status'] as String? ?? 'available';
    final specs = (_profile['specializations'] as List?)?.cast<String>() ?? [];
    final city = _profile['city'] as String?;
    final address = _profile['address'] as String?;
    final avgRat = _stats['avg_rating'] as double? ?? 0.0;
    final total = _stats['total_assigned'] as int? ?? 0;
    final resolved = _stats['resolved'] as int? ?? 0;
    final ratedCount = _stats['rated_count'] as int? ?? 0;
    final memberSince =
        DateTime.tryParse(_profile['created_at'] as String? ?? '');

    return RefreshIndicator(
      color: isDark ? Brand.darkIconActive : _engAccent,
      backgroundColor: Brand.surface(isDark),
      onRefresh: _loadProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Column(
          children: [
            _buildViewHeader(isDark),
            _buildProfileHero(
              name,
              email,
              phone,
              photo,
              avail,
              avgRat,
              total,
              resolved,
              isDark,
            ),
            if (bio != null && bio.isNotEmpty) _buildBioCard(bio, isDark),
            _buildSpecializationsCard(specs, isDark),
            _buildPerformanceCard(total, resolved, avgRat, ratedCount, isDark),
            _buildInfoCard(email, phone, city, address, memberSince, isDark),
            // ── Settings card (language selector + future prefs) ──
            _buildSettingsCard(isDark, t, localeProvider),
            _buildLogoutButton(isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildViewHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [Brand.darkIconActive, Brand.royalBlueGlow]
                    : [_engAccent, _engAccentDark],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(Brand.r(2)),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'My Profile',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _enterEditMode,
              borderRadius: BorderRadius.circular(Brand.r(12)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (isDark ? Brand.darkIconActive : _engAccent)
                      .withAlpha(((isDark ? 0.12 : 0.06) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                  border: Border.all(
                    color: (isDark ? Brand.darkIconActive : _engAccent)
                        .withAlpha(((0.25) * 255).toInt()),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_rounded,
                      size: 15,
                      color: isDark ? Brand.darkIconActive : _engAccent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Brand.darkIconActive : _engAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHero(
    String name,
    String email,
    String phone,
    String? photo,
    String avail,
    double rating,
    int total,
    int resolved,
    bool isDark,
  ) {
    final initialsText = Text(
      StringUtils.getInitials(name),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w600,
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.r(26)),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF052E16), const Color(0xFF14532D)]
              : [const Color(0xFF14532D), const Color(0xFF16A34A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: const Color(0xFF16A34A).withAlpha(89),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
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
                color: Colors.white.withAlpha(((isDark ? 0.015 : 0.04) * 255).toInt()),
              ),
            ),
          ),
          Positioned(
            right: 25,
            bottom: -25,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(((isDark ? 0.01 : 0.025) * 255).toInt()),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Avatar + availability + camera button
                GestureDetector(
                  onTap: _isUploadingImage ? null : _showPhotoOptions,
                  child: Stack(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_engAccent, _engAccentDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _engAccent.withAlpha(((0.4) * 255).toInt()),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _isUploadingImage
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : (photo != null && photo.isNotEmpty)
                                  ? CachedNetworkImage(
                                      imageUrl: photo,
                                      width: 88,
                                      height: 88,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) =>
                                          Center(child: initialsText),
                                      errorWidget: (_, __, ___) =>
                                          Center(child: initialsText),
                                    )
                                  : Center(child: initialsText),
                        ),
                      ),
                      // Availability dot
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _availColor(avail),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Brand.surface(isDark),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _availColor(avail).withAlpha(((0.4) * 255).toInt()),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Camera icon
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Brand.lightGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  isDark ? Brand.darkCard : Brand.royalBlueDark,
                              width: 2.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: TextStyle(
                    color: isDark ? Brand.darkTextPrimary : Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.email_outlined,
                      color: isDark
                          ? Brand.darkTextSecondary
                          : Colors.white.withAlpha(((0.55) * 255).toInt()),
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        email,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Colors.white.withAlpha(((0.7) * 255).toInt()),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _heroStatCol('$total', 'Assigned', isDark),
                    _statDivider(isDark),
                    _heroStatCol('$resolved', 'Resolved', isDark),
                    _statDivider(isDark),
                    _heroStatCol(
                      rating > 0 ? rating.toStringAsFixed(1) : '—',
                      'Rating',
                      isDark,
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

  Widget _heroStatCol(String val, String label, bool isDark) => Column(
        children: [
          Text(
            val,
            style: TextStyle(
              color: isDark ? Brand.darkTextPrimary : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? Brand.darkTextSecondary
                  : Colors.white.withAlpha(((0.5) * 255).toInt()),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );

  Widget _statDivider(bool isDark) => Container(
        width: 1,
        height: 36,
        color: isDark ? Brand.darkBorderLight : Colors.white.withAlpha(((0.15) * 255).toInt()),
      );

  Widget _buildBioCard(String bio, bool isDark) {
    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('About Me', Icons.person_pin_rounded, isDark),
          const SizedBox(height: 12),
          Text(
            bio,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecializationsCard(List<String> specs, bool isDark) {
    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Specializations', Icons.engineering_rounded, isDark),
          const SizedBox(height: 14),
          if (specs.isEmpty)
            Text(
              'No specializations added yet',
              style: TextStyle(
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontSize: 13,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: specs
                  .map(
                    (s) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _engAccent.withAlpha(((isDark ? 0.12 : 0.1) * 255).toInt()),
                        borderRadius: BorderRadius.circular(Brand.r(20)),
                        border: Border.all(
                          color: _engAccent.withAlpha(((0.3) * 255).toInt()),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: _engAccent,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            s,
                            style: const TextStyle(
                              color: _engAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard(
    int total,
    int resolved,
    double rating,
    int rCount,
    bool isDark,
  ) {
    final open = _stats['open'] as int? ?? 0;
    final resRate = total > 0 ? (resolved / total * 100).toInt() : 0;

    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Performance', Icons.bar_chart_rounded, isDark),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _perfStat(
                  'Total',
                  '$total',
                  Icons.inbox_rounded,
                  Brand.darkIconActive,
                  isDark,
                ),
              ),
              Expanded(
                child: _perfStat(
                  'Resolved',
                  '$resolved',
                  Icons.check_circle_rounded,
                  Brand.lightGreenBright,
                  isDark,
                ),
              ),
              Expanded(
                child: _perfStat(
                  'Open',
                  '$open',
                  Icons.pending_actions_rounded,
                  const Color(0xFFFFB74D),
                  isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Resolution rate bar
          Row(
            children: [
              Text(
                'Resolution rate',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
              const Spacer(),
              Text(
                '$resRate%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Brand.lightGreenBright,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: isDark
                  ? Brand.darkBorderLight.withAlpha(((0.4) * 255).toInt())
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: FractionallySizedBox(
              widthFactor: (resRate / 100.0).clamp(0.0, 1.0),
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Brand.lightGreen, Brand.lightGreenBright],
                  ),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                  boxShadow: [
                    BoxShadow(
                      color: Brand.lightGreen.withAlpha(((0.4) * 255).toInt()),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (rating > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Average rating',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
                const Spacer(),
                ...List.generate(
                  5,
                  (i) => Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      i < rating.round()
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '($rCount)',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _perfStat(
    String label,
    String val,
    IconData icon,
    Color c,
    bool isDark,
  ) =>
      Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.withAlpha(((isDark ? 0.12 : 0.1) * 255).toInt()),
              borderRadius: BorderRadius.circular(Brand.r(13)),
            ),
            child: Icon(icon, color: c, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            val,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ],
      );

  Widget _buildInfoCard(
    String email,
    String phone,
    String? city,
    String? address,
    DateTime? memberSince,
    bool isDark,
  ) {
    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Contact & Info', Icons.contact_page_rounded, isDark),
          const SizedBox(height: 14),
          _infoRow(Icons.email_outlined, 'Email', email, isDark,
              onTap: email.isNotEmpty
                  ? () => _launchContact('mailto:$email')
                  : null),
          const SizedBox(height: 10),
          _infoRow(Icons.phone_rounded, 'Phone', phone, isDark,
              onTap: phone.isNotEmpty
                  ? () => _launchContact('tel:$phone')
                  : null),
          if (city != null && city.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoRow(
              Icons.location_city_rounded,
              'City',
              city,
              isDark,
            ),
          ],
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoRow(
              Icons.location_on_outlined,
              'Address',
              address,
              isDark,
            ),
          ],
          if (memberSince != null) ...[
            const SizedBox(height: 10),
            _infoRow(
              Icons.calendar_today_rounded,
              'Member Since',
              TimeUtils.formatMonthYear(memberSince),
              isDark,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _launchContact(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Widget _infoRow(IconData icon, String label, String val, bool isDark,
          {VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isDark ? Brand.darkIconActive : _engAccent)
                  .withAlpha(((isDark ? 0.1 : 0.08) * 255).toInt()),
              borderRadius: BorderRadius.circular(Brand.r(12)),
            ),
            child: Icon(
              icon,
              color: isDark ? Brand.darkIconActive : _engAccent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        val.isEmpty ? '—' : val,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                    ),
                    if (onTap != null && val.isNotEmpty)
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 12,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : Brand.subtleLight,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      );

  // ─────────────────────────────────────────────────────────
  //  SETTINGS CARD  (language selector + future prefs)
  // ─────────────────────────────────────────────────────────

  Widget _buildSettingsCard(
    bool isDark,
    S t,
    LocaleProvider localeProvider,
  ) {
    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Preferences', Icons.tune_rounded, isDark),
          const SizedBox(height: 8),
          // ── Language selector tile ─────────────────────────
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showLanguageSelector(context),
              borderRadius: BorderRadius.circular(Brand.r(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    // Leading icon container
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _engAccent.withAlpha(26),
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                      ),
                      child: Icon(
                        Icons.translate_rounded,
                        color: _engAccent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title + subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.settingsLanguage,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            localeProvider.currentLanguageName,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Trailing chevron
                    Icon(
                      Icons.chevron_right_rounded,
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // ── Dark mode toggle + style picker ─────────────────
          Consumer<ThemeProvider>(
            builder: (ctx, tp, _) => Column(children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _engAccent.withAlpha(26),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: Icon(
                    tp.isDarkMode
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: _engAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Dark Mode',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : const Color(0xFF1E293B),
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: tp.isDarkMode,
                  onChanged: (_) => tp.toggleTheme(),
                  activeThumbColor: _engAccent,
                ),
              ]),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => ThemeStyleSheet.show(context),
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _engAccent.withAlpha(26),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                        ),
                        child: Icon(
                          Icons.style_rounded,
                          color: _engAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Dark style',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Brand.darkTextPrimary
                                : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      Text(
                        ThemeProvider.styleName(tp.darkStyle),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : Brand.subtleLight,
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────

  Widget _buildLogoutButton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _logout,
          borderRadius: BorderRadius.circular(Brand.r(18)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? StatusColors.danger.withAlpha(20) : StatusColors.danger.withAlpha(20),
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: Border.all(color: StatusColors.danger.withAlpha(51)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.logout_rounded,
                  color: StatusColors.danger,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'Sign Out',
                  style: TextStyle(
                    color: StatusColors.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  EDIT MODE
  // ═══════════════════════════════════════════════════════════

  Widget _buildEditView(bool isDark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        children: [
          // Edit header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () => setState(() => _isEditing = false),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Brand.surface(isDark),
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                      border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isSaving ? null : _saveProfile,
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_engAccent, _engAccentDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        boxShadow: [
                          BoxShadow(
                            color: _engAccent.withAlpha(((0.35) * 255).toInt()),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Basic info fields
          _editCard(
            isDark: isDark,
            title: 'Basic Information',
            icon: Icons.person_rounded,
            child: Column(
              children: [
                _editField(
                  'Full Name',
                  _nameCtrl,
                  Icons.person_outline_rounded,
                  isDark,
                ),
                const SizedBox(height: 14),
                _editField(
                  'Phone Number',
                  _phoneCtrl,
                  Icons.phone_outlined,
                  isDark,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                _editField(
                  'Company',
                  _companyCtrl,
                  Icons.business_outlined,
                  isDark,
                ),
                const SizedBox(height: 14),
                _editField(
                  'City',
                  _cityCtrl,
                  Icons.location_city_rounded,
                  isDark,
                ),
                const SizedBox(height: 14),
                _editField(
                  'Address',
                  _addressCtrl,
                  Icons.location_on_outlined,
                  isDark,
                  maxLines: 2,
                ),
              ],
            ),
          ),

          // Bio
          _editCard(
            isDark: isDark,
            title: 'About Me',
            icon: Icons.person_pin_rounded,
            child: TextField(
              controller: _bioCtrl,
              maxLines: 4,
              style: TextStyle(
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText:
                    'Write a short bio about yourself, your experience, expertise...',
                hintStyle: TextStyle(
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  fontSize: 13,
                ),
                filled: true,
                fillColor:
                    isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  borderSide: BorderSide(
                    color: isDark ? Brand.darkBorder : Brand.borderLight,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  borderSide: BorderSide(
                    color: isDark ? Brand.darkBorder : Brand.borderLight,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                  borderSide: const BorderSide(color: _engAccent, width: 2),
                ),
              ),
            ),
          ),

          // Specializations
          _editCard(
            isDark: isDark,
            title: 'Specializations',
            icon: Icons.engineering_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select all that apply',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
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
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? _engAccent.withAlpha(((isDark ? 0.15 : 0.12) * 255).toInt())
                              : (isDark
                                  ? Brand.darkCardElevated
                                  : Brand.royalBlueSurface),
                          borderRadius: BorderRadius.circular(Brand.r(20)),
                          border: Border.all(
                            color: isSel
                                ? _engAccent.withAlpha(((0.5) * 255).toInt())
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
                              const Icon(
                                Icons.check_rounded,
                                color: _engAccent,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              s,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isSel
                                    ? _engAccent
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
        ],
      ),
    );
  }

  Widget _editField(
    String label,
    TextEditingController ctrl,
    IconData icon,
    bool isDark, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(
        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        ),
        prefixIcon: Icon(
          icon,
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
          size: 20,
        ),
        filled: true,
        fillColor: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(14)),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(14)),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(14)),
          borderSide: const BorderSide(color: _engAccent, width: 2),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════

  Widget _card({required bool isDark, required Widget child}) => Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(22)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: child,
      );

  Widget _editCard({
    required bool isDark,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(22)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(title, icon, isDark),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _cardTitle(String title, IconData icon, bool isDark) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _engAccent.withAlpha(((isDark ? 0.12 : 0.1) * 255).toInt()),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: Icon(icon, color: _engAccent, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
        ],
      );

  Widget _skeleton(bool isDark) {
    Widget sk(double w, double h, double r) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkBorderLight.withAlpha(((0.3) * 255).toInt())
                : Brand.royalBlue.withAlpha(((0.05) * 255).toInt()),
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [sk(100, 24, 8), const Spacer(), sk(70, 34, 12)],
          ),
          const SizedBox(height: 20),
          sk(double.infinity, 260, 26),
          const SizedBox(height: 16),
          sk(double.infinity, 90, 22),
          const SizedBox(height: 16),
          sk(double.infinity, 120, 22),
          const SizedBox(height: 16),
          sk(double.infinity, 200, 22),
          const SizedBox(height: 16),
          sk(double.infinity, 180, 22),
        ],
      ),
    );
  }
}
