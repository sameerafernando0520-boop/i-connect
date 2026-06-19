// lib/screens/customer/profile_page.dart

import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:url_launcher/url_launcher.dart';
import 'package:i_connect/l10n/s.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/notification_service.dart';
import '../../services/points_service.dart';
import '../../utils/string_utils.dart';
import '../../utils/upload_validator.dart';
import '../../utils/sri_lanka_locations.dart';
import '../../widgets/common/ic_icons.dart';
import '../../widgets/common/app_logo.dart';
import '../../widgets/common/language_selector_sheet.dart';
import '../../widgets/customer/customer_nav_bar.dart';
import '../../widgets/customer/customer_nav_controller.dart';
import '../auth/login_page.dart';
import 'catalog_page.dart';
import 'notification_list_page.dart';
import 'my_invoices_page.dart';
import 'my_quotations_page.dart';
import 'customer_installments_page.dart';
import '../../widgets/common/theme_style_sheet.dart';
import '../../widgets/ds/ds_widgets.dart';

class ProfilePage extends StatefulWidget {
  final bool showNavBar;
  const ProfilePage({super.key, this.showNavBar = true});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isUploadingImage = false;
  bool _isSaving = false;
  bool _hasError = false;
  bool _accountInfoExpanded = false;

  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // ── Sri Lanka location selection ────────────────────────────
  // Province/district are dropdowns; selecting a province filters the
  // district options below it. Null = not selected yet (user can also
  // clear via the dropdown's null sentinel).
  String? _province;
  String? _district;

  String _userId = '';
  String? _profileImageUrl;
  DateTime? _createdAt;

  int _totalTickets = 0;
  int _totalMachines = 0;
  int _openTickets = 0;
  int _resolvedTickets = 0;

  int _unreadNotifications = 0;

  int _progressPercentage = 0;
  bool _milestone25 = false;
  bool _milestone50 = false;
  bool _milestone75 = false;
  bool _milestone100 = false;

  int _profileCompletePercent = 0;
  int _profileCompletedFields = 0;
  int _profileTotalFields = 0;
  String _nextProfileAction = '';

  Map<String, String> _originalValues = {};

  // ── Support Contacts (loaded from DB) ──
  List<Map<String, dynamic>> _supportContacts = [];

  // ── Tier System (real DB-backed — matches home_page) ──
  Map<String, dynamic> _tierData = {};

  // ── Tier Computed Getters ──
  String get _currentTier =>
      (_tierData['tier'] as Map?)?['current'] as String? ?? 'bronze';
  int get _totalPoints =>
      ((_tierData['tier'] as Map?)?['total_points'] as num?)?.toInt() ?? 0;

  int get _nextTierThreshold =>
      ((_tierData['tier'] as Map?)?['next_threshold'] as num?)?.toInt() ?? 500;
  int get _loginStreak =>
      ((_tierData['tier'] as Map?)?['login_streak'] as num?)?.toInt() ?? 0;

  late AnimationController _animController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _loadProfile();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ── Dark mode helper ────────────────────────────────────────
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // ── Navigation helper (reload stats on return) ──────────────
  Future<void> _navigateTo(Widget page, {bool reload = true}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    if (reload) _loadProfile();
  }

  // ═══════════════════════════════════════════════════════════
  //  DATA LOADING
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadProfile() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');
      _userId = user.id;

      final profileData = await _loadProfileFallback(user.id);

      if (!mounted) return;

      try {
        _parseProfileData(profileData);
      } catch (parseError) {
        debugPrint('⚠️ Profile parse error (non-fatal): $parseError');
      }

      _progressAnimation =
          Tween<double>(begin: 0, end: _progressPercentage / 100).animate(
              CurvedAnimation(
                  parent: _animController, curve: Curves.easeOutCubic));

      setState(() {
        _isLoading = false;
        _hasError = false;
      });

      _animController.forward(from: 0);

      // Fetch tier info separately (non-blocking, non-critical)
      _fetchTierInfo(user.id);

