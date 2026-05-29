// lib/screens/admin/broadcast_notifications.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../utils/time_utils.dart';

class BroadcastNotificationsPage extends StatefulWidget {
  const BroadcastNotificationsPage({super.key});

  @override
  State<BroadcastNotificationsPage> createState() =>
      _BroadcastNotificationsPageState();
}

class _BroadcastNotificationsPageState extends State<BroadcastNotificationsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Broadcast Tab ──
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _audience = 'all_customers';
  String? _selectedCategory;
  bool _isSending = false;
  bool _isLoadingHistory = true;
  List<Map<String, dynamic>> _history = [];
  List<String> _machineCategories = [];
  int _recipientCount = 0;
  bool _recipientLoading = false;
  // M4: Tracks whether the last count query errored out, so the UI can
  // distinguish "genuinely empty audience" from "we don't know" and the send
  // button can block broadcasts when the count is untrusted.
  bool _recipientError = false;

  // ── Promotions Tab ──
  List<Map<String, dynamic>> _banners = [];
  bool _loadingBanners = true;

  // ── Constants ──
  static const _audiences = [
    (
      'all_customers',
      'All Customers',
      Icons.people_rounded,
      Brand.royalBlue,
    ),
    (
      'all_engineers',
      'All Engineers',
      Icons.engineering_rounded,
      Color(0xFF00B4D8),
    ),
    (
      'all_users',
      'Everyone',
      Icons.groups_rounded,
      Brand.lightGreen,
    ),
    (
      'specific_machine',
      'By Machine Category',
      Icons.precision_manufacturing_rounded,
      Color(0xFFFF9800),
    ),
  ];

  static const _seasonTags = [
    (
      'new_year',
      'New Year',
      Icons.celebration_rounded,
      Color(0xFFE91E63),
    ),
    (
      'holiday',
      'Holiday',
      Icons.card_giftcard_rounded,
      Color(0xFFE53935),
    ),
    (
      'mid_year',
      'Mid-Year',
      Icons.local_offer_rounded,
      Color(0xFFFF9800),
    ),
    (
      'special',
      'Special',
      Icons.star_rounded,
      Color(0xFF9C27B0),
    ),
  ];

  static const _linkTypes = [
    ('none', 'No Link'),
    ('machine', 'Machine Detail'),
    ('catalog', 'Catalog Category'),
    ('url', 'External URL'),
  ];

  // ── Const color aliases ──
  static const _redColor = Color(0xFFE53935);
  static const _redLight = Color(0xFFEF5350); // shade400
  static const _greyColor = Color(0xFF607D8B);
  static const _orangeColor = Color(0xFFFF9800);
  static const _greyDark = Color(0xFF455A64); // shade700

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Defense-in-depth: verify admin role before loading any data.
    // RLS still enforces authorization on the backend; this guards the UI.
    _guardAdminRole().then((isAdmin) {
      if (!mounted || !isAdmin) return;
      _loadHistory();
      _loadMachineCategories();
      _updateRecipientCount();
      _loadBanners();
    });
  }

  /// Verifies the current user has role='admin'. Pops and shows a message
  /// if not, so non-admins can never reach this screen even if the route
  /// is exposed. Returns true if the user is confirmed as admin.
  Future<bool> _guardAdminRole() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) Navigator.of(context).maybePop();
      return false;
    }
    try {
      final row = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      final role = row?['role'] as String?;
      if (role != 'admin') {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin access required.')),
        );
        Navigator.of(context).maybePop();
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ Admin role check failed: $e');
      if (mounted) Navigator.of(context).maybePop();
      return false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  //  BROADCAST — DATA
  // ════════════════════════════════════════════════════════

  Future<void> _loadHistory() async {
    // FIX: added mounted check
    if (!mounted) return;
    try {
      final data = await SupabaseConfig.client
          .from('notifications')
          .select('title, body, type, created_at')
          .eq('type', 'broadcast')
          .order('created_at', ascending: false)
          .limit(50);

      if (!mounted) return;

      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final n in data as List) {
        final key =
            '${n['title']}|${n['body']}|${(n['created_at'] as String).substring(0, 16)}';
        if (!seen.contains(key)) {
          seen.add(key);
          unique.add(Map<String, dynamic>.from(n));
        }
      }

      setState(() {
        _history = unique;
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('Error loading broadcast history: $e');
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _loadMachineCategories() async {
    try {
      final data = await SupabaseConfig.client
          .from('machine_catalog')
          .select('category')
          .eq('is_active', true)
          .order('category');

      if (!mounted) return;

      final categories = <String>{};
      for (final row in data as List) {
        if (row['category'] != null) {
          categories.add(row['category'] as String);
        }
      }
      setState(
        () => _machineCategories = categories.toList(),
      );
    } catch (e) {
      debugPrint('Error loading machine categories: $e');
    }
  }

  Future<void> _updateRecipientCount() async {
    if (!mounted) return;
    setState(() => _recipientLoading = true);

    // M4: Use `-1` as an error sentinel so a failed query doesn't collapse to
    // "0 recipients" and mask the failure — the UI uses _recipientError to
    // distinguish "genuinely empty audience" from "count query failed".
    int count = -1;
    try {
      switch (_audience) {
        case 'all_customers':
          final res = await SupabaseConfig.client
              .from('users')
              .select('id')
              .eq('role', 'customer');
          count = (res as List).length;
          break;
        case 'all_engineers':
          final res = await SupabaseConfig.client
              .from('users')
              .select('id')
              .eq('role', 'engineer');
          count = (res as List).length;
          break;
        case 'all_users':
          final res = await SupabaseConfig.client
              .from('users')
              .select('id')
              .neq('role', 'admin');
          count = (res as List).length;
          break;
        case 'specific_machine':
          if (_selectedCategory != null) {
            final res = await SupabaseConfig.client
                .from('customer_machines')
                .select(
                  'user_id, machine_catalog!inner(category)',
                )
                .eq(
                  'machine_catalog.category',
                  _selectedCategory!,
                );
            final userIds = <String>{};
            for (final row in res as List) {
              userIds.add(row['user_id'] as String);
            }
            count = userIds.length;
          } else {
            // No category chosen yet — that's a valid empty audience, not
            // an error.
            count = 0;
          }
          break;
      }

      if (!mounted) return;
      setState(() {
        _recipientCount = count;
        _recipientError = false;
        _recipientLoading = false;
      });
    } catch (e) {
      debugPrint('Error counting recipients: $e');
      if (!mounted) return;
      setState(() {
        // Keep the previous count visually, but flag the error so the
        // send button / hint text can reflect "count unknown".
        _recipientError = true;
        _recipientLoading = false;
      });
    }
  }

  // ════════════════════════════════════════════════════════
  //  BROADCAST — SEND
  // ════════════════════════════════════════════════════════

  Future<void> _sendBroadcast() async {
    final title = _titleCtrl.text.trim();
    final msgBody = _bodyCtrl.text.trim();

    if (title.isEmpty) {
      _snack('Please enter a title', isError: true);
      return;
    }
    if (msgBody.isEmpty) {
      _snack('Please enter a message body', isError: true);
      return;
    }
    if (_audience == 'specific_machine' && _selectedCategory == null) {
      _snack(
        'Please select a machine category',
        isError: true,
      );
      return;
    }
    // M4: Refuse to send if we couldn't count the audience — otherwise we'd
    // either spam everyone or silently drop the broadcast.
    if (_recipientError) {
      _snack(
        'Could not verify recipients. Please retry.',
        isError: true,
      );
      return;
    }
    if (_recipientCount <= 0) {
      _snack(
        'No recipients found for this audience',
        isError: true,
      );
      return;
    }

    final confirmed = await _showConfirmDialog(title, msgBody);
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _isSending = true);

    try {
      // ── Step 1: Get user IDs ──
      List<String> userIds = [];
      switch (_audience) {
        case 'all_customers':
          final res = await SupabaseConfig.client
              .from('users')
              .select('id')
              .eq('role', 'customer');
          userIds = (res as List).map((r) => r['id'] as String).toList();
          break;
        case 'all_engineers':
          final res = await SupabaseConfig.client
              .from('users')
              .select('id')
              .eq('role', 'engineer');
          userIds = (res as List).map((r) => r['id'] as String).toList();
          break;
        case 'all_users':
          final res = await SupabaseConfig.client
              .from('users')
              .select('id')
              .neq('role', 'admin');
          userIds = (res as List).map((r) => r['id'] as String).toList();
          break;
        case 'specific_machine':
          final res = await SupabaseConfig.client
              .from('customer_machines')
              .select(
                'user_id, machine_catalog!inner(category)',
              )
              .eq(
                'machine_catalog.category',
                _selectedCategory!,
              );
          final ids = <String>{};
          for (final row in res as List) {
            ids.add(row['user_id'] as String);
          }
          userIds = ids.toList();
          break;
      }

      if (!mounted) return;

      if (userIds.isEmpty) {
        _snack('No recipients found', isError: true);
        setState(() => _isSending = false);
        return;
      }

      // ── Step 2: Insert notification rows ──
      final now = DateTime.now().toIso8601String();
      final allRows = userIds
          .map((uid) => {
                'user_id': uid,
                'title': title,
                'body': msgBody,
                'type': 'broadcast',
                'is_read': false,
                'created_at': now,
              })
          .toList();

      for (var i = 0; i < allRows.length; i += 100) {
        await SupabaseConfig.client.from('notifications').insert(
              allRows.sublist(
                i,
                (i + 100) > allRows.length ? allRows.length : i + 100,
              ),
            );
        if (!mounted) return;
      }

      // ── Step 3: Send FCM push via Edge Function ──
      int pushSent = 0;
      int pushTotal = 0;
      String? pushError;

      try {
        final pushRes = await SupabaseConfig.client.functions.invoke(
          'send-push',
          body: {
            'title': title,
            'body': msgBody,
            'audience': _audience,
            if (_audience == 'specific_machine' && _selectedCategory != null)
              'category': _selectedCategory,
          },
        );

        final pushData = pushRes.data;
        if (pushData is Map<String, dynamic>) {
          pushSent = (pushData['sent'] as num?)?.toInt() ?? 0;
          pushTotal = (pushData['total_tokens'] as num?)?.toInt() ?? 0;
          if (pushData['error'] != null) {
            pushError = pushData['error'].toString();
          }
        }
      } catch (e) {
        try {
          final dynamic ex = e;
          pushError = 'Status ${ex.status}: ${ex.details}';
        } catch (_) {
          pushError = e.toString();
        }
        debugPrint(
          'FCM push call failed (notifications saved): $pushError',
        );
      }

      _titleCtrl.clear();
      _bodyCtrl.clear();
      await _loadHistory();

      if (!mounted) return;
      setState(() => _isSending = false);

      if (pushError != null && pushTotal == 0) {
        final shortErr = pushError.length > 100
            ? '${pushError.substring(0, 100)}...'
            : pushError;
        _snack('Push error: $shortErr', isError: true);
      } else if (pushTotal > 0) {
        _snack(
          'Broadcast sent to ${userIds.length} · $pushSent/$pushTotal push delivered',
        );
      } else {
        _snack(
          'Broadcast sent to ${userIds.length} recipients (in-app only)',
        );
      }
    } catch (e) {
      debugPrint('Broadcast send error: $e');
      if (!mounted) return;
      setState(() => _isSending = false);
      _snack(
        'Failed to send broadcast: $e',
        isError: true,
      );
    }
  }

  // ════════════════════════════════════════════════════════
  //  CONFIRM DIALOG
  // ════════════════════════════════════════════════════════

  Future<bool> _showConfirmDialog(
    String title,
    String body,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  // FIX: replaced .withOpacity() with .withAlpha()
                  // 0.12 ≈ 31 alpha, 0.08 ≈ 20 alpha
                  color: Brand.royalBlue.withAlpha(
                    isDark ? 31 : 20,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Confirm Broadcast',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                  borderRadius: BorderRadius.circular(14),
                  border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.people_rounded,
                    size: 16,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$_recipientCount recipients will receive this',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    size: 14,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'In-app + push notification will be sent',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogCtx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Brand.darkBorderLight
                                : Brand.borderLight,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
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
                      onTap: () => Navigator.pop(dialogCtx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Brand.royalBlueDark,
                              Brand.royalBlue,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Brand.royalBlue.withAlpha(89),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Send',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  // ════════════════════════════════════════════════════════
  //  PROMOTIONS — DATA
  // ════════════════════════════════════════════════════════

  Future<void> _loadBanners() async {
    if (!mounted) return;
    setState(() => _loadingBanners = true);
    try {
      final data = await SupabaseConfig.client
          .from('promotional_banners')
          .select()
          .order('display_order', ascending: false)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _banners = List<Map<String, dynamic>>.from(data as List);
        _loadingBanners = false;
      });
    } catch (e) {
      debugPrint('Error loading banners: $e');
      if (!mounted) return;
      setState(() => _loadingBanners = false);
    }
  }

  Future<void> _toggleBannerActive(
    String id,
    bool active,
  ) async {
    try {
      await SupabaseConfig.client.from('promotional_banners').update({
        'is_active': active,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      if (!mounted) return;
      setState(() {
        final idx = _banners.indexWhere((b) => b['id'] == id);
        if (idx != -1) {
          // FIX: use spread copy instead of direct mutation
          _banners[idx] = {
            ..._banners[idx],
            'is_active': active,
          };
        }
      });
      _snack(active ? 'Banner activated' : 'Banner deactivated');
    } catch (e) {
      _snack('Failed to update banner', isError: true);
    }
  }

  Future<void> _deleteBanner(String id) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  // FIX: replaced .withOpacity() with .withAlpha()
                  // 0.15 ≈ 38 alpha, 0.08 ≈ 20 alpha
                  color: _redColor.withAlpha(
                    isDark ? 38 : 20,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  // FIX: replaced Colors.red.shade400
                  color: _redLight,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Delete Banner?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This action cannot be undone.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogCtx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                isDark ? Brand.darkBorder : Brand.borderLight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
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
                      onTap: () => Navigator.pop(dialogCtx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _redColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Delete',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await SupabaseConfig.client
          .from('promotional_banners')
          .delete()
          .eq('id', id);

      if (!mounted) return;
      setState(
        () => _banners.removeWhere((b) => b['id'] == id),
      );
      _snack('Banner deleted');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to delete banner', isError: true);
    }
  }

  Future<String?> _uploadBannerImage(File file) async {
    try {
      final ext = file.path.split('.').last;
      final path = 'banners/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await SupabaseConfig.client.storage
          .from('promotional-banners')
          .upload(path, file);

      return SupabaseConfig.client.storage
          .from('promotional-banners')
          .getPublicUrl(path);
    } catch (e) {
      debugPrint('Banner image upload error: $e');
      return null;
    }
  }

  String _getBannerStatus(Map<String, dynamic> banner) {
    if (banner['is_active'] != true) return 'inactive';
    final now = DateTime.now();
    final start = banner['start_date'] != null
        ? DateTime.tryParse(
            banner['start_date'].toString(),
          )
        : null;
    final end = banner['end_date'] != null
        ? DateTime.tryParse(banner['end_date'].toString())
        : null;
    if (start != null && start.isAfter(now)) {
      return 'scheduled';
    }
    if (end != null && end.isBefore(now)) return 'expired';
    return 'active';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Brand.lightGreen;
      case 'scheduled':
        return const Color(0xFF2196F3);
      case 'expired':
        return _redColor;
      case 'inactive':
        // FIX: replaced Colors.grey with const
        return _greyColor;
      default:
        return _greyColor;
    }
  }

  // ── Banner Editor Bottom Sheet ──
  void _showBannerEditor({Map<String, dynamic>? existing}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = existing != null;

    // Controllers — disposed in finally block
    final eTitleCtrl = TextEditingController(
      text: existing?['title'] ?? '',
    );
    final eSubtitleCtrl = TextEditingController(
      text: existing?['subtitle'] ?? '',
    );
    final eLinkValueCtrl = TextEditingController(
      text: existing?['link_value'] ?? '',
    );
    final eOrderCtrl = TextEditingController(
      text: (existing?['display_order'] ?? 0).toString(),
    );

    File? imageFile;
    String? existingImageUrl = existing?['image_url'];
    String linkType = existing?['link_type'] ?? 'none';
    String? seasonTag = existing?['season_tag'];
    bool isActive = existing?['is_active'] ?? true;
    DateTime? startDate = existing?['start_date'] != null
        ? DateTime.tryParse(
            existing!['start_date'].toString(),
          )
        : null;
    DateTime? endDate = existing?['end_date'] != null
        ? DateTime.tryParse(
            existing!['end_date'].toString(),
          )
        : null;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          Future<void> pickImage() async {
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1920,
              maxHeight: 1080,
              imageQuality: 85,
            );
            if (picked != null) {
              setSheet(() => imageFile = File(picked.path));
            }
          }

          Future<void> pickDate(bool isStart) async {
            final picked = await showDatePicker(
              context: sheetCtx,
              initialDate: (isStart ? startDate : endDate) ?? DateTime.now(),
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: isDark
                      ? const ColorScheme.dark(
                          primary: Brand.darkIconActive,
                          surface: Brand.darkCard,
                          onSurface: Brand.darkTextPrimary,
                        )
                      : const ColorScheme.light(
                          primary: Brand.royalBlue,
                        ),
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              setSheet(() {
                if (isStart) {
                  startDate = picked;
                } else {
                  endDate = picked;
                }
              });
            }
          }

          Future<void> save() async {
            final title = eTitleCtrl.text.trim();
            if (title.isEmpty) {
              _snack('Title is required', isError: true);
              return;
            }
            if (imageFile == null && existingImageUrl == null) {
              _snack(
                'Please upload a banner image',
                isError: true,
              );
              return;
            }

            setSheet(() => isSaving = true);

            try {
              String? imageUrl = existingImageUrl;
              if (imageFile != null) {
                imageUrl = await _uploadBannerImage(imageFile!);
                if (imageUrl == null) {
                  setSheet(() => isSaving = false);
                  _snack(
                    'Image upload failed',
                    isError: true,
                  );
                  return;
                }
              }

              final userId = SupabaseConfig.client.auth.currentUser?.id;
              final record = {
                'title': title,
                'subtitle': eSubtitleCtrl.text.trim().isEmpty
                    ? null
                    : eSubtitleCtrl.text.trim(),
                'image_url': imageUrl,
                'link_type': linkType,
                'link_value': eLinkValueCtrl.text.trim().isEmpty
                    ? null
                    : eLinkValueCtrl.text.trim(),
                'is_active': isActive,
                'display_order': int.tryParse(eOrderCtrl.text) ?? 0,
                'start_date': startDate != null
                    ? '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}'
                    : null,
                'end_date': endDate != null
                    ? '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}'
                    : null,
                'season_tag': seasonTag,
                'updated_at': DateTime.now().toIso8601String(),
              };

              if (isEditing) {
                await SupabaseConfig.client
                    .from('promotional_banners')
                    .update(record)
                    .eq('id', existing['id']);
              } else {
                final insertRecord = {
                  ...record,
                  'created_by': userId,
                };
                await SupabaseConfig.client
                    .from('promotional_banners')
                    .insert(insertRecord);
              }

              await _loadBanners();

              // FIX: check sheetCtx.mounted before pop
              if (!sheetCtx.mounted) return;
              Navigator.pop(sheetCtx);

              if (!mounted) return;
              _snack(
                isEditing ? 'Banner updated' : 'Banner created',
              );
            } catch (e) {
              if (sheetCtx.mounted) {
                setSheet(() => isSaving = false);
              }
              _snack('Failed to save: $e', isError: true);
            } finally {
              // FIX: dispose controllers
              eTitleCtrl.dispose();
              eSubtitleCtrl.dispose();
              eLinkValueCtrl.dispose();
              eOrderCtrl.dispose();
            }
          }

          String fmtDate(DateTime? d) {
            if (d == null) return 'Not set';
            const m = [
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
              'Dec',
            ];
            return '${m[d.month - 1]} ${d.day}, ${d.year}';
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.9,
              ),
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.cardLight,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle + Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      24,
                      14,
                      24,
                      0,
                    ),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              // FIX: replaced Colors.grey.shade300
                              color: isDark
                                  ? Brand.darkBorderLight
                                  : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                // FIX: replaced .withOpacity() with .withAlpha()
                                color: Brand.royalBlue.withAlpha(
                                  isDark ? 31 : 20,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isEditing
                                    ? Icons.edit_rounded
                                    : Icons.add_photo_alternate_rounded,
                                color: isDark
                                    ? Brand.royalBlueGlow
                                    : Brand.royalBlue,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              isEditing ? 'Edit Banner' : 'Create Banner',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Scrollable form
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        0,
                        24,
                        24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Image ──
                          _editorLabel(
                            'Banner Image *',
                            isDark,
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: pickImage,
                            child: Container(
                              height: 180,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Brand.darkCardElevated
                                    : Brand.scaffoldLight,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark
                                      ? Brand.darkBorder
                                      : Brand.borderLight,
                                ),
                              ),
                              child: imageFile != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.file(
                                        imageFile!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                      ),
                                    )
                                  : existingImageUrl != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: CachedNetworkImage(
                                            imageUrl: existingImageUrl,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            placeholder: (_, __) =>
                                                _imagePlaceholder(isDark),
                                            errorWidget: (_, __, ___) =>
                                                _imagePlaceholder(isDark),
                                          ),
                                        )
                                      : _imagePlaceholder(isDark),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // ── Title ──
                          _editorLabel('Title *', isDark),
                          const SizedBox(height: 8),
                          _editorField(
                            eTitleCtrl,
                            'Banner title',
                            isDark,
                          ),
                          const SizedBox(height: 14),

                          // ── Subtitle ──
                          _editorLabel('Subtitle', isDark),
                          const SizedBox(height: 8),
                          _editorField(
                            eSubtitleCtrl,
                            'Optional subtitle',
                            isDark,
                          ),
                          const SizedBox(height: 18),

                          // ── Date Range ──
                          _editorLabel(
                            'Display Period',
                            isDark,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _dateChip(
                                  'Start',
                                  fmtDate(startDate),
                                  () => pickDate(true),
                                  isDark,
                                  onClear: startDate != null
                                      ? () => setSheet(
                                            () => startDate = null,
                                          )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _dateChip(
                                  'End',
                                  fmtDate(endDate),
                                  () => pickDate(false),
                                  isDark,
                                  onClear: endDate != null
                                      ? () => setSheet(
                                            () => endDate = null,
                                          )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // ── Season Tag ──
                          _editorLabel(
                            'Season Tag',
                            isDark,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _tagChip(
                                null,
                                'None',
                                Icons.block_rounded,
                                _greyColor,
                                seasonTag == null,
                                () => setSheet(
                                  () => seasonTag = null,
                                ),
                                isDark,
                              ),
                              ..._seasonTags.map(
                                (s) => _tagChip(
                                  s.$1,
                                  s.$2,
                                  s.$3,
                                  s.$4,
                                  seasonTag == s.$1,
                                  () => setSheet(
                                    () => seasonTag = s.$1,
                                  ),
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // ── Link ──
                          _editorLabel(
                            'Link Action',
                            isDark,
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: linkType,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: isDark
                                  ? Brand.darkCardElevated
                                  : Brand.scaffoldLight,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            dropdownColor: isDark
                                ? Brand.darkCardElevated
                                : Brand.cardLight,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark,
                            ),
                            items: _linkTypes
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l.$1,
                                    child: Text(l.$2),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setSheet(
                              () => linkType = v!,
                            ),
                          ),
                          if (linkType == 'catalog') ...[
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: eLinkValueCtrl.text.isNotEmpty
                                  ? eLinkValueCtrl.text
                                  : null,
                              hint: Text(
                                'Select category',
                                style: TextStyle(
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : Brand.subtleLight,
                                ),
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isDark
                                    ? Brand.darkCardElevated
                                    : Brand.scaffoldLight,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              dropdownColor: isDark
                                  ? Brand.darkCardElevated
                                  : Brand.cardLight,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : Brand.royalBlueDark,
                              ),
                              items: _machineCategories
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                eLinkValueCtrl.text = v ?? '';
                              },
                            ),
                          ] else if (linkType != 'none') ...[
                            const SizedBox(height: 10),
                            _editorField(
                              eLinkValueCtrl,
                              linkType == 'url'
                                  ? 'https://...'
                                  : 'Machine catalog ID',
                              isDark,
                            ),
                          ],
                          const SizedBox(height: 18),

                          // ── Display Order ──
                          _editorLabel(
                            'Display Order',
                            isDark,
                          ),
                          const SizedBox(height: 8),
                          _editorField(
                            eOrderCtrl,
                            '0 (higher = shown first)',
                            isDark,
                            keyboard: TextInputType.number,
                          ),
                          const SizedBox(height: 18),

                          // ── Active Toggle ──
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Brand.darkCardElevated
                                  : Brand.scaffoldLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isActive
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  color: isActive
                                      ? Brand.lightGreen
                                      : Brand.subtleLight,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    isActive
                                        ? 'Banner is active'
                                        : 'Banner is hidden',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Brand.darkTextPrimary
                                          : Brand.royalBlueDark,
                                    ),
                                  ),
                                ),
                                Switch.adaptive(
                                  value: isActive,
                                  activeTrackColor: Brand.lightGreen,
                                  onChanged: (v) => setSheet(
                                    () => isActive = v,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── Save Button ──
                          GestureDetector(
                            onTap: isSaving ? null : save,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: double.infinity,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: isSaving
                                    ? null
                                    : const LinearGradient(
                                        colors: [
                                          Brand.royalBlueDark,
                                          Brand.royalBlueLight
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                color: isSaving ? Brand.royalBlue : null,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: isDark || isSaving
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: Brand.royalBlue.withAlpha(89),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: Center(
                                child: isSaving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        isEditing
                                            ? 'Save Changes'
                                            : 'Create Banner',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: MediaQuery.of(sheetCtx).padding.bottom + 8,
                          ),
                        ],
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

  // ════════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ════════════════════════════════════════════════════════

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    // FIX: added clearSnackBars
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _redColor : Brand.lightGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatDate(String? ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts)?.toLocal();
    if (dt == null) return '';
    const months = [
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
      'Dec',
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:${dt.minute.toString().padLeft(2, '0')} $ap';
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      appBar: AppBar(
        backgroundColor: isDark ? Brand.darkCard : Brand.royalBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Broadcast & Promotions',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _loadHistory();
              _updateRecipientCount();
              _loadBanners();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withAlpha(179),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.campaign_rounded, size: 20),
              text: 'Broadcast',
            ),
            Tab(
              icon: Icon(
                Icons.photo_library_rounded,
                size: 20,
              ),
              text: 'Promotions',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBroadcastTab(isDark),
          _buildPromotionsTab(isDark),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  BROADCAST TAB
  // ════════════════════════════════════════════════════════

  Widget _buildBroadcastTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel(
            'COMPOSE',
            Icons.edit_rounded,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildComposeCard(isDark),
          const SizedBox(height: 24),
          _buildSectionLabel(
            'AUDIENCE',
            Icons.people_rounded,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildAudienceSelector(isDark),
          const SizedBox(height: 16),
          _buildRecipientCount(isDark),
          const SizedBox(height: 24),
          _buildSendButton(isDark),
          const SizedBox(height: 32),
          _buildSectionLabel(
            'RECENT BROADCASTS',
            Icons.history_rounded,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildHistory(isDark),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(
    String label,
    IconData icon,
    bool isDark,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Brand.darkTextSecondary : Brand.royalBlueLight,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Brand.darkTextSecondary : Brand.royalBlueLight,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildComposeCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(22),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        // FIX: replaced null with [] for dark mode
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _titleCtrl,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
            cursorColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
            decoration: InputDecoration(
              hintText: 'Notification title...',
              hintStyle: TextStyle(
                color:
                    isDark ? Brand.darkTextTertiary : const Color(0xFFCBD5E1),
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: Icon(
                Icons.title_rounded,
                color: isDark ? Brand.darkTextSecondary : Brand.royalBlueLight,
                size: 20,
              ),
              filled: true,
              fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bodyCtrl,
            maxLines: 5,
            minLines: 3,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              height: 1.5,
            ),
            cursorColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Write your message...',
              hintStyle: TextStyle(
                color:
                    isDark ? Brand.darkTextTertiary : const Color(0xFFCBD5E1),
              ),
              filled: true,
              fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceSelector(bool isDark) {
    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _audiences.map((a) {
            final selected = _audience == a.$1;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _audience = a.$1;
                  if (_audience != 'specific_machine') {
                    _selectedCategory = null;
                  }
                });
                _updateRecipientCount();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  // FIX: replaced .withOpacity() with .withAlpha()
                  // 0.15 ≈ 38, 0.1 ≈ 26
                  color: selected
                      ? a.$4.withAlpha(isDark ? 38 : 26)
                      : (isDark ? Brand.darkCard : Brand.cardLight),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    // 128 ≈ 50%
                    color: selected
                        ? a.$4.withAlpha(128)
                        : (isDark ? Brand.darkBorder : Brand.borderLight),
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: a.$4.withAlpha(38),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      a.$3,
                      size: 18,
                      color: selected
                          ? a.$4
                          : (isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      a.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected
                            ? a.$4
                            : (isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: a.$4,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (_audience == 'specific_machine') ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCard : Brand.cardLight,
              borderRadius: BorderRadius.circular(14),
              border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                isExpanded: true,
                hint: Text(
                  'Select machine category',
                  style: TextStyle(
                    color: isDark
                        ? Brand.darkTextTertiary
                        : const Color(0xFFCBD5E1),
                    fontSize: 14,
                  ),
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
                dropdownColor: isDark ? Brand.darkCard : Brand.cardLight,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
                items: _machineCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  setState(() => _selectedCategory = val);
                  _updateRecipientCount();
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecipientCount(bool isDark) {
    final hasRecipients = _recipientCount > 0;
    // FIX: replaced Colors.orange with const
    final color = hasRecipients ? Brand.lightGreen : _orangeColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // FIX: replaced .withOpacity() with .withAlpha()
        // 0.08 ≈ 20, 0.05 ≈ 13
        color: color.withAlpha(isDark ? 20 : 13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withAlpha(51),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withAlpha(38),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _recipientLoading
                ? Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    ),
                  )
                : Icon(
                    hasRecipients
                        ? Icons.group_rounded
                        : Icons.person_off_rounded,
                    color: color,
                    size: 20,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recipientLoading
                      ? 'Counting recipients...'
                      : '$_recipientCount recipient${_recipientCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                Text(
                  _audience == 'specific_machine' && _selectedCategory != null
                      ? 'Customers with $_selectedCategory machines'
                      : _audiences
                          .firstWhere(
                            (a) => a.$1 == _audience,
                          )
                          .$2,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _isSending ? null : _sendBroadcast,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: _isSending
                ? null
                : const LinearGradient(
                    colors: [
                      Brand.royalBlueDark,
                      Brand.royalBlue,
                    ],
                  ),
            color: _isSending
                ? (isDark ? Brand.darkCardElevated : Brand.borderLight)
                : null,
            borderRadius: BorderRadius.circular(18),
            // FIX: replaced null with [] for dark mode
            boxShadow: _isSending
                ? []
                : [
                    BoxShadow(
                      color: Brand.royalBlue.withAlpha(89),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSending)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                )
              else
                const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              const SizedBox(width: 12),
              Text(
                _isSending ? 'Sending...' : 'Send Broadcast',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _isSending
                      ? (isDark ? Brand.darkTextSecondary : Brand.subtleLight)
                      : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(bool isDark) {
    if (_isLoadingHistory) {
      return Column(
        children: List.generate(
          3,
          (_) => Container(
            height: 80,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : const Color(0xFFEEF0F5),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    if (_history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(22),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Column(
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 42,
              color: isDark ? Brand.darkTextTertiary : const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 12),
            Text(
              'No broadcasts sent yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _history.map((n) => _buildHistoryCard(n, isDark)).toList(),
    );
  }

  Widget _buildHistoryCard(
    Map<String, dynamic> n,
    bool isDark,
  ) {
    final createdAt = n['created_at'] as String?;
    final timeAgo = createdAt != null
        ? TimeUtils.getTimeAgo(DateTime.parse(createdAt))
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(18),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              // FIX: replaced .withOpacity() with .withAlpha()
              color: Brand.royalBlue.withAlpha(
                isDark ? 31 : 20,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.campaign_rounded,
              size: 18,
              color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (n['title'] ?? 'Untitled').toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  (n['body'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 12,
                      color: isDark
                          ? Brand.darkTextTertiary
                          : const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : const Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _formatDate(
                          n['created_at']?.toString(),
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextTertiary
                              : const Color(0xFFCBD5E1),
                        ),
                        overflow: TextOverflow.ellipsis,
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

  // ════════════════════════════════════════════════════════
  //  PROMOTIONS TAB
  // ════════════════════════════════════════════════════════

  Widget _buildPromotionsTab(bool isDark) {
    if (_loadingBanners) {
      return _buildBannersLoadingSkeleton(isDark);
    }

    final active =
        _banners.where((b) => _getBannerStatus(b) == 'active').length;
    final scheduled =
        _banners.where((b) => _getBannerStatus(b) == 'scheduled').length;
    final expired =
        _banners.where((b) => _getBannerStatus(b) == 'expired').length;

    return Stack(
      children: [
        RefreshIndicator(
          color: isDark ? Brand.darkIconActive : Brand.royalBlue,
          backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
          onRefresh: _loadBanners,
          child: _banners.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 100),
                    _buildEmptyBanners(isDark),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    100,
                  ),
                  children: [
                    _buildBannerStats(
                      isDark,
                      active,
                      scheduled,
                      expired,
                    ),
                    const SizedBox(height: 16),
                    _buildSectionLabel(
                      'BANNERS',
                      Icons.photo_library_rounded,
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    ..._banners.map(
                      (b) => _buildBannerCard(b, isDark),
                    ),
                  ],
                ),
        ),
        Positioned(
          right: 16,
          bottom: 24,
          child: FloatingActionButton.extended(
            onPressed: () => _showBannerEditor(),
            backgroundColor: Brand.royalBlue,
            foregroundColor: Colors.white,
            elevation: 4,
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text(
              'New Banner',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBannerStats(
    bool isDark,
    int active,
    int scheduled,
    int expired,
  ) {
    return Row(
      children: [
        _buildStatChip(
          'Total',
          '${_banners.length}',
          Brand.royalBlue,
          isDark,
        ),
        const SizedBox(width: 8),
        _buildStatChip(
          'Active',
          '$active',
          Brand.lightGreen,
          isDark,
        ),
        const SizedBox(width: 8),
        _buildStatChip(
          'Scheduled',
          '$scheduled',
          const Color(0xFF2196F3),
          isDark,
        ),
        const SizedBox(width: 8),
        _buildStatChip(
          'Expired',
          '$expired',
          _redColor,
          isDark,
        ),
      ],
    );
  }

  Widget _buildStatChip(
    String label,
    String value,
    Color color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: color,
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
        ),
      ),
    );
  }

  Widget _buildBannerCard(
    Map<String, dynamic> banner,
    bool isDark,
  ) {
    final status = _getBannerStatus(banner);
    final statusColor = _getStatusColor(status);
    final impressions = banner['impressions'] ?? 0;
    final clicks = banner['clicks'] ?? 0;
    final seasonTag = banner['season_tag'] as String?;
    final season = seasonTag != null
        ? _seasonTags.where((s) => s.$1 == seasonTag).firstOrNull
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(18),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        // FIX: replaced null with [] for dark mode
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18),
            ),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: (banner['image_url'] ?? '').toString(),
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                  child: const Center(
                    child: Icon(
                      Icons.image_rounded,
                      size: 32,
                      color: Brand.subtleLight,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      size: 32,
                      color: Brand.subtleLight,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (banner['title'] ?? '').toString(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        // FIX: replaced .withOpacity() with .withAlpha()
                        // 0.15 ≈ 38, 0.1 ≈ 26
                        color: statusColor.withAlpha(
                          isDark ? 38 : 26,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (banner['subtitle'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    banner['subtitle'].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.visibility_rounded,
                      size: 13,
                      color: Brand.subtleLight,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$impressions',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.touch_app_rounded,
                      size: 13,
                      color: Brand.subtleLight,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$clicks',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (season != null) ...[
                      const SizedBox(width: 10),
                      Icon(
                        season.$3,
                        size: 13,
                        color: season.$4,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        season.$2,
                        style: TextStyle(
                          fontSize: 12,
                          color: season.$4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Edit button
                    _actionButton(
                      icon: Icons.edit_rounded,
                      color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                      bg: Brand.royalBlue.withAlpha(
                        isDark ? 31 : 20,
                      ),
                      onTap: () => _showBannerEditor(existing: banner),
                    ),
                    const SizedBox(width: 6),
                    // Toggle active button
                    _actionButton(
                      icon: banner['is_active'] == true
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: banner['is_active'] == true
                          ? Brand.lightGreen
                          : _greyColor,
                      bg: (banner['is_active'] == true
                              ? Brand.lightGreen
                              : _greyColor)
                          .withAlpha(isDark ? 31 : 20),
                      onTap: () => _toggleBannerActive(
                        banner['id'].toString(),
                        !(banner['is_active'] == true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Delete button
                    _actionButton(
                      icon: Icons.delete_rounded,
                      color: _redLight,
                      bg: _redColor.withAlpha(
                        isDark ? 31 : 20,
                      ),
                      onTap: () => _deleteBanner(
                        banner['id'].toString(),
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

  // ── Reusable action button for banner card ──
  Widget _actionButton({
    required IconData icon,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildEmptyBanners(bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(22),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Column(
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 48,
              color: isDark ? Brand.darkTextTertiary : const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 16),
            Text(
              'No Promotional Banners',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create banners to display on\ncustomer home screens.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => _showBannerEditor(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
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
                            color: Brand.royalBlue.withAlpha(76),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Create First Banner',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Banners loading skeleton ──
  Widget _buildBannersLoadingSkeleton(bool isDark) {
    final shimmer = isDark ? Brand.darkCardElevated : const Color(0xFFEEF0F5);
    final card = isDark ? Brand.darkCard : const Color(0xFFF8FAFC);

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        // Stats row
        Row(
          children: List.generate(4, (i) {
            return Expanded(
              child: Container(
                height: 60,
                margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(14),
                  border: isDark ? Border.all(color: Brand.darkBorder) : null,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        // Banner cards
        ...List.generate(3, (i) {
          return Container(
            height: 220,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: shimmer,
              borderRadius: BorderRadius.circular(18),
              border: isDark ? Border.all(color: Brand.darkBorder) : null,
            ),
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  EDITOR HELPER WIDGETS
  // ════════════════════════════════════════════════════════

  Widget _editorLabel(String text, bool isDark) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            // FIX: replaced Colors.grey.shade700 with const
            color: isDark ? Brand.darkTextSecondary : _greyDark,
          ),
        ),
      );

  Widget _editorField(
    TextEditingController ctrl,
    String hint,
    bool isDark, {
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: TextStyle(
        fontSize: 14,
        color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
      ),
      cursorColor: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Brand.darkTextTertiary : const Color(0xFFCBD5E1),
          fontSize: 13,
        ),
        filled: true,
        fillColor: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _dateChip(
    String label,
    String value,
    VoidCallback onTap,
    bool isDark, {
    VoidCallback? onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              )
            else
              Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(
    String? value,
    String label,
    IconData icon,
    Color color,
    bool selected,
    VoidCallback onTap,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          // FIX: replaced .withOpacity() with .withAlpha()
          // 0.15 ≈ 38, 0.1 ≈ 26, 128 ≈ 50%
          color: selected
              ? color.withAlpha(isDark ? 38 : 26)
              : (isDark ? Brand.darkCardElevated : Brand.scaffoldLight),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color.withAlpha(128)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? color
                  : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? color
                    : (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_rounded,
            size: 36,
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to upload image',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recommended: 1920×1080 (16:9)',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Brand.darkTextTertiary : const Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }
}