      // Fetch support contacts (non-blocking)
      _loadSupportContacts();
    } catch (e) {
      debugPrint('❌ Profile load error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<Map<String, dynamic>> _loadProfileFallback(String userId) async {
    // ── Step 1: User profile ──────────────────────────────────
    Map<String, dynamic> userData = {};
    try {
      final rawUserData = await SupabaseConfig.client
          .from('users')
          .select(
              'full_name, email, company_name, phone_number, address, city, province, district, profile_photo, created_at')
          .eq('id', userId)
          .maybeSingle();

      if (rawUserData != null) {
        userData = Map<String, dynamic>.from(rawUserData as Map);
      } else {
        debugPrint('⚠️ No users row found for $userId — using auth fallback');
        userData = {
          'email': SupabaseConfig.client.auth.currentUser?.email ?? '',
        };
      }
    } catch (e) {
      debugPrint('⚠️ User profile query error: $e');
      userData = {
        'email': SupabaseConfig.client.auth.currentUser?.email ?? '',
      };
    }

    // ── Step 2: Tickets + machines in parallel ────────────────
    List<Map<String, dynamic>> ticketList = [];
    List<Map<String, dynamic>> machineList = [];
    try {
      final parallelResults = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('service_tickets')
            .select('id, status, ticket_type')
            .eq('user_id', userId)
            .eq('is_deleted', false),
        SupabaseConfig.client
            .from('customer_machines')
            .select('id, status')
            .eq('user_id', userId),
      ]);

      ticketList = ((parallelResults[0] as List?) ?? [])
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList();
      machineList = ((parallelResults[1] as List?) ?? [])
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Stats parallel query error: $e');
    }

    // ── Step 3: Unread notification count ────────────────────
    int unreadCount = 0;
    try {
      final notifResponse = await SupabaseConfig.client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      unreadCount = ((notifResponse as List?) ?? []).length;
    } catch (e) {
      debugPrint('⚠️ Unread count query error: $e');
    }

    // ── Step 4: Compute derived values ────────────────────────
    // Active states (per spec): new / open / assigned / in_progress / waiting_customer.
    // Closed states (NOT counted as open): resolved / closed / completed / cancelled.
    // Use a positive whitelist so a ticket that gets marked 'completed' or
    // 'cancelled' is correctly excluded from the badge.
    const activeStatuses = {
      'new',
      'open',
      'assigned',
      'in_progress',
      'waiting_customer',
    };
    final open =
        ticketList.where((t) => activeStatuses.contains(t['status'])).length;
    final resolved = ticketList.length - open;

    int progress = 0;
    if ((userData['full_name'] ?? '').toString().isNotEmpty &&
        (userData['company_name'] ?? '').toString().isNotEmpty) {
      progress += 10;
    }
    if (machineList.isNotEmpty) {
      progress += 15 + ((machineList.length - 1) * 10).clamp(0, 30);
    }
    if (ticketList.any((t) => t['ticket_type'] == 'support')) progress += 10;
    if (ticketList.any((t) => t['ticket_type'] == 'inquiry')) progress += 10;
    if (ticketList.any((t) => t['ticket_type'] == 'order')) progress += 15;
    progress = progress.clamp(0, 100);

    int completed = 0;
    const int total = 8;
    if ((userData['full_name'] ?? '').toString().isNotEmpty) completed++;
    if ((userData['email'] ?? '').toString().isNotEmpty) completed++;
    if ((userData['phone_number'] ?? '').toString().isNotEmpty) completed++;
    if ((userData['company_name'] ?? '').toString().isNotEmpty) completed++;
    if ((userData['address'] ?? '').toString().isNotEmpty) completed++;
    if ((userData['city'] ?? '').toString().isNotEmpty) completed++;
    if ((userData['profile_photo'] ?? '').toString().isNotEmpty) completed++;
    if (machineList.isNotEmpty) completed++;

    String nextAction = 'Complete your profile';
    if (completed == total) {
      nextAction = 'Profile complete!';
    } else if ((userData['profile_photo'] ?? '').toString().isEmpty) {
      nextAction = 'Add a profile photo';
    } else if (machineList.isEmpty) {
      nextAction = 'Explore our machine catalog';
    }

    return {
      'user': {
        'id': userId,
        'email': userData['email'] ?? '',
        'full_name': userData['full_name'] ?? '',
        'company_name': userData['company_name'] ?? '',
        'phone_number': userData['phone_number'] ?? '',
        'address': userData['address'] ?? '',
        'city': userData['city'] ?? '',
        'province': userData['province'],
        'district': userData['district'],
        'profile_photo': userData['profile_photo'],
        'created_at': userData['created_at'],
      },
      'stats': {
        'total_machines': machineList.length,
        'active_machines':
            machineList.where((m) => m['status'] == 'active').length,
        'total_tickets': ticketList.length,
        'open_tickets': open,
        'resolved_tickets': resolved,
        'total_inquiries':
            ticketList.where((t) => t['ticket_type'] == 'inquiry').length,
        'total_orders':
            ticketList.where((t) => t['ticket_type'] == 'order').length,
        'unread_notifications': unreadCount,
      },
      'progress': {
        'percentage': progress,
        'milestone_25': progress >= 25,
        'milestone_50': progress >= 50,
        'milestone_75': progress >= 75,
        'milestone_100': progress >= 100,
      },
      'profile_completeness': {
        'percentage': (completed * 100 / total).round(),
        'completed': completed,
        'total': total,
        'next_action': nextAction,
      },
    };
  }

  void _parseProfileData(Map<String, dynamic> data) {
    final user = (data['user'] is Map)
        ? Map<String, dynamic>.from(data['user'] as Map)
        : <String, dynamic>{};
    final stats = (data['stats'] is Map)
        ? Map<String, dynamic>.from(data['stats'] as Map)
        : <String, dynamic>{};
    final progress = (data['progress'] is Map)
        ? Map<String, dynamic>.from(data['progress'] as Map)
        : <String, dynamic>{};
    final completeness = (data['profile_completeness'] is Map)
        ? Map<String, dynamic>.from(data['profile_completeness'] as Map)
        : <String, dynamic>{};

    _emailController.text = (user['email'] ?? '').toString();
    _nameController.text = (user['full_name'] ?? '').toString();
    _companyController.text = (user['company_name'] ?? '').toString();
    _phoneController.text = (user['phone_number'] ?? '').toString();
    _addressController.text = (user['address'] ?? '').toString();
    _cityController.text = (user['city'] ?? '').toString();
    final loadedProvince = (user['province'] as String?)?.trim();
    final loadedDistrict = (user['district'] as String?)?.trim();
    _province = (loadedProvince == null || loadedProvince.isEmpty)
        ? null
        : loadedProvince;
    // Only keep the district if it still belongs to the loaded province —
    // protects against legacy/orphaned data.
    if (_province != null &&
        loadedDistrict != null &&
        loadedDistrict.isNotEmpty &&
        SriLankaLocations.districtsOf(_province).contains(loadedDistrict)) {
      _district = loadedDistrict;
    } else {
      _district = null;
    }
    _profileImageUrl = user['profile_photo'] as String?;
    _createdAt = user['created_at'] != null
        ? DateTime.tryParse(user['created_at'].toString())
        : null;
    _storeOriginalValues();

    _totalMachines = (stats['total_machines'] as num?)?.toInt() ?? 0;
    _totalTickets = (stats['total_tickets'] as num?)?.toInt() ?? 0;
    _openTickets = (stats['open_tickets'] as num?)?.toInt() ?? 0;
    _resolvedTickets = (stats['resolved_tickets'] as num?)?.toInt() ?? 0;
    _unreadNotifications =
        (stats['unread_notifications'] as num?)?.toInt() ?? 0;

    _progressPercentage = (progress['percentage'] as num?)?.toInt() ?? 0;
    _milestone25 = progress['milestone_25'] as bool? ?? false;
    _milestone50 = progress['milestone_50'] as bool? ?? false;
    _milestone75 = progress['milestone_75'] as bool? ?? false;
    _milestone100 = progress['milestone_100'] as bool? ?? false;

    _profileCompletePercent =
        (completeness['percentage'] as num?)?.toInt() ?? 0;
    _profileCompletedFields = (completeness['completed'] as num?)?.toInt() ?? 0;
    _profileTotalFields = (completeness['total'] as num?)?.toInt() ?? 8;
    _nextProfileAction = (completeness['next_action'] as String?) ?? '';
  }

  void _storeOriginalValues() {
    _originalValues = {
      'full_name': _nameController.text,
      'company_name': _companyController.text,
      'phone_number': _phoneController.text,
      'address': _addressController.text,
      'city': _cityController.text,
      'province': _province ?? '',
      'district': _district ?? '',
    };
  }

  void _restoreOriginalValues() {
    _nameController.text = _originalValues['full_name'] ?? '';
    _companyController.text = _originalValues['company_name'] ?? '';
    _phoneController.text = _originalValues['phone_number'] ?? '';
    _addressController.text = _originalValues['address'] ?? '';
    _cityController.text = _originalValues['city'] ?? '';
    final p = _originalValues['province'] ?? '';
    final d = _originalValues['district'] ?? '';
    _province = p.isEmpty ? null : p;
    _district = d.isEmpty ? null : d;
  }

  bool get _hasUnsavedChanges =>
      _nameController.text != (_originalValues['full_name'] ?? '') ||
      _companyController.text != (_originalValues['company_name'] ?? '') ||
      _phoneController.text != (_originalValues['phone_number'] ?? '') ||
      _addressController.text != (_originalValues['address'] ?? '') ||
      _cityController.text != (_originalValues['city'] ?? '') ||
      (_province ?? '') != (_originalValues['province'] ?? '') ||
      (_district ?? '') != (_originalValues['district'] ?? '');

  // ── Storage Cleanup Helpers ─────────────────────────────────
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
    } catch (_) {
      // Non-critical — old file remains but doesn't block flow
    }
  }

  // ── Image Handling ─────────────────────────────────────────
  Future<void> _pickAndUploadImage() async {
    final isDark = _isDark;
    try {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => _buildImageSourceSheet(isDark),
      );
      if (action == null || !mounted) return;
      if (action == 'remove') {
        await _removeProfileImage();
        return;
      }

      final source =
          action == 'camera' ? ImageSource.camera : ImageSource.gallery;
      final XFile? image = await ImagePicker().pickImage(
          source: source, maxWidth: 512, maxHeight: 512, imageQuality: 75);
      if (image == null || !mounted) return;

      setState(() => _isUploadingImage = true);

      final bytes = await image.readAsBytes();

      // Validate before touching storage
      final validation = UploadValidator.validate(
        bytes: bytes,
        filename: image.name,
        category: UploadCategory.profilePhoto,
      );
      if (!validation.ok) {
        if (!mounted) return;
        setState(() => _isUploadingImage = false);
        _showError(validation.error!);
        return;
      }

      // Delete old photo from storage before uploading new one
      await _deleteStorageFile(_profileImageUrl);

      final fileExt = image.path.split('.').last;
      final path = '$_userId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await SupabaseConfig.client.storage.from('profile-photos').uploadBinary(
          path, bytes,
          fileOptions: const FileOptions(upsert: true));

      final imageUrl = SupabaseConfig.client.storage
          .from('profile-photos')
          .getPublicUrl(path);

      await SupabaseConfig.client.from('users').update({
        'profile_photo': imageUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _userId);

      if (!mounted) return;
      setState(() {
        _profileImageUrl = imageUrl;
        _isUploadingImage = false;
      });
      _showSuccess('Profile photo updated!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingImage = false);
      _showError(
          'Upload failed: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<void> _removeProfileImage() async {
    if (_profileImageUrl == null) return;
    setState(() => _isUploadingImage = true);
    try {
      await _deleteStorageFile(_profileImageUrl);

      await SupabaseConfig.client.from('users').update({
        'profile_photo': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _userId);

      if (!mounted) return;
      setState(() {
        _profileImageUrl = null;
        _isUploadingImage = false;
      });
      _showSuccess('Profile photo removed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingImage = false);
      _showError('Failed to remove photo');
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await SupabaseConfig.client.from('users').update({
        'full_name': _nameController.text.trim(),
        'company_name': _companyController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'province': _province,
        'district': _district,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _userId);

      // ── Check profile completion for bonus points ──
      final hasPhoto = (_profileImageUrl ?? '').isNotEmpty;
      if (_nameController.text.trim().isNotEmpty &&
          _phoneController.text.trim().isNotEmpty &&
          _companyController.text.trim().isNotEmpty &&
          _cityController.text.trim().isNotEmpty &&
          _addressController.text.trim().isNotEmpty &&
          hasPhoto) {
        PointsService.awardOnce(
          'complete_profile',
          100,
          'Profile completed — all fields filled',
        );
      }

      _storeOriginalValues();
      if (!mounted) return;
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      _showSuccess('Profile updated successfully!');
      _loadProfile();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError(
          'Error saving profile: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<void> _changePassword() async {
    final email = _emailController.text;
    if (email.isEmpty) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _confirmDialog(
            icon: Icons.lock_reset_rounded,
            iconColor: Brand.royalBlueLight,
            title: 'Reset Password',
            message: 'We\'ll send a password reset link to:\n$email',
            confirmText: 'Send Link',
            confirmColor: Brand.royalBlueLight));
    if (confirmed != true || !mounted) return;
    try {
      await SupabaseConfig.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'iconnect://password-reset',
      );
      if (!mounted) return;
      _showSuccess('Password reset link sent to $email');
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to send reset link');
    }
  }

  Future<void> _exportData() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _confirmDialog(
            icon: Icons.download_rounded,
            iconColor: Brand.royalBlueLight,
            title: 'Export Your Data',
            message: 'We\'ll prepare a copy of all your data.',
            confirmText: 'Export',
            confirmColor: Brand.royalBlueLight));
    if (confirmed != true || !mounted) return;

    try {
      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('users')
            .select(
                'full_name, email, phone_number, company_name, address, city, created_at')
            .eq('id', _userId)
            .maybeSingle(),
        SupabaseConfig.client
            .from('customer_machines')
            .select('serial_number, purchase_date, warranty_end_date, status')
            .eq('user_id', _userId),
        SupabaseConfig.client
            .from('service_tickets')
            .select('ticket_number, ticket_type, subject, status, created_at')
            .eq('user_id', _userId)
            .eq('is_deleted', false)
            .order('created_at', ascending: false),
      ]);

      if (!mounted) return;

      final exportedData = {
        'personal_info': results[0] != null
            ? Map<String, dynamic>.from(results[0] as Map)
            : {},
        'machines': ((results[1] as List?) ?? [])
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList(),
        'tickets': ((results[2] as List?) ?? [])
            .map((t) => Map<String, dynamic>.from(t as Map))
            .toList(),
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'app': 'iFrontiers Connect v1.0.0',
      };

      await SharePlus.instance.share(ShareParams(
          text: const JsonEncoder.withIndent('  ').convert(exportedData),
          subject: 'iFrontiers Connect - My Data Export'));
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (!mounted) return;
      _showError('Failed to export data. Please try again.');
    }
  }

  Future<void> _deactivateAccount() async {
    final isDark = _isDark;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _confirmDialog(
              icon: Icons.warning_rounded,
              iconColor: isDark ? const Color(0xFFFF6B6B) : Colors.red.shade400,
              title: 'Sign Out & Contact Support',
              message:
                  'To deactivate your account, please contact support at marketing@ifrontiers.lk after signing out.',
              confirmText: 'Sign Out',
              confirmColor: Colors.red,
            ));
    if (confirmed != true || !mounted) return;

    try {
      final ns = NotificationService();
      await ns.unsubscribeFromAllTopics();
      await ns.onLogout();
    } catch (_) {}

    await SupabaseConfig.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _shareApp() async {
    await SharePlus.instance.share(ShareParams(
        text:
            'Check out iFrontiers Connect - The smart way to manage your industrial machines! Download from: https://play.google.com/store/apps/details?id=com.ifrontiers.connect',
        subject: 'iFrontiers Connect App'));
  }

  Future<void> _logout() async {
    final t = S.of(context)!;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _confirmDialog(
            icon: Icons.logout_rounded,
            iconColor: _isDark ? const Color(0xFFFF6B6B) : Colors.red.shade400,
            title: 'Sign Out?',
            message: 'Are you sure you want to sign out\nof your account?',
            confirmText: t.authLogout,
            confirmColor: Colors.red));
    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      final ns = NotificationService();
      await ns.unsubscribeFromAllTopics();
      await ns.onLogout();
      await SupabaseConfig.client.auth.signOut();

      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showError('Sign out failed: $e');
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: Brand.lightGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.r(12)))));
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.r(12)))));
  }

  String _getMemberSince() {
    if (_createdAt == null) return 'N/A';
    final m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${m[_createdAt!.month - 1]} ${_createdAt!.day}, ${_createdAt!.year}';
  }

  String _getMemberDuration() {
    if (_createdAt == null) return '';
    final d = DateTime.now().difference(_createdAt!).inDays;
    if (d < 30) return '${d}d';
    if (d < 365) return '${(d / 30).floor()}mo';
    return '${(d / 365).floor()}y ${((d % 365) / 30).floor()}mo';
  }

  // ── Real Tier Helpers (DB-backed — matches home_page) ──

  Map<String, dynamic> _getTierConfig(String tier) {
    switch (tier) {
      case 'platinum':
        return {
          'label': 'PLATINUM',
          'emoji': '💎',
          'color': const Color(0xFFE5E4E2),
          'gradient': [const Color(0xFFE5E4E2), const Color(0xFFB8B8B8)],
        };
      case 'gold':
        return {
          'label': 'GOLD',
          'emoji': '🥇',
          'color': const Color(0xFFFFD700),
          'gradient': [const Color(0xFFFFD700), const Color(0xFFFFA000)],
        };
      case 'silver':
        return {
          'label': 'SILVER',
          'emoji': '🥈',
          'color': const Color(0xFFC0C0C0),
          'gradient': [const Color(0xFFC0C0C0), const Color(0xFF9E9E9E)],
        };
      default:
        return {
          'label': 'BRONZE',
          'emoji': '🥉',
          'color': const Color(0xFFCD7F32),
          'gradient': [const Color(0xFFCD7F32), const Color(0xFFA0522D)],
        };
    }
  }

  String _getTierProgressMessage() {
    final pointsNeeded = _nextTierThreshold - _totalPoints;
    if (_currentTier == 'platinum') {
      return 'You\'ve reached the highest tier! 🎉';
    }
    final nextTier = _currentTier == 'bronze'
        ? 'Silver'
        : _currentTier == 'silver'
            ? 'Gold'
            : 'Platinum';
    return '$pointsNeeded pts to $nextTier →';
  }

  // ── Engagement Progress Helpers (feature adoption — NOT real tiers) ──

  String _getMilestoneLabel() {
    if (_progressPercentage >= 75) return 'Champion';
    if (_progressPercentage >= 50) return 'Achiever';
    if (_progressPercentage >= 25) return 'Explorer';
    return 'Starter';
  }

  Color _getMilestoneColor() {
    if (_progressPercentage >= 75) return const Color(0xFF9C27B0);
    if (_progressPercentage >= 50) return const Color(0xFFFF6D00);
    if (_progressPercentage >= 25) return const Color(0xFF0097A7);
    return const Color(0xFF5C6BC0);
  }

  IconData _getMilestoneIcon() {
    if (_progressPercentage >= 75) return Icons.emoji_events_rounded;
    if (_progressPercentage >= 50) return Icons.workspace_premium_rounded;
    if (_progressPercentage >= 25) return Icons.explore_rounded;
    return Icons.rocket_launch_rounded;
  }

  String _getProgressHint() {
    if (_progressPercentage >= 100) {
      return 'You\'re an iFrontiers power user! 🎉';
    }
    if (_progressPercentage >= 75) return 'Almost there! Keep exploring.';
    if (_progressPercentage >= 50) {
      return 'Great progress! Try our knowledge base.';
    }
    if (_progressPercentage >= 25) return 'Good start! Register more machines.';
    return 'Complete your profile to get started!';
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  // ── Tier Info Fetch (DB-backed — matches home_page pattern) ──
  Future<void> _fetchTierInfo(String userId) async {
    try {
      final result = await SupabaseConfig.client
          .rpc('get_tier_dashboard', params: {'p_user_id': userId});

      if (!mounted) return;
      setState(() {
        _tierData = result is Map
            ? Map<String, dynamic>.from(result)
            : <String, dynamic>{};
      });
    } catch (e) {
      debugPrint('⚠️ Fetch tier info error: $e');
      // Non-fatal — hero card falls back to defaults
    }
  }

  Future<void> _loadSupportContacts() async {
    try {
      final rows = await SupabaseConfig.client
          .from('support_contacts')
          .select('*')
          .eq('is_active', true)
          .order('display_order');
      if (!mounted) return;
      setState(() {
        _supportContacts = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      debugPrint('Support contacts load failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // ignore: unused_local_variable — used in child methods via context
    final t = S.of(context)!;
    // ignore: unused_local_variable — used in child methods via context
    final localeProvider = Provider.of<LocaleProvider>(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Brand.canvas(isDark),
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: isDark ? Brand.darkCard : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(Brand.r(22)),
                  border: isDark ? Border.all(color: Brand.darkBorder) : null),
              child: Center(
                  child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          color:
                              isDark ? Brand.darkIconActive : Brand.royalBlue,
                          strokeWidth: 3)))),
          const SizedBox(height: 16),
          Text(S.of(context)!.profileLoading,
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
        ])),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Brand.darkCard)
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.white),
      child: PopScope(
        canPop: !(_isEditing && _hasUnsavedChanges),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _isEditing && _hasUnsavedChanges) {
            _showDiscardEditsDialog();
          }
        },
        child: Scaffold(
          backgroundColor: Brand.canvas(isDark),
          body: _hasError ? _buildErrorState(isDark) : _buildBody(isDark),
          bottomNavigationBar: widget.showNavBar
              ? CustomerNavBar(
                  currentIndex: 4,
                  onTabSelected: CustomerNavController.switchTab,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    return RefreshIndicator(
      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
      backgroundColor: Brand.surface(isDark),
      onRefresh: _loadProfile,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: _buildTopBar(isDark)),
          SliverToBoxAdapter(child: _buildProfileHero(isDark)),
          if (_profileCompletePercent < 100)
            SliverToBoxAdapter(child: _buildCompletenessCard(isDark)),
          SliverToBoxAdapter(child: _buildStatsGrid(isDark)),
          SliverToBoxAdapter(child: _buildProgressCard(isDark)),
          SliverToBoxAdapter(child: _buildTierBenefitsCard(isDark)),
          SliverToBoxAdapter(child: _buildAccountInfo(isDark)),
          SliverToBoxAdapter(child: _buildQuickNav(isDark)),
          SliverToBoxAdapter(child: _buildDocumentsSection(isDark)),
          SliverToBoxAdapter(child: _buildContactCard(isDark)),
          SliverToBoxAdapter(child: _buildThemeSelector(isDark)),
          SliverToBoxAdapter(child: _buildSettings(isDark)),
          SliverToBoxAdapter(child: _buildDangerZone(isDark)),
          SliverToBoxAdapter(child: _buildLogoutBtn(isDark)),
          SliverToBoxAdapter(child: _buildVersion(isDark)),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return SafeArea(
        child: Center(
            child: Container(
      margin: const EdgeInsets.all(32),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(24)),
          border: isDark ? Border.all(color: Brand.darkBorder) : null),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: Colors.red.withAlpha(isDark ? 38 : 26),
                borderRadius: BorderRadius.circular(Brand.r(22))),
            child: Icon(Icons.error_outline,
                size: 36,
                color: isDark ? const Color(0xFFFF6B6B) : Colors.red)),
        const SizedBox(height: 20),
        Text(S.of(context)!.profileLoadFailed,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        const SizedBox(height: 10),
        Text('Please check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight)),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: isDark
                              ? Brand.darkBorderLight
                              : Brand.borderLight),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.r(14)))),
                  child: Text(S.of(context)!.commonBack,
                      style: TextStyle(
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight)))),
          const SizedBox(width: 12),
          Expanded(
              child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _hasError = false;
                    });
                    _loadProfile();
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isDark ? Brand.darkIconActive : Brand.royalBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.r(14)))),
                  child: Text(S.of(context)!.commonRetry,
                      style: TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ]),
    )));
  }

  // ── TOP BAR — Navy Glow hero ────────────────────────────────
  Widget _buildTopBar(bool isDark) {
    return DsPageHeader(
      title: S.of(context)!.profileTitle,
      onBack: () {
        if (_isEditing && _hasUnsavedChanges) {
          _showDiscardEditsDialog();
        } else {
          Navigator.pop(context);
        }
      },
    );
  }

  void _showDiscardEditsDialog() {
    showDialog(
        context: context,
        builder: (context) => _confirmDialog(
              icon: Icons.warning_rounded,
              iconColor: _isDark ? const Color(0xFFFFB74D) : Colors.orange,
              title: S.of(context)!.profileDiscardChanges,
              message: 'Your unsaved changes will be lost.',
              confirmText: S.of(context)!.registerDiscard,
              confirmColor: Colors.red,
              cancelText: S.of(context)!.profileKeepEditing,
            )).then((v) {
      if (v == true) {
        _restoreOriginalValues();
        setState(() => _isEditing = false);
      }
    });
  }

  Widget _buildProfileHero(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.r(26)),
        gradient: LinearGradient(
            colors: isDark
                ? [Brand.darkCard, Brand.darkCardElevated]
                : [Brand.royalBlueDark, Brand.royalBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        border:
            isDark ? Border.all(color: Brand.darkBorderLight, width: 1) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Brand.royalBlue.withAlpha(89),
                    blurRadius: 28,
                    offset: const Offset(0, 10))
              ],
      ),
      child: Stack(children: [
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
                        : Colors.white.withAlpha(10)))),
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
                        : Colors.white.withAlpha(8)))),
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
                        : Colors.white.withAlpha(5)))),
        Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Row(children: [
                Stack(children: [
                  Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isDark
                                  ? Brand.darkBorderLight
                                  : Colors.white.withAlpha(51),
                              width: 3)),
                      child: ClipOval(
                          child: _profileImageUrl != null &&
                                  _profileImageUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: _profileImageUrl!,
                                  fit: BoxFit.cover,
                                  width: 76,
                                  height: 76,
                                  placeholder: (_, __) => _avatarFallback(),
                                  errorWidget: (_, __, ___) =>
                                      _avatarFallback(),
                                )
                              : _avatarFallback())),
                  Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                          onTap: _isUploadingImage ? null : _pickAndUploadImage,
                          child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Brand.lightGreen,
                                    Brand.lightGreenBright
                                  ]),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: isDark
                                          ? Brand.darkCard
                                          : Brand.royalBlueDark,
                                      width: 2.5)),
                              child: _isUploadingImage
                                  ? const Padding(
                                      padding: EdgeInsets.all(5),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: Colors.white))
                                  : const Icon(Icons.camera_alt_rounded,
                                      size: 12, color: Colors.white)))),
                ]),
                const SizedBox(width: 18),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          _nameController.text.isNotEmpty
                              ? _nameController.text
                              : 'Your Name',
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Brand.darkTextPrimary : Colors.white,
                              letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(
                          _companyController.text.isNotEmpty
                              ? _companyController.text
                              : _emailController.text,
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Colors.white.withAlpha(140),
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      Row(children: [
                        Builder(builder: (_) {
                          final tierConfig = _getTierConfig(_currentTier);
                          final tierColor = tierConfig['color'] as Color;
                          final tierLabel = tierConfig['label'] as String;
                          final tierEmoji = tierConfig['emoji'] as String;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: tierColor.withAlpha(isDark ? 31 : 46),
                                borderRadius:
                                    BorderRadius.circular(Brand.r(20)),
                                border: Border.all(
                                    color:
                                        tierColor.withAlpha(isDark ? 51 : 64))),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(tierEmoji,
                                  style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text('$tierLabel Member',
                                  style: TextStyle(
                                      color: tierColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ]),
                          );
                        }),
                        if (_getMemberDuration().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(_getMemberDuration(),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : Colors.white.withAlpha(89),
                                  fontWeight: FontWeight.w500)),
                        ],
                      ]),
                    ])),
              ]),
              const SizedBox(height: 20),
              // ── Points + Streak Row (matches home_page) ──
              Builder(builder: (_) {
                final tierConfig = _getTierConfig(_currentTier);
                final tierColor = tierConfig['color'] as Color;
                return Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: tierColor.withAlpha(isDark ? 31 : 46),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                      border: Border.all(
                          color: tierColor.withAlpha(isDark ? 38 : 51)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.stars_rounded, color: tierColor, size: 14),
                      const SizedBox(width: 4),
                      Text('$_totalPoints pts',
                          style: TextStyle(
                            color: tierColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          )),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  if (_loginStreak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(isDark ? 26 : 31),
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                        border: Border.all(
                            color: Colors.orange.withAlpha(isDark ? 38 : 46)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🔥', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 3),
                        Text('$_loginStreak day',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.orange.shade300
                                  : Colors.orange.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            )),
                      ]),
                    ),
                  const Spacer(),
                  Flexible(
                    child: Text(_getTierProgressMessage(),
                        style: TextStyle(
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Colors.white.withAlpha(128),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right),
                  ),
                ]);
              }),
              const SizedBox(height: 14),
              Row(children: [
                Icon(Icons.calendar_today_rounded,
                    color: isDark
                        ? Brand.darkTextTertiary
                        : Colors.white.withAlpha(77),
                    size: 14),
                const SizedBox(width: 6),
                Text('Member since ${_getMemberSince()}',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : Colors.white.withAlpha(102),
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                Opacity(
                  opacity: isDark ? 0.40 : 0.55,
                  child: const AppLogo.wordmark(height: 20, dark: true),
                ),
              ]),
            ])),
      ]),
    );
  }

  Widget _avatarFallback() => Container(
      width: 76,
      height: 76,
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Brand.lightGreen, Brand.lightGreenBright],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: Center(
          child: Text(StringUtils.getInitials(_nameController.text),
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: Colors.white))));

  Widget _buildCompletenessCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color:
              isDark ? Brand.darkCard : Brand.royalBlueSurface.withAlpha(179),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: Border.all(
              color:
                  isDark ? Brand.darkBorder : Brand.royalBlue.withAlpha(26))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_circle_outlined,
              color: isDark ? Brand.darkIconActive : Brand.royalBlue, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(S.of(context)!.profileCompletionTitle,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark))),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: isDark
                      ? Brand.darkCardElevated
                      : Brand.royalBlue.withAlpha(26),
                  borderRadius: BorderRadius.circular(Brand.r(8)),
                  border:
                      isDark ? Border.all(color: Brand.darkBorderLight) : null),
              child: Text('$_profileCompletedFields/$_profileTotalFields',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue))),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
            borderRadius: BorderRadius.circular(Brand.r(10)),
            child: LinearProgressIndicator(
                value: _profileCompletePercent / 100,
                minHeight: 6,
                backgroundColor: isDark
                    ? Brand.darkBorderLight.withAlpha(102)
                    : Brand.royalBlue.withAlpha(20),
                valueColor: AlwaysStoppedAnimation(
                    isDark ? Brand.darkIconActive : Brand.royalBlue))),
        if (_nextProfileAction.isNotEmpty &&
            _nextProfileAction != 'Profile complete!') ...[
          const SizedBox(height: 12),
          GestureDetector(
              onTap: () {
                if (_nextProfileAction.contains('photo')) {
                  _pickAndUploadImage();
                } else if (_nextProfileAction.contains('machine') ||
                    _nextProfileAction.contains('catalog')) {
                  _navigateTo(const CatalogPage());
                } else {
                  setState(() => _isEditing = true);
                }
              },
              child: Row(children: [
                Icon(Icons.arrow_forward_rounded,
                    size: 14,
                    color: isDark ? Brand.darkIconActive : Brand.royalBlue),
                const SizedBox(width: 6),
                Text(_nextProfileAction,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Brand.darkIconActive : Brand.royalBlue)),
              ])),
        ],
      ]),
    );
  }

  Widget _buildStatsGrid(bool isDark) {
    final stats = [
      _Stat(
          (c) => IcTwinGearIcon(
              primaryColor: c, secondaryColor: c.withAlpha(180), size: 19),
          '$_totalMachines',
          'Machines',
          isDark ? Brand.darkIconActive : Brand.royalBlue),
      _Stat((c) => IcTicketIcon(color: c, size: 19), '$_totalTickets',
          'Tickets', isDark ? Brand.lightGreenBright : Brand.lightGreen),
      _Stat((c) => IcChatGearIcon(color: c, size: 19), '$_openTickets', 'Open',
          isDark ? const Color(0xFFFFB74D) : Colors.orange),
      _Stat((c) => Icon(Icons.check_circle_rounded, color: c, size: 19),
          '$_resolvedTickets', 'Resolved', const Color(0xFF4CAF50)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
          children: stats
              .map((s) => Expanded(
                      child: Container(
                    margin: EdgeInsets.only(right: s == stats.last ? 0 : 10),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                        color: Brand.surface(isDark),
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        border: Border.all(
                            color: isDark
                                ? Brand.darkBorder
                                : s.color.withAlpha(26)),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                    color: s.color.withAlpha(13),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3))
                              ]),
                    child: Column(children: [
                      Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                              color: s.color.withAlpha(isDark ? 31 : 20),
                              borderRadius: BorderRadius.circular(Brand.r(11)),
                              border: isDark
                                  ? Border.all(color: s.color.withAlpha(38))
                                  : null),
                          child: Center(child: s.iconWidget(s.color))),
                      const SizedBox(height: 8),
                      Text(s.value,
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark)),
                      const SizedBox(height: 2),
                      Text(s.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                              fontWeight: FontWeight.w600)),
                    ]),
                  )))
              .toList()),
    );
  }

  Widget _buildProgressCard(bool isDark) {
    final mc = _getMilestoneColor();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(22)),
          border: isDark ? Border.all(color: Brand.darkBorder) : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Brand.royalBlue.withAlpha(10),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color:
                      isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                  border:
                      isDark ? Border.all(color: Brand.darkBorderLight) : null),
              child: Icon(Icons.trending_up_rounded,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  size: 22)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(S.of(context)!.profileEngagementProgress,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark))),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: mc.withAlpha(isDark ? 31 : 26),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                  border: isDark ? Border.all(color: mc.withAlpha(51)) : null),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_getMilestoneIcon(), color: mc, size: 14),
                const SizedBox(width: 4),
                Text(_getMilestoneLabel(),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: mc)),
              ])),
        ]),
        const SizedBox(height: 20),
        AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, _) {
              return Column(children: [
                Stack(children: [
                  Container(
                      height: 10,
                      decoration: BoxDecoration(
                          color: isDark
                              ? Brand.darkBorderLight.withAlpha(102)
                              : Brand.royalBlueSurface,
                          borderRadius: BorderRadius.circular(Brand.r(5)))),
                  FractionallySizedBox(
                      widthFactor: _progressAnimation.value,
                      child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: [mc, mc.withAlpha(179)]),
                              borderRadius: BorderRadius.circular(Brand.r(5)),
                              boxShadow: [
                                BoxShadow(
                                    color: mc.withAlpha(102), blurRadius: 8)
                              ]))),
                  Positioned.fill(
                      child: Row(children: [
                    _pDot(25, _milestone25, mc, isDark),
                    _pDot(50, _milestone50, mc, isDark),
                    _pDot(75, _milestone75, mc, isDark),
                    _pDot(100, _milestone100, mc, isDark),
                  ])),
                ]),
                const SizedBox(height: 10),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${(_progressAnimation.value * 100).round()}%',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: mc)),
                      Flexible(
                          child: Text(_getProgressHint(),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight),
                              overflow: TextOverflow.ellipsis)),
                    ]),
              ]);
            }),
        const SizedBox(height: 16),
        Row(children: [
          _mMarker('Starter', 0, const Color(0xFF5C6BC0), isDark),
          _mMarker('Explorer', 25, const Color(0xFF0097A7), isDark),
          _mMarker('Achiever', 50, const Color(0xFFFF6D00), isDark),
          _mMarker('Champion', 75, const Color(0xFF9C27B0), isDark),
        ]),
      ]),
    );
  }

  Widget _pDot(int t, bool r, Color mc, bool isDark) => Expanded(
      child: Align(
          alignment: Alignment.centerRight,
          child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: r
                      ? mc
                      : (isDark
                          ? Brand.darkTextTertiary.withAlpha(77)
                          : Brand.subtleLight.withAlpha(51)),
                  border:
                      Border.all(color: Brand.surface(isDark), width: 1.5)))));

  Widget _mMarker(String l, int t, Color c, bool isDark) {
    final r = _progressPercentage >= t;
    return Expanded(
        child: Column(children: [
      Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
              color: r
                  ? c
                  : (isDark ? Brand.darkCardElevated : Brand.royalBlueSurface),
              shape: BoxShape.circle,
              border: r
                  ? null
                  : Border.all(
                      color:
                          isDark ? Brand.darkBorderLight : Brand.borderLight)),
          child: r
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : null),
      const SizedBox(height: 4),
      Text(l,
          style: TextStyle(
              fontSize: 11,
              fontWeight: r ? FontWeight.w700 : FontWeight.w500,
              color: r
                  ? c
                  : (isDark ? Brand.darkTextSecondary : Brand.subtleLight))),
    ]));
  }

  // ── TIER BENEFITS CARD ──────────────────────────────────────
  // Shows all active benefits grouped by tier. The customer's current
  // tier is highlighted; locked tiers are shown dimmed.
  Widget _buildTierBenefitsCard(bool isDark) {
    final benefits = (_tierData['benefits'] as List?) ?? [];
    final thresholds = (_tierData['thresholds'] as List?) ?? [];

    // Nothing to show if data not loaded yet
    if (benefits.isEmpty && thresholds.isEmpty) return const SizedBox.shrink();

    // Tier ordering + display config
    const tierOrder = ['bronze', 'silver', 'gold', 'platinum'];
    final tierConfig = {
      'bronze': {
        'label': 'Bronze',
        'emoji': '🥉',
        'color': const Color(0xFFCD7F32),
      },
      'silver': {
        'label': 'Silver',
        'emoji': '🥈',
        'color': const Color(0xFF9E9E9E),
      },
      'gold': {
        'label': 'Gold',
        'emoji': '🥇',
        'color': const Color(0xFFF59E0B),
      },
      'platinum': {
        'label': 'Platinum',
        'emoji': '💎',
        'color': const Color(0xFF14B8A6),
      },
    };

    // Group benefits by tier
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final b in benefits) {
      final tier = (b['tier'] as String?) ?? 'bronze';
      grouped.putIfAbsent(tier, () => []).add(Map<String, dynamic>.from(b));
    }

    // Tier unlock threshold lookup
    final Map<String, int> minPts = {};
    for (final t in thresholds) {
      final tierName = (t['tier'] as String?) ?? '';
      final pts = (t['min_points'] as num?)?.toInt() ?? 0;
      minPts[tierName] = pts;
    }

    // Determine which tiers to show (those with benefits or with known thresholds)
    final tiersToShow = tierOrder
        .where(
            (t) => (grouped[t]?.isNotEmpty ?? false) || minPts.containsKey(t))
        .toList();

    if (tiersToShow.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(22)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                  border:
                      isDark ? Border.all(color: Brand.darkBorderLight) : null,
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loyalty Benefits',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    Text(
                      'Perks unlocked by tier',
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
            ]),
          ),

          Divider(
            height: 1,
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),

          // ── Tier sections ──────────────────────────────────────
          ...tiersToShow.map((tierName) {
            final cfg = tierConfig[tierName]!;
            final color = cfg['color'] as Color;
            final label = cfg['label'] as String;
            final emoji = cfg['emoji'] as String;
            final tierBenefits = grouped[tierName] ?? [];
            final isCurrentTier = tierName == _currentTier;
            final isUnlocked =
                tierOrder.indexOf(tierName) <= tierOrder.indexOf(_currentTier);
            final pts = minPts[tierName] ?? 0;

            return Container(
              decoration: BoxDecoration(
                color: isCurrentTier
                    ? color.withAlpha(isDark ? 20 : 12)
                    : Colors.transparent,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Brand.darkBorder : Brand.borderLight,
                    width: 0.5,
                  ),
                ),
              ),
              // Material(transparency) sits between the decorated card
              // Container and ExpansionTile's internal ListTile so the tile
              // can paint its ink/background. Without it Flutter asserts:
              // "ListTile background color or ink splashes may be invisible."
              child: Material(
                type: MaterialType.transparency,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    initiallyExpanded: isCurrentTier,
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    childrenPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isUnlocked
                            ? color.withAlpha(isDark ? 38 : 26)
                            : (isDark
                                ? Brand.darkCardElevated
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                        border: isUnlocked
                            ? Border.all(
                                color: color.withAlpha(isDark ? 64 : 51))
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          isUnlocked ? emoji : '🔒',
                          style: TextStyle(
                            fontSize: 16,
                            color: isUnlocked ? null : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    title: Row(children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isUnlocked
                              ? color
                              : (isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight),
                        ),
                      ),
                      if (isCurrentTier) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withAlpha(isDark ? 51 : 38),
                            borderRadius: BorderRadius.circular(Brand.r(20)),
                          ),
                          child: Text(
                            'Current',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ]),
                    subtitle: Text(
                      isUnlocked
                          ? (isCurrentTier
                              ? '$_totalPoints pts earned'
                              : 'Unlocked at $pts pts')
                          : 'Unlock at $pts pts',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                      ),
                    ),
                    children: tierBenefits.isEmpty
                        ? [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                              child: Text(
                                'No specific benefits listed for this tier yet.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : Brand.subtleLight,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ]
                        : tierBenefits.map((b) {
                            final name =
                                (b['benefit_name'] as String?) ?? 'Benefit';
                            final desc =
                                (b['benefit_description'] as String?) ?? '';
                            final iconName =
                                (b['icon_name'] as String?) ?? 'star';
                            final IconData icon = _benefitIcon(iconName);

                            return Opacity(
                              opacity: isUnlocked ? 1.0 : 0.45,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      margin: const EdgeInsets.only(top: 1),
                                      decoration: BoxDecoration(
                                        color: isUnlocked
                                            ? color.withAlpha(isDark ? 31 : 20)
                                            : (isDark
                                                ? Brand.darkCardElevated
                                                : const Color(0xFFF1F5F9)),
                                        borderRadius:
                                            BorderRadius.circular(Brand.r(8)),
                                      ),
                                      child: Icon(
                                        icon,
                                        size: 16,
                                        color: isUnlocked
                                            ? color
                                            : (isDark
                                                ? Brand.darkTextTertiary
                                                : Brand.subtleLight),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isUnlocked
                                                  ? (isDark
                                                      ? Brand.darkTextPrimary
                                                      : const Color(0xFF1E293B))
                                                  : (isDark
                                                      ? Brand.darkTextTertiary
                                                      : Brand.subtleLight),
                                            ),
                                          ),
                                          if (desc.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              desc,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark
                                                    ? Brand.darkTextSecondary
                                                    : Brand.subtleLight,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Maps icon_name strings (from DB) to Material icons
  IconData _benefitIcon(String name) {
    switch (name.toLowerCase()) {
      case 'discount':
      case 'local_offer':
        return Icons.local_offer_rounded;
      case 'priority':
      case 'flash_on':
        return Icons.flash_on_rounded;
      case 'support':
      case 'headset_mic':
        return Icons.headset_mic_rounded;
      case 'free':
      case 'card_giftcard':
      case 'gift':
        return Icons.card_giftcard_rounded;
      case 'warranty':
      case 'verified':
      case 'verified_user':
        return Icons.verified_user_rounded;
      case 'delivery':
      case 'local_shipping':
        return Icons.local_shipping_rounded;
      case 'star':
      case 'stars':
        return Icons.stars_rounded;
      case 'badge':
        return Icons.badge_rounded;
      case 'celebration':
        return Icons.celebration_rounded;
      case 'engineering':
        return Icons.engineering_rounded;
      case 'build':
        return Icons.build_rounded;
      case 'percent':
        return Icons.percent_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  // ── ACCOUNT INFO ────────────────────────────────────────────
  Widget _buildAccountInfo(bool isDark) {
    return Form(
        key: _formKey,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          padding: const EdgeInsets.all(20),
          decoration: _cardDeco(isDark),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () =>
                  setState(() => _accountInfoExpanded = !_accountInfoExpanded),
              behavior: HitTestBehavior.opaque,
              child: Row(children: [
                _sectionIcon(Icons.person_rounded, isDark),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(S.of(context)!.profileAccountInfo,
                        style: _sectionTitle(isDark))),
                if (!_isEditing && !_accountInfoExpanded)
                  AnimatedRotation(
                    turns: _accountInfoExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight),
                  )
                else if (!_isEditing && _accountInfoExpanded)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Material(
                        color: Colors.transparent,
                        child: InkWell(
                            onTap: () => setState(() {
                                  _isEditing = true;
                                  _accountInfoExpanded = true;
                                }),
                            borderRadius: BorderRadius.circular(Brand.r(10)),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    color: (isDark
                                            ? Brand.darkIconActive
                                            : Brand.royalBlue)
                                        .withAlpha(isDark ? 31 : 15),
                                    borderRadius:
                                        BorderRadius.circular(Brand.r(10))),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_rounded,
                                          size: 14,
                                          color: isDark
                                              ? Brand.darkIconActive
                                              : Brand.royalBlue),
                                      const SizedBox(width: 3),
                                      Text(S.of(context)!.commonEdit,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Brand.darkIconActive
                                                  : Brand.royalBlue)),
                                    ])))),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: 0.5,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    ),
                  ])
                else
                  Material(
                      color: Colors.transparent,
                      child: InkWell(
                          onTap: () {
                            if (_hasUnsavedChanges) {
                              _showDiscardEditsDialog();
                            } else {
                              setState(() => _isEditing = false);
                            }
                          },
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                  color: Colors.red.withAlpha(isDark ? 31 : 15),
                                  borderRadius:
                                      BorderRadius.circular(Brand.r(10))),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.close_rounded,
                                        size: 14,
                                        color: isDark
                                            ? const Color(0xFFFF6B6B)
                                            : Colors.red.shade400),
                                    const SizedBox(width: 3),
                                    Text(S.of(context)!.commonCancel,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? const Color(0xFFFF6B6B)
                                                : Colors.red.shade400)),
                                  ])))),
              ]),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    _infoField('Full Name', _nameController,
                        Icons.person_outline_rounded, _isEditing, isDark,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Name is required'
                            : null),
                    _infoField('Company', _companyController,
                        Icons.business_rounded, _isEditing, isDark),
                    _infoField('Email', _emailController, Icons.email_outlined,
                        false, isDark,
                        showLock: true),
                    _infoField('Phone', _phoneController, Icons.phone_rounded,
                        _isEditing, isDark, keyboardType: TextInputType.phone,
                        validator: (v) {
                      if (v != null && v.isNotEmpty) {
                        final c = v.replaceAll(RegExp(r'[\s\-\(\)]'), '');
                        if (c.length < 9 || c.length > 15) {
                          return 'Enter a valid phone number';
                        }
                      }
                      return null;
                    }),
                    _infoField('Address', _addressController,
                        Icons.location_on_outlined, _isEditing, isDark),
                    _infoField('City', _cityController,
                        Icons.location_city_rounded, _isEditing, isDark),
                    _dropdownField(
                      label: S.of(context)!.profileProvince,
                      icon: Icons.map_rounded,
                      value: _province,
                      enabled: _isEditing,
                      isDark: isDark,
                      options: SriLankaLocations.provinces,
                      onChanged: (v) => setState(() {
                        _province = v;
                        // Reset the district if it no longer belongs to
                        // the newly-picked province.
                        if (_district != null &&
                            !SriLankaLocations.districtsOf(v)
                                .contains(_district)) {
                          _district = null;
                        }
                      }),
                    ),
                    _dropdownField(
                      label: S.of(context)!.profileDistrict,
                      icon: Icons.location_on_outlined,
                      value: _district,
                      enabled: _isEditing && (_province != null),
                      isDark: isDark,
                      options: SriLankaLocations.districtsOf(_province),
                      onChanged: (v) => setState(() => _district = v),
                      placeholder: _province == null
                          ? 'Select province first'
                          : S.of(context)!.profileSelectDistrict,
                      isLast: true,
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: 18),
                      Material(
                          color: Colors.transparent,
                          child: InkWell(
                              onTap: _isSaving ? null : _saveProfile,
                              borderRadius: BorderRadius.circular(Brand.r(16)),
                              child: Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                          colors: isDark
                                              ? [
                                                  Brand.darkIconActive,
                                                  Brand.royalBlueGlow
                                                ]
                                              : [
                                                  Brand.royalBlue,
                                                  Brand.royalBlueLight
                                                ]),
                                      borderRadius:
                                          BorderRadius.circular(Brand.r(16)),
                                      boxShadow: [
                                        BoxShadow(
                                            color: isDark
                                                ? Brand.darkIconActive
                                                    .withAlpha(77)
                                                : Brand.royalBlue.withAlpha(89),
                                            blurRadius: 14,
                                            offset: const Offset(0, 5))
                                      ]),
                                  child: Center(
                                      child: _isSaving
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  color: Colors.white))
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                  const Icon(Icons.save_rounded,
                                                      color: Colors.white,
                                                      size: 20),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                      S
                                                          .of(context)!
                                                          .profileSaveChanges,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 14)),
                                                ]))))),
                    ],
                  ]),
              crossFadeState: _accountInfoExpanded || _isEditing
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ]),
        ));
  }

  Widget _infoField(String label, TextEditingController ctrl, IconData icon,
      bool enabled, bool isDark,
      {bool isLast = false,
      bool showLock = false,
      TextInputType? keyboardType,
      String? Function(String?)? validator}) {
    return Column(children: [
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: enabled
                        ? (isDark
                            ? Brand.darkCardElevated
                            : Brand.royalBlue.withAlpha(20))
                        : (isDark
                            ? Brand.darkCardElevated.withAlpha(128)
                            : Brand.royalBlueSurface.withAlpha(128)),
                    borderRadius: BorderRadius.circular(Brand.r(11)),
                    border: isDark && enabled
                        ? Border.all(color: Brand.darkBorderLight)
                        : null),
                child: Icon(icon,
                    size: 18,
                    color: enabled
                        ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                        : (isDark
                            ? Brand.darkTextTertiary
                            : Brand.subtleLight))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          letterSpacing: 0.5)),
                  TextFormField(
                      controller: ctrl,
                      enabled: enabled,
                      keyboardType: keyboardType,
                      validator: validator,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? (isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark)
                              : (isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight)),
                      decoration: InputDecoration(
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 5),
                          enabledBorder: InputBorder.none,
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: isDark
                                    ? Brand.darkIconActive
                                    : Brand.royalBlue,
                                width: 1.5),
                          ),
                          border: InputBorder.none)),
                ])),
            if (showLock)
              Icon(Icons.lock_outline_rounded,
                  size: 15,
                  color: isDark
                      ? Brand.darkTextTertiary
                      : Brand.subtleLight.withAlpha(102))
            else if (enabled)
              Icon(Icons.edit_rounded,
                  size: 15,
                  color: isDark
                      ? Brand.darkTextTertiary
                      : Brand.subtleLight.withAlpha(102)),
          ])),
      if (!isLast)
        Divider(
            color: isDark ? Brand.darkBorder : Brand.borderLight, height: 14),
    ]);
  }

  // ── Read-only / editable dropdown row (matches _infoField layout) ─
  Widget _dropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required bool enabled,
    required bool isDark,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String placeholder = 'Select',
    bool isLast = false,
  }) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: enabled
                  ? (isDark
                      ? Brand.darkCardElevated
                      : Brand.royalBlue.withAlpha(20))
                  : (isDark
                      ? Brand.darkCardElevated.withAlpha(128)
                      : Brand.royalBlueSurface.withAlpha(128)),
              borderRadius: BorderRadius.circular(Brand.r(11)),
              border: isDark && enabled
                  ? Border.all(color: Brand.darkBorderLight)
                  : null,
            ),
            child: Icon(icon,
                size: 18,
                color: enabled
                    ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                    : (isDark ? Brand.darkTextTertiary : Brand.subtleLight)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      letterSpacing: 0.5)),
              // When not editing OR no options → render as plain text so
              // the row visually matches _infoField.
              if (!enabled || options.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    (value == null || value.isEmpty)
                        ? (enabled ? placeholder : '—')
                        : value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: (value == null || value.isEmpty)
                            ? (isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight)
                            : (isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark)),
                  ),
                )
              else
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: options.contains(value) ? value : null,
                    hint: Text(placeholder,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight)),
                    icon: Icon(Icons.expand_more_rounded,
                        size: 18,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight),
                    dropdownColor:
                        isDark ? Brand.darkCardElevated : Colors.white,
                    items: options
                        .map((o) => DropdownMenuItem<String>(
                              value: o,
                              child: Text(o,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Brand.darkTextPrimary
                                          : Brand.royalBlueDark)),
                            ))
                        .toList(),
                    onChanged: onChanged,
                  ),
                ),
            ]),
          ),
          if (enabled && options.isNotEmpty)
            Icon(Icons.edit_rounded,
                size: 15,
                color: isDark
                    ? Brand.darkTextTertiary
                    : Brand.subtleLight.withAlpha(102)),
        ]),
      ),
      if (!isLast)
        Divider(
            color: isDark ? Brand.darkBorder : Brand.borderLight, height: 14),
    ]);
  }

  Widget _buildQuickNav(bool isDark) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Row(children: [
                Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: isDark
                                ? [Brand.darkIconActive, Brand.royalBlueGlow]
                                : [Brand.royalBlue, Brand.royalBlueGlow],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter),
                        borderRadius: BorderRadius.circular(Brand.r(2)))),
                const SizedBox(width: 10),
                Text(S.of(context)!.profileQuickNav,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark)),
              ])),
          Row(children: [
            _navCard(
                Icons.precision_manufacturing_rounded,
                'My Machines',
                '$_totalMachines',
                isDark ? Brand.darkIconActive : Brand.royalBlue,
                isDark,
                () => CustomerNavController.switchTab(1)),
            const SizedBox(width: 10),
            _navCard(
                Icons.confirmation_num_rounded,
                'My Tickets',
                '$_openTickets open',
                isDark ? Brand.lightGreenBright : Brand.lightGreen,
                isDark,
                () => CustomerNavController.switchTab(2)),
            const SizedBox(width: 10),
            _navCard(
                Icons.auto_stories_rounded,
                'Guides',
                '',
                isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A),
                isDark,
                () => CustomerNavController.switchTab(3)),
          ]),
        ]));
  }

  Widget _navCard(IconData icon, String label, String count, Color c,
      bool isDark, VoidCallback onTap) {
    return Expanded(
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(Brand.r(18)),
                child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Brand.surface(isDark),
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        border: Border.all(
                            color: isDark ? Brand.darkBorder : c.withAlpha(20)),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                    color: c.withAlpha(13),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3))
                              ]),
                    child: Column(children: [
                      Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              color: c.withAlpha(isDark ? 26 : 20),
                              borderRadius: BorderRadius.circular(Brand.r(14)),
                              border: isDark
                                  ? Border.all(color: c.withAlpha(38))
                                  : null),
                          child: Icon(icon, color: c, size: 22)),
                      const SizedBox(height: 10),
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark),
                          textAlign: TextAlign.center),
                      if (count.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(count,
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight,
                                fontWeight: FontWeight.w500)),
                      ],
                    ])))));
  }

  // ── DOCUMENTS SECTION (Invoices + Quotations) ───────────────
  Widget _buildDocumentsSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(children: [
            Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: isDark
                            ? [Brand.darkIconActive, Brand.royalBlueGlow]
                            : [Brand.royalBlue, Brand.royalBlueGlow],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter),
                    borderRadius: BorderRadius.circular(Brand.r(2)))),
            const SizedBox(width: 10),
            Text(S.of(context)!.profileMyDocuments,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
          ]),
        ),
        _documentTile(
          isDark: isDark,
          icon: Icons.receipt_long_rounded,
          accent: isDark ? Brand.darkIconActive : Brand.royalBlue,
          title: S.of(context)!.profileMyInvoices,
          subtitle: S.of(context)!.profileMyInvoicesDesc,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyInvoicesPage()),
          ),
        ),
        const SizedBox(height: 12),
        _documentTile(
          isDark: isDark,
          icon: Icons.request_quote_rounded,
          accent: isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A),
          title: S.of(context)!.profileMyQuotations,
          subtitle: S.of(context)!.profileMyQuotationsDesc,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyQuotationsPage()),
          ),
        ),
        const SizedBox(height: 12),
        _documentTile(
          isDark: isDark,
          icon: Icons.payments_rounded,
          accent: isDark ? Brand.lightGreenBright : Brand.lightGreen,
          title: S.of(context)!.profileMyInstallments,
          subtitle: S.of(context)!.profileMyInstallmentsDesc,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CustomerInstallmentsPage()),
          ),
        ),
      ]),
    );
  }

  Widget _documentTile({
    required bool isDark,
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.r(20)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(20)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Brand.royalBlue.withAlpha(10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withAlpha(isDark ? 38 : 26),
                borderRadius: BorderRadius.circular(Brand.r(14)),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              size: 22,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildContactCard(bool isDark) {
    // Group contacts by type for display
    final callContacts =
        _supportContacts.where((c) => c['contact_type'] == 'call').toList();
    final whatsappContacts =
        _supportContacts.where((c) => c['contact_type'] == 'whatsapp').toList();
    final emailContacts =
        _supportContacts.where((c) => c['contact_type'] == 'email').toList();
    final webContacts =
        _supportContacts.where((c) => c['contact_type'] == 'web').toList();

    // Build contact button list — show all contacts grouped by type
    final List<Widget> contactWidgets = [];

    for (final c in callContacts) {
      contactWidgets.add(_contactBtn(
        Icons.phone_rounded,
        const Color(0xFF4CAF50),
        c['label'] as String? ?? 'Call',
        () => _launchUrl('tel:${c['value']}'),
        isDark,
      ));
    }
    for (final c in whatsappContacts) {
      contactWidgets.add(_contactBtn(
        Icons.chat_rounded,
        const Color(0xFF25D366),
        c['label'] as String? ?? 'WhatsApp',
        () => _launchUrl('https://wa.me/${c['value']}'),
        isDark,
      ));
    }
    for (final c in emailContacts) {
      contactWidgets.add(_contactBtn(
        Icons.email_rounded,
        isDark ? const Color(0xFFFF80AB) : const Color(0xFFE91E63),
        c['label'] as String? ?? 'Email',
        () => _launchUrl('mailto:${c['value']}'),
        isDark,
      ));
    }
    for (final c in webContacts) {
      contactWidgets.add(_contactBtn(
        Icons.public_rounded,
        isDark ? Brand.darkIconActive : Brand.royalBlue,
        c['label'] as String? ?? 'Web',
        () => _launchUrl(c['value'] as String? ?? ''),
        isDark,
      ));
    }

    // Fallback if DB contacts not loaded yet
    if (contactWidgets.isEmpty) {
      contactWidgets.addAll([
        _contactBtn(Icons.phone_rounded, const Color(0xFF4CAF50), 'Call',
            () => _launchUrl('tel:0777244882'), isDark),
        _contactBtn(
            Icons.email_rounded,
            isDark ? const Color(0xFFFF80AB) : const Color(0xFFE91E63),
            'Email',
            () => _launchUrl('mailto:marketing@ifrontiers.lk'),
            isDark),
        _contactBtn(
            Icons.public_rounded,
            isDark ? Brand.darkIconActive : Brand.royalBlue,
            'Web',
            () => _launchUrl('https://www.ifrontiers.lk'),
            isDark),
        _contactBtn(Icons.chat_rounded, const Color(0xFF25D366), 'WhatsApp',
            () => _launchUrl('https://wa.me/94777244882'), isDark),
      ]);
    }

    return Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(20),
        decoration: _cardDeco(isDark),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _sectionIcon(Icons.contact_support_rounded, isDark),
            const SizedBox(width: 10),
            Text(S.of(context)!.profileContactSupport,
                style: _sectionTitle(isDark)),
          ]),
          const SizedBox(height: 16),
          // Use Wrap for flexible layout when many contacts
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: contactWidgets,
          ),
        ]));
  }

  Widget _contactBtn(
      IconData icon, Color c, String label, VoidCallback onTap, bool isDark) {
    return SizedBox(
        width: 72,
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(Brand.r(14)),
                child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        color: c.withAlpha(isDark ? 26 : 15),
                        borderRadius: BorderRadius.circular(Brand.r(14)),
                        border:
                            Border.all(color: c.withAlpha(isDark ? 38 : 31))),
                    child: Column(children: [
                      Icon(icon, color: c, size: 22),
                      const SizedBox(height: 4),
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              color: c,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          textAlign: TextAlign.center),
                    ])))));
  }

  // ── THEME SELECTOR ──────────────────────────────────────────
  Widget _buildThemeSelector(bool isDark) {
    final t = S.of(context)!;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentIsDark = themeProvider.isDarkMode;

    return Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(20),
        decoration: _cardDeco(isDark),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _sectionIcon(Icons.palette_rounded, isDark),
            const SizedBox(width: 10),
            Expanded(
                child: Text(S.of(context)!.profileAppearance,
                    style: _sectionTitle(isDark))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlue.withAlpha(26),
                    borderRadius: BorderRadius.circular(Brand.r(8)),
                    border: isDark
                        ? Border.all(color: Brand.darkBorderLight)
                        : null),
                child: Text(
                    currentIsDark
                        ? S.of(context)!.profileDark
                        : S.of(context)!.profileLight,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Brand.darkIconActive : Brand.royalBlue))),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _themeOption(
              icon: Icons.light_mode_rounded,
              label: 'Light',
              isSelected: !currentIsDark,
              isDark: isDark,
              gradientColors: [const Color(0xFFF0F2FB), Colors.white],
              onTap: () {
                HapticFeedback.selectionClick();
                themeProvider.setDarkMode(false);
              },
            ),
            const SizedBox(width: 10),
            _themeOption(
              icon: Icons.dark_mode_rounded,
              label: t.settingsDarkMode,
              isSelected: currentIsDark,
              isDark: isDark,
              gradientColors: [Brand.darkBg, Brand.darkCard],
              onTap: () {
                HapticFeedback.selectionClick();
                themeProvider.setDarkMode(true);
              },
            ),
          ]),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              ThemeStyleSheet.show(context);
            },
            borderRadius: BorderRadius.circular(Brand.r(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(Brand.r(12)),
                border: Border.all(
                    color: isDark ? Brand.darkBorderLight : Brand.borderLight),
              ),
              child: Row(children: [
                Icon(Icons.style_rounded,
                    size: 18,
                    color: isDark ? Brand.darkIconActive : Brand.royalBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Dark style',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.textPrimaryLight)),
                ),
                Text(ThemeProvider.styleName(themeProvider.darkStyle),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.textSecondaryLight)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 18,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
              ]),
            ),
          ),
        ]));
  }

  Widget _themeOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required bool isDark,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Expanded(
        child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? Brand.darkIconActive.withAlpha(26)
                      : Brand.royalBlue.withAlpha(15))
                  : (isDark
                      ? Brand.darkCardElevated
                      : Brand.royalBlueSurface.withAlpha(128)),
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: Border.all(
                  color: isSelected
                      ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                      : (isDark ? Brand.darkBorder : Brand.borderLight),
                  width: isSelected ? 2 : 1)),
          child: Column(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isSelected
                            ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                            : Colors.transparent,
                        width: 2)),
                child: isSelected
                    ? Icon(Icons.check_rounded,
                        color:
                            isDark ? Brand.lightGreenBright : Brand.royalBlue,
                        size: 20)
                    : null),
            const SizedBox(height: 8),
            Icon(icon,
                color: isSelected
                    ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                    : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
                size: 18),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? (isDark ? Brand.darkIconActive : Brand.royalBlue)
                        : (isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight)),
                textAlign: TextAlign.center),
          ])),
    ));
  }

  Widget _buildSettings(bool isDark) {
    final t = S.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context);

    return Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: _cardDeco(isDark),
        child: Column(children: [
          _settingItem(
              Icons.notifications_rounded,
              'Notifications',
              _unreadNotifications > 0
                  ? '$_unreadNotifications unread'
                  : 'Manage alerts',
              isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800),
              isDark, () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationListPage()));
            if (!mounted) return;
            _loadProfile();
          }, badge: _unreadNotifications > 0 ? '$_unreadNotifications' : null),
          _sDivider(isDark),
          _settingItem(
              Icons.lock_rounded,
              'Change Password',
              'Reset via email link',
              isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A),
              isDark,
              _changePassword),
          _sDivider(isDark),
          _settingItem(
              Icons.share_rounded,
              'Share App',
              'Invite colleagues',
              isDark ? Brand.lightGreenBright : Brand.lightGreen,
              isDark,
              _shareApp),
          _sDivider(isDark),
          // ── Language selector tile (i18n) ──────────────────
          _settingItem(
            Icons.translate_rounded,
            t.settingsLanguage,
            localeProvider.currentLanguageName,
            isDark ? Brand.darkIconActive : Brand.royalBlueLight,
            isDark,
            () => showLanguageSelector(context),
            trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlue.withAlpha(26),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                    border: isDark
                        ? Border.all(color: Brand.darkBorderLight)
                        : null),
                child: Text(localeProvider.locale.languageCode.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Brand.darkIconActive : Brand.royalBlue))),
          ),
          _sDivider(isDark),
          _settingItem(
              Icons.description_rounded,
              'Terms & Conditions',
              'Read our terms',
              const Color(0xFF795548),
              isDark,
              () => _showInfoPage('Terms & Conditions')),
          _sDivider(isDark),
          _settingItem(
              Icons.privacy_tip_rounded,
              'Privacy Policy',
              'Your data protection',
              isDark ? const Color(0xFFCE93D8) : const Color(0xFF9C27B0),
              isDark,
              () => _showInfoPage('Privacy Policy')),
          _sDivider(isDark),
          _settingItem(
              Icons.info_rounded,
              'About iFrontiers Connect',
              'Version 1.0.0',
              isDark ? Brand.darkIconActive : Brand.royalBlue,
              isDark,
              _showAboutAppDialog),
        ]));
  }

  Widget _settingItem(IconData icon, String label, String sub, Color c,
      bool isDark, VoidCallback onTap,
      {Widget? trailing, String? badge}) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                          color: c.withAlpha(isDark ? 26 : 20),
                          borderRadius: BorderRadius.circular(Brand.r(12)),
                          border: isDark
                              ? Border.all(color: c.withAlpha(31))
                              : null),
                      child: Stack(children: [
                        Center(child: Icon(icon, color: c, size: 21)),
                        if (badge != null)
                          Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle),
                                  child: Text(badge,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)))),
                      ])),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark)),
                        const SizedBox(height: 2),
                        Text(sub,
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextSecondary
                                    : Brand.subtleLight)),
                      ])),
                  trailing ??
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight.withAlpha(102)),
                ]))));
  }

  Widget _sDivider(bool isDark) => Padding(
      padding: const EdgeInsets.only(left: 72),
      child: Divider(
          color: isDark ? Brand.darkBorder : Brand.borderLight, height: 1));

  Widget _buildDangerZone(bool isDark) {
    return Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(22)),
            border: Border.all(color: Colors.red.withAlpha(isDark ? 38 : 26))),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color:
                        isDark ? const Color(0xFFFF6B6B) : Colors.red.shade300,
                    size: 18),
                const SizedBox(width: 8),
                Text('Account',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFFF6B6B)
                            : Colors.red.shade300)),
              ])),
          _settingItem(
              Icons.download_rounded,
              'Export My Data',
              'Download a copy of your data',
              isDark ? Brand.darkIconActive : Brand.royalBlueLight,
              isDark,
              _exportData),
          _sDivider(isDark),
          _settingItem(
              Icons.person_off_rounded,
              'Deactivate Account',
              'Temporarily disable your account',
              isDark ? const Color(0xFFFF6B6B) : Colors.red,
              isDark,
              _deactivateAccount),
        ]));
  }

  Widget _buildLogoutBtn(bool isDark) {
    final t = S.of(context)!;
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                onTap: _logout,
                borderRadius: BorderRadius.circular(Brand.r(18)),
                child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                        color: Brand.surface(isDark),
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                        border: Border.all(
                            color: Colors.red.withAlpha(isDark ? 64 : 51),
                            width: 1.5)),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded,
                              color: isDark
                                  ? const Color(0xFFFF6B6B)
                                  : Colors.red.shade400,
                              size: 22),
                          const SizedBox(width: 10),
                          Text(t.authLogout,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFFFF6B6B)
                                      : Colors.red.shade400)),
                        ])))));
  }

  Widget _buildVersion(bool isDark) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Column(children: [
          Text('iFrontiers Connect v1.0.0',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Brand.darkTextTertiary
                      : Brand.subtleLight.withAlpha(128))),
          const SizedBox(height: 4),
          Text('© ${DateTime.now().year} iFrontiers (Pvt) Ltd',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Brand.darkTextTertiary.withAlpha(153)
                      : Brand.subtleLight.withAlpha(102))),
        ]));
  }

  // ── Shared Decorations ──────────────────────────────────────
  BoxDecoration _cardDeco(bool isDark) => BoxDecoration(
      color: Brand.surface(isDark),
      borderRadius: BorderRadius.circular(Brand.r(22)),
      border: isDark ? Border.all(color: Brand.darkBorder) : null,
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ]);

  Widget _sectionIcon(IconData icon, bool isDark) => Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
          borderRadius: BorderRadius.circular(Brand.r(12)),
          border: isDark ? Border.all(color: Brand.darkBorderLight) : null),
      child: Icon(icon,
          color: isDark ? Brand.darkIconActive : Brand.royalBlue, size: 22));

  TextStyle _sectionTitle(bool isDark) => TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark);

  Widget _dialogBtn(String text, Color border, Color textColor, bool filled,
      VoidCallback onTap) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
                color: filled ? border : null,
                border: filled ? null : Border.all(color: border, width: 1.5),
                borderRadius: BorderRadius.circular(Brand.r(14))),
            child: Center(
                child: Text(text,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        fontSize: 15)))));
  }

  Widget _confirmDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
    String cancelText = 'Cancel',
  }) {
    final isDark = _isDark;
    return Dialog(
        backgroundColor: Brand.surface(isDark),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.r(24))),
        child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                      color: iconColor.withAlpha(isDark ? 31 : 26),
                      borderRadius: BorderRadius.circular(Brand.r(20)),
                      border: isDark
                          ? Border.all(color: iconColor.withAlpha(38))
                          : null),
                  child: Icon(icon, color: iconColor, size: 34)),
              const SizedBox(height: 20),
              Text(title,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark)),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      height: 1.5)),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                    child: _dialogBtn(
                        cancelText,
                        isDark ? Brand.darkBorderLight : Brand.borderLight,
                        isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                        false,
                        () => Navigator.pop(context, false))),
                const SizedBox(width: 12),
                Expanded(
                    child: _dialogBtn(confirmText, confirmColor, Colors.white,
                        true, () => Navigator.pop(context, true))),
              ]),
            ])));
  }

  Widget _buildImageSourceSheet(bool isDark) {
    return Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: isDark
                      ? Brand.darkTextTertiary
                      : Brand.subtleLight.withAlpha(77),
                  borderRadius: BorderRadius.circular(Brand.r(2)))),
          const SizedBox(height: 20),
          Text('Change Profile Photo',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
          const SizedBox(height: 20),
          _sheetItem(
              Icons.photo_camera_rounded,
              'Take a Photo',
              'Use your camera',
              isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
              isDark ? Brand.darkIconActive : Brand.royalBlue,
              isDark,
              () => Navigator.pop(context, 'camera')),
          Padding(
              padding: const EdgeInsets.only(left: 70),
              child: Divider(
                  color: isDark ? Brand.darkBorder : Brand.borderLight)),
          _sheetItem(
              Icons.photo_library_rounded,
              'Choose from Gallery',
              'Select existing photo',
              Brand.lightGreen.withAlpha(isDark ? 26 : 20),
              isDark ? Brand.lightGreenBright : Brand.lightGreen,
              isDark,
              () => Navigator.pop(context, 'gallery')),
          if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) ...[
            Padding(
                padding: const EdgeInsets.only(left: 70),
                child: Divider(
                    color: isDark ? Brand.darkBorder : Brand.borderLight)),
            _sheetItem(
                Icons.delete_outline_rounded,
                'Remove Photo',
                'Use initials instead',
                Colors.red.withAlpha(isDark ? 26 : 26),
                isDark ? const Color(0xFFFF6B6B) : Colors.red.shade400,
                isDark,
                () => Navigator.pop(context, 'remove')),
          ],
          const SizedBox(height: 16),
        ]));
  }

  Widget _sheetItem(IconData icon, String title, String sub, Color bg, Color ic,
      bool isDark, VoidCallback onTap) {
    return ListTile(
        leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(Brand.r(14)),
                border: isDark ? Border.all(color: ic.withAlpha(31)) : null),
            child: Icon(icon, color: ic, size: 24)),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark)),
        subtitle: Text(sub,
            style: TextStyle(
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontSize: 12)),
        onTap: onTap);
  }

  void _showInfoPage(String title) {
    final isDark = _isDark;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            builder: (context, sc) => Container(
                decoration: BoxDecoration(
                    color: Brand.surface(isDark),
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(Brand.r(24)))),
                child: Column(children: [
                  const SizedBox(height: 12),
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight.withAlpha(77),
                          borderRadius: BorderRadius.circular(Brand.r(2)))),
                  const SizedBox(height: 20),
                  Text(title,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark)),
                  const SizedBox(height: 16),
                  Expanded(
                      child: SingleChildScrollView(
                          controller: sc,
                          padding: const EdgeInsets.all(20),
                          child: Text(
                              'Content for $title will be available soon.\n\niFrontiers (Pvt) Ltd is committed to protecting your privacy.\n\nFor questions, contact us at marketing@ifrontiers.lk',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Brand.darkTextSecondary
                                      : Brand.subtleLight,
                                  height: 1.6)))),
                ]))));
  }

  void _showAboutAppDialog() {
    final isDark = _isDark;
    showDialog(
        context: context,
        builder: (context) => Dialog(
            backgroundColor: Brand.surface(isDark),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Brand.r(24))),
            child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(Brand.r(16)),
                      child: const AppLogo.mark(height: 56, width: 56)),
                  const SizedBox(height: 16),
                  Text('iFrontiers Connect',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark)),
                  const SizedBox(height: 4),
                  Text('The Customer Companion App',
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              isDark ? Brand.darkIconActive : Brand.royalBlue,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Text(
                      'Version 1.0.0\n\nStay Connected. Stay Informed. Stay Ahead.\n\n© ${DateTime.now().year} iFrontiers (Pvt) Ltd\nAll rights reserved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                          height: 1.5)),
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? Brand.darkIconActive
                                  : Brand.royalBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(Brand.r(14)))),
                          child: const Text('Close'))),
                ]))));
  }
}

class _Stat {
  final Widget Function(Color) iconWidget;
  final String value;
  final String label;
  final Color color;
  const _Stat(this.iconWidget, this.value, this.label, this.color);
}
