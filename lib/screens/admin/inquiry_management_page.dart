// lib/screens/admin/inquiry_management_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../services/export_service.dart';
import '../../utils/time_utils.dart';
import '../../utils/string_utils.dart';
import 'inquiry_detail_page.dart';

class InquiryManagementPage extends StatefulWidget {
  const InquiryManagementPage({super.key});

  @override
  State<InquiryManagementPage> createState() => _InquiryManagementPageState();
}

class _InquiryManagementPageState extends State<InquiryManagementPage>
    with TickerProviderStateMixin {
  // ─── State ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _inquiries = [];
  List<Map<String, dynamic>> _filteredInquiries = [];
  Map<String, dynamic> _pipeline = {};
  bool _isLoading = true;

  String _filterStage = 'all';
  String _sortBy = 'newest';
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  StreamSubscription? _realtimeSubscription;

  // Animation
  late AnimationController _pipelineAnimController;
  late Animation<double> _pipelineAnim;
  bool _hasAnimatedPipeline = false;

  // Scroll
  final _scrollController = ScrollController();
  bool _showScrollTop = false;

  // ─── Dark mode ─────────────────────────────────────────────
  // FIX: compute isDark from context in build, pass it to helpers
  // DO NOT store as instance field set in build()

  // ─── Theme helpers (receive isDark as parameter) ────────────
  Color _scaffoldBg(bool d) =>
      // FIX: AdminColors.background doesn't exist → Brand.scaffoldLight
      d ? Brand.darkBg : Brand.scaffoldLight;

  Color _cardBg(bool d) => d ? Brand.darkCard : Brand.cardLight;

  Color _cardElevated(bool d) =>
      // FIX: AdminColors.background doesn't exist → Brand.scaffoldLight
      d ? Brand.darkCardElevated : Brand.scaffoldLight;

  Color _textPrimary(bool d) =>
      // FIX: AdminColors.textPrimary doesn't exist
      d ? Brand.darkTextPrimary : Brand.royalBlueDark;

  Color _textSecondary(bool d) =>
      d ? Brand.darkTextSecondary : Colors.grey.shade600;

  Color _textMuted(bool d) => d ? Brand.darkTextTertiary : Colors.grey.shade400;

  Color _borderColor(bool d) => d ? Brand.darkBorder : Colors.grey.shade200;

  Color _borderLight(bool d) =>
      d ? Brand.darkBorderLight : Colors.grey.shade100;

  Color _handleColor(bool d) =>
      d ? Brand.darkBorderLight : Colors.grey.shade300;

  Color _sheetBg(bool d) => d ? Brand.darkCard : Colors.white;

  Color _primaryColor(bool d) => d ? Brand.royalBlueGlow : AdminColors.primary;

  Color _accentColor(bool d) => d ? Brand.lightGreenBright : AdminColors.accent;

  // FIX: AdminColors.primaryLight doesn't exist → Brand.royalBlueLight
  Color _primaryLight(bool d) => d ? Brand.royalBlue : Brand.royalBlueLight;

  // FIX: AdminColors.info doesn't exist → const value
  static const Color _infoColor = Color(0xFF3B82F6);

  List<BoxShadow> _softShadow(bool d) => d
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  List<BoxShadow> _cardShadow(bool d) => d
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ];

  @override
  void initState() {
    super.initState();
    _pipelineAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pipelineAnim = CurvedAnimation(
      parent: _pipelineAnimController,
      curve: Curves.easeOutCubic,
    );

    _scrollController.addListener(() {
      final show = _scrollController.offset > 200;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });

    _loadInquiries();
    _setupRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _realtimeDebounce?.cancel();
    _realtimeSubscription?.cancel();
    _pipelineAnimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── REALTIME ──────────────────────────────────────────────
  void _setupRealtime() {
    // FIX: added try/catch + debounce timer for realtime callback
    _realtimeSubscription = SupabaseConfig.client
        .from('service_tickets')
        .stream(primaryKey: ['id'])
        .eq('ticket_type', 'inquiry')
        .listen(
          (data) {
            try {
              if (!mounted || _isLoading) return;
              _realtimeDebounce?.cancel();
              _realtimeDebounce = Timer(const Duration(seconds: 2), () {
                if (mounted) _loadInquiries(silent: true);
              });
            } catch (e) {
              debugPrint('Realtime callback error: $e');
            }
          },
          onError: (e) {
            debugPrint('Inquiry stream error: $e');
          },
        );
  }

  // ─── DATA LOADING ──────────────────────────────────────────
  Future<void> _loadInquiries({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);


    try {
      // FIX: explicit <dynamic> type on Future.wait
      final results = await Future.wait<dynamic>([
        _fetchPipeline(),
        _fetchInquiries(),
      ]);

      if (!mounted) return;

      setState(() {
        _pipeline = results[0] as Map<String, dynamic>;
        _inquiries = results[1] as List<Map<String, dynamic>>;
        _applyFilters();
        _isLoading = false;
      });

      if (!_hasAnimatedPipeline) {
        _pipelineAnimController.forward(from: 0);
        _hasAnimatedPipeline = true;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Error loading inquiries: $e', isError: true);
    }
  }

  Future<Map<String, dynamic>> _fetchPipeline() async {
    try {
      final result = await SupabaseConfig.client.rpc('get_inquiry_pipeline');
      if (result is Map<String, dynamic>) return result;
      if (result is Map) return Map<String, dynamic>.from(result);
      return <String, dynamic>{};
    } catch (e) {
      debugPrint('Pipeline fetch error: $e');
      return <String, dynamic>{};
    }
  }

  Future<List<Map<String, dynamic>>> _fetchInquiries() async {
    try {
      final result =
          await SupabaseConfig.client.rpc('get_inquiries_with_details');
      if (result is List) {
        return result
            .map((e) => e is Map<String, dynamic>
                ? e
                : Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return await _loadInquiriesFallback();
    } catch (e) {
      debugPrint('Inquiries RPC error: $e — using fallback');
      return await _loadInquiriesFallback();
    }
  }

  Future<List<Map<String, dynamic>>> _loadInquiriesFallback() async {
    final data = await SupabaseConfig.client.from('service_tickets').select('''
          *,
          users!service_tickets_user_id_fkey(
            full_name, email, company_name, phone_number, city, profile_photo
          ),
          machine_catalog!service_tickets_catalog_machine_id_fkey(
            machine_name, brand, model_number, category, product_images, image_url
          )
        ''')
        .eq('ticket_type', 'inquiry')
        .eq('is_deleted', false)
        .order('created_at', ascending: false);

    return (data as List).map((raw) {
      // FIX: use spread copy — never mutate maps directly
      final i = Map<String, dynamic>.from(raw as Map);
      final user = i['users'] as Map<String, dynamic>?;
      final machine = i['machine_catalog'] as Map<String, dynamic>?;
      final images = machine?['product_images'] as List?;
      return <String, dynamic>{
        ...i,
        'customer_name': user?['full_name'],
        'customer_email': user?['email'],
        'customer_company': user?['company_name'],
        'customer_phone': user?['phone_number'],
        'customer_city': user?['city'],
        'customer_photo': user?['profile_photo'],
        'machine_name': machine?['machine_name'],
        'machine_brand': machine?['brand'],
        'machine_model': machine?['model_number'],
        'machine_category': machine?['category'],
        'machine_image': images != null && images.isNotEmpty
            ? images[0]
            : machine?['image_url'],
        'message_count': 0,
        'unread_count': 0,
        'days_open': DateTime.now()
            .difference(DateTime.parse(i['created_at'].toString()))
            .inDays,
      };
    }).toList();
  }

  // ─── FILTERING & SORTING ──────────────────────────────────
  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_inquiries);

    if (_filterStage == 'hot') {
      filtered = filtered.where((i) => i['is_hot_lead'] == true).toList();
    } else if (_filterStage == 'overdue') {
      filtered = filtered.where((i) {
        final followUp = i['follow_up_date'];
        if (followUp == null) return false;
        return DateTime.parse(followUp.toString()).isBefore(DateTime.now());
      }).toList();
    } else if (_filterStage == 'needs_attention') {
      filtered = filtered.where((i) {
        final lastActivity = i['last_activity_at'];
        if (lastActivity == null) return true;
        return DateTime.now()
                .difference(DateTime.parse(lastActivity.toString()))
                .inDays >=
            3;
      }).toList();
    } else if (_filterStage != 'all') {
      filtered = filtered
          .where((i) => (i['sales_stage'] ?? 'new') == _filterStage)
          .toList();
    }

    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      filtered = filtered.where((i) {
        final searchFields = [
          i['customer_name'],
          i['customer_company'],
          i['customer_email'],
          i['customer_phone'],
          i['machine_name'],
          i['machine_brand'],
          i['machine_model'],
          i['ticket_number'],
          i['subject'],
        ];
        return searchFields.any(
            (f) => f != null && f.toString().toLowerCase().contains(query));
      }).toList();
    }

    switch (_sortBy) {
      case 'oldest':
        filtered.sort(
            (a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''));
        break;
      case 'deal_value':
        filtered.sort((a, b) =>
            _toNum(b['deal_value']).compareTo(_toNum(a['deal_value'])));
        break;
      case 'priority':
        const priorityOrder = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};
        filtered.sort((a, b) => (priorityOrder[a['priority'] ?? 'medium'] ?? 2)
            .compareTo(priorityOrder[b['priority'] ?? 'medium'] ?? 2));
        break;
      case 'last_activity':
        filtered.sort((a, b) => (b['last_activity_at'] ?? '')
            .toString()
            .compareTo((a['last_activity_at'] ?? '').toString()));
        break;
      default:
        filtered.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
    }

    _filteredInquiries = filtered;
  }

  num _toNum(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? 0;
  }

  // ─── QUICK ACTIONS ─────────────────────────────────────────
  Future<void> _quickUpdateStage(
      Map<String, dynamic> inquiry, String newStage) async {
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    HapticFeedback.mediumImpact();

    try {
      final result =
          await SupabaseConfig.client.rpc('update_inquiry_stage', params: {
        'p_ticket_id': inquiry['id'],
        'p_new_stage': newStage,
        'p_user_id': currentUserId,
      });

      if (!mounted) return;

      final success = result is Map && result['success'] == true;
      if (success) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        _showSnackBar(
          'Stage updated to ${newStage.toUpperCase()}',
          icon: _getStageIcon(newStage),
          color: _getStageColor(newStage),
          isDark: isDark,
        );
        await _loadInquiries(silent: true);
      } else {
        final errorMsg =
            result is Map ? (result['error'] ?? 'Unknown error') : 'Failed';
        if (mounted) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          _showSnackBar('Update failed: $errorMsg',
              isError: true, isDark: isDark);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      _showSnackBar('Failed to update stage: $e',
          isError: true, isDark: isDark);
    }
  }

  Future<void> _toggleHotLead(Map<String, dynamic> inquiry) async {
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    HapticFeedback.lightImpact();

    try {
      final result =
          await SupabaseConfig.client.rpc('toggle_hot_lead', params: {
        'p_ticket_id': inquiry['id'],
        'p_user_id': currentUserId,
      });

      if (!mounted) return;

      final bool newValue = result == true;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      _showSnackBar(
        newValue ? '🔥 Marked as hot lead' : 'Hot lead flag removed',
        color: newValue ? Colors.orange : Colors.grey,
        isDark: isDark,
      );
      await _loadInquiries(silent: true);
    } catch (e) {
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      _showSnackBar('Failed to toggle hot lead: $e',
          isError: true, isDark: isDark);
    }
  }

  // ─── HELPERS ───────────────────────────────────────────────
  int _getStageCount(String stage) {
    if (stage == 'all') return _inquiries.length;
    if (stage == 'hot') {
      return _toNum(_pipeline['hot_leads']).toInt();
    }
    if (stage == 'overdue') {
      return _toNum(_pipeline['overdue_follow_ups']).toInt();
    }
    if (stage == 'needs_attention') {
      return _toNum(_pipeline['needs_attention']).toInt();
    }
    final pipelineCount = _pipeline[stage];
    if (pipelineCount != null) return _toNum(pipelineCount).toInt();
    return _inquiries.where((i) => (i['sales_stage'] ?? 'new') == stage).length;
  }

  Color _getStageColor(String stage) {
    switch (stage) {
      case 'new':
        return const Color(0xFF3B82F6);
      case 'contacted':
        return const Color(0xFF8B5CF6);
      case 'quoted':
        return const Color(0xFFF59E0B);
      case 'negotiating':
        return const Color(0xFFEF8C22);
      case 'won':
        return AdminColors.accent;
      case 'lost':
        return AdminColors.error;
      case 'hot':
        return const Color(0xFFFF6B35);
      case 'overdue':
        return const Color(0xFFDC2626);
      case 'needs_attention':
        return const Color(0xFFCA8A04);
      default:
        return Colors.grey;
    }
  }

  IconData _getStageIcon(String stage) {
    switch (stage) {
      case 'new':
        return Icons.fiber_new_rounded;
      case 'contacted':
        return Icons.phone_callback_rounded;
      case 'quoted':
        return Icons.receipt_long_rounded;
      case 'negotiating':
        return Icons.handshake_rounded;
      case 'won':
        return Icons.emoji_events_rounded;
      case 'lost':
        return Icons.cancel_rounded;
      case 'hot':
        return Icons.local_fire_department_rounded;
      case 'overdue':
        return Icons.warning_amber_rounded;
      case 'needs_attention':
        return Icons.notification_important_rounded;
      default:
        return Icons.circle_rounded;
    }
  }

  String _getNextStage(String currentStage) {
    const order = ['new', 'contacted', 'quoted', 'negotiating', 'won'];
    final idx = order.indexOf(currentStage);
    if (idx < 0 || idx >= order.length - 1) return currentStage;
    return order[idx + 1];
  }

  double _getStageProgress(String stage) {
    switch (stage) {
      case 'new':
        return 0.15;
      case 'contacted':
        return 0.30;
      case 'quoted':
        return 0.55;
      case 'negotiating':
        return 0.75;
      case 'won':
        return 1.0;
      case 'lost':
        return 1.0;
      default:
        return 0.1;
    }
  }

  String _formatCurrency(dynamic value) {
    final num numValue = _toNum(value);
    if (numValue == 0) return 'Rs. 0';
    if (numValue >= 1000000) {
      return 'Rs. ${(numValue / 1000000).toStringAsFixed(1)}M';
    }
    if (numValue >= 1000) {
      return 'Rs. ${(numValue / 1000).toStringAsFixed(1)}K';
    }
    return 'Rs. ${numValue.toStringAsFixed(0)}';
  }

  String _getPriorityLabel(String? priority) {
    switch (priority) {
      case 'urgent':
        return '🔴';
      case 'high':
        return '🟠';
      case 'medium':
        return '🟡';
      case 'low':
        return '🟢';
      default:
        return '';
    }
  }

  String _getSortLabel(String sort) {
    switch (sort) {
      case 'newest':
        return 'Newest';
      case 'oldest':
        return 'Oldest';
      case 'deal_value':
        return 'Value';
      case 'priority':
        return 'Priority';
      case 'last_activity':
        return 'Activity';
      default:
        return 'Sort';
    }
  }

  // FIX: added isDark parameter so snackbar can be called from
  // async callbacks after await (where context.brightness might differ)
  void _showSnackBar(
    String message, {
    bool isError = false,
    IconData? icon,
    Color? color,
    bool? isDark,
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
        backgroundColor:
            isError ? AdminColors.error : color ?? AdminColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) {
      if (mounted) _loadInquiries(silent: true);
    });
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // FIX: compute isDark locally in build, pass to all helpers
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _scaffoldBg(isDark),
      floatingActionButton: _showScrollTop
          ? FloatingActionButton.small(
              onPressed: () => _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
              ),
              backgroundColor: _primaryColor(isDark),
              child: const Icon(Icons.keyboard_arrow_up_rounded,
                  color: Colors.white),
            )
          : null,
      appBar: DsPageHeader(
        title: 'Inquiries',
        subtitle: '${_inquiries.length} total',
        showBack: false,
        accent: HeroAccent.navy,
        actions: [
          IconButton(icon: const Icon(Icons.file_download_outlined, color: Colors.white), onPressed: _exportInquiriesToExcel),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _loadInquiries),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? _buildLoadingSkeleton(isDark)
                  : RefreshIndicator(
                      onRefresh: _loadInquiries,
                      color: _accentColor(isDark),
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildSearchBar(isDark)),
                          SliverToBoxAdapter(child: _buildAlertBanner(isDark)),
                          SliverToBoxAdapter(child: _buildPipelineCard(isDark)),
                          SliverToBoxAdapter(child: _buildStageFilters(isDark)),
                          SliverToBoxAdapter(
                              child: _buildResultsHeader(isDark)),
                          _filteredInquiries.isEmpty
                              ? SliverFillRemaining(
                                  child: _buildEmptyState(isDark))
                              : SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 4, 20, 20),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) => _buildInquiryCard(
                                        _filteredInquiries[index],
                                        isDark,
                                      ),
                                      childCount: _filteredInquiries.length,
                                    ),
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

  // ─── EXPORT INQUIRIES (v24) ────────────────────────────────
  Future<void> _exportInquiriesToExcel() async {
    if (_filteredInquiries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export with current filters.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing Excel export…')),
    );
    final path = await ExportService.instance.exportInquiries(_filteredInquiries);
    if (!mounted) return;
    ExportService.showResult(context, path);
  }

  // ─── ALERT BANNER ──────────────────────────────────────────
  Widget _buildAlertBanner(bool isDark) {
    final overdueCount = _toNum(_pipeline['overdue_follow_ups']).toInt();
    final noResponse = _toNum(_pipeline['no_response_24h']).toInt();
    final quotesExpiring = _toNum(_pipeline['quotes_expiring_soon']).toInt();

    if (overdueCount == 0 && noResponse == 0 && quotesExpiring == 0) {
      return const SizedBox.shrink();
    }

    final alerts = <Map<String, dynamic>>[];
    if (noResponse > 0) {
      alerts.add({
        'icon': Icons.schedule_rounded,
        'text':
            '$noResponse new inquiry${noResponse > 1 ? 's' : ''} > 24h without response',
        'color': Colors.red,
        'filter': 'new',
      });
    }
    if (overdueCount > 0) {
      alerts.add({
        'icon': Icons.warning_amber_rounded,
        'text': '$overdueCount overdue follow-up${overdueCount > 1 ? 's' : ''}',
        'color': Colors.orange,
        'filter': 'overdue',
      });
    }
    if (quotesExpiring > 0) {
      alerts.add({
        'icon': Icons.timer_off_rounded,
        'text':
            '$quotesExpiring quote${quotesExpiring > 1 ? 's' : ''} expiring within 7 days',
        'color': Colors.amber.shade700,
        'filter': 'quoted',
      });
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      decoration: BoxDecoration(
        // FIX: .withOpacity() → .withAlpha()
        color: AdminColors.error.withAlpha(isDark ? 20 : 10),
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border:
            Border.all(color: AdminColors.error.withAlpha(isDark ? 51 : 31)),
      ),
      child: Column(
        children: alerts.map((alert) {
          return GestureDetector(
            onTap: () {
              setState(() {
                _filterStage = alert['filter'] as String;
                _applyFilters();
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(alert['icon'] as IconData,
                      size: 18, color: alert['color'] as Color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      alert['text'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: _textMuted(isDark)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── SEARCH BAR ────────────────────────────────────────────
  Widget _buildSearchBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: isDark ? Border.all(color: _borderColor(isDark)) : null,
        boxShadow: _cardShadow(isDark),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: _textPrimary(isDark), fontSize: 14),
        onChanged: (_) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) setState(() => _applyFilters());
          });
        },
        decoration: InputDecoration(
          hintText: 'Search customer, machine, ticket #...',
          hintStyle: TextStyle(color: _textMuted(isDark), fontSize: 14),
          prefixIcon:
              Icon(Icons.search_rounded, color: _textMuted(isDark), size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _applyFilters());
                  },
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _cardElevated(isDark),
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Icon(Icons.close_rounded,
                        color: _textSecondary(isDark), size: 18),
                  ),
                )
              : null,
          filled: true,
          fillColor: _cardBg(isDark),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ─── PIPELINE CARD ─────────────────────────────────────────
  Widget _buildPipelineCard(bool isDark) {
    final conversionRate = _toNum(_pipeline['conversion_rate']).toInt();
    final totalDealValue = _toNum(_pipeline['total_deal_value']);
    final pendingValue = _toNum(_pipeline['pending_deal_value']);
    final thisMonth = _toNum(_pipeline['this_month']).toInt();
    final thisMonthWon = _toNum(_pipeline['this_month_won']).toInt();
    final thisMonthValue = _toNum(_pipeline['this_month_value']);
    final avgDaysToClose = _toNum(_pipeline['avg_days_to_close']).toInt();

    return AnimatedBuilder(
      animation: _pipelineAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 10 * (1 - _pipelineAnim.value)),
          child: Opacity(opacity: _pipelineAnim.value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [Brand.royalBlueDark, Brand.royalBlue]
                // FIX: AdminColors.primaryLight → _primaryLight(isDark)
                : [AdminColors.primary, _primaryLight(isDark)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          boxShadow: [
            BoxShadow(
              // FIX: .withOpacity() → .withAlpha()
              color: (isDark ? Brand.royalBlue : AdminColors.primary)
                  .withAlpha(isDark ? 77 : 89),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accentColor(isDark),
                    borderRadius: BorderRadius.circular(Brand.r(20)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.trending_up_rounded,
                          color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Sales Pipeline',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '$thisMonth this month ($thisMonthWon won)',
                  style: TextStyle(
                      // FIX: .withOpacity() → .withAlpha()
                      color: Colors.white.withAlpha(153),
                      fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPipelineStat(
                    '$conversionRate%', 'Conversion', _accentColor(isDark)),
                _buildPipelineDivider(),
                _buildPipelineStat(
                    _formatCurrency(totalDealValue), 'Won Value', Colors.white),
                _buildPipelineDivider(),
                _buildPipelineStat(
                    _formatCurrency(pendingValue), 'In Pipeline', Colors.amber),
                _buildPipelineDivider(),
                _buildPipelineStat(
                    '${avgDaysToClose}d', 'Avg Close', Colors.lightBlueAccent),
              ],
            ),
            if (thisMonthValue > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  // FIX: .withOpacity() → .withAlpha()
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_rounded,
                        size: 14,
                        // FIX: .withOpacity() → .withAlpha()
                        color: Colors.white.withAlpha(153)),
                    const SizedBox(width: 6),
                    Text(
                      'This month: ${_formatCurrency(thisMonthValue)}',
                      style: TextStyle(
                          fontSize: 12,
                          // FIX: .withOpacity() → .withAlpha()
                          color: Colors.white.withAlpha(204),
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          // FIX: .withOpacity() → .withAlpha()
          style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(128)),
        ),
      ],
    );
  }

  Widget _buildPipelineDivider() {
    // FIX: .withOpacity() → .withAlpha()
    return Container(width: 1, height: 28, color: Colors.white.withAlpha(31));
  }

  // ─── STAGE FILTERS ─────────────────────────────────────────
  Widget _buildStageFilters(bool isDark) {
    const stages = [
      'all',
      'hot',
      'new',
      'contacted',
      'quoted',
      'negotiating',
      'won',
      'lost',
      'overdue',
      'needs_attention',
    ];
    const labels = {
      'all': 'All',
      'hot': 'Hot 🔥',
      'new': 'New',
      'contacted': 'Contacted',
      'quoted': 'Quoted',
      'negotiating': 'Negotiating',
      'won': 'Won',
      'lost': 'Lost',
      'overdue': 'Overdue',
      'needs_attention': 'Stale',
    };

    final visibleStages = stages.where((s) {
      if (s == 'all' || s == _filterStage) return true;
      return _getStageCount(s) > 0;
    }).toList();

    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 14),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: visibleStages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final stage = visibleStages[index];
          final isSelected = _filterStage == stage;
          final color =
              stage == 'all' ? _primaryColor(isDark) : _getStageColor(stage);
          final count = _getStageCount(stage);

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _filterStage = stage;
                _applyFilters();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color : _cardBg(isDark),
                borderRadius: BorderRadius.circular(Brand.r(12)),
                border: Border.all(
                  color: isSelected ? color : _borderColor(isDark),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            // FIX: .withOpacity() → .withAlpha()
                            color: color.withAlpha(77),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ]
                    : _softShadow(isDark),
              ),
              child: Row(
                children: [
                  if (stage != 'all') ...[
                    Icon(_getStageIcon(stage),
                        size: 14, color: isSelected ? Colors.white : color),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    labels[stage]!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : _textSecondary(isDark),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          // FIX: .withOpacity() → .withAlpha()
                          ? Colors.white.withAlpha(64)
                          : color.withAlpha(isDark ? 38 : 26),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : color,
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

  // ─── RESULTS HEADER ────────────────────────────────────────
  Widget _buildResultsHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Text(
            '${_filteredInquiries.length} ',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _primaryColor(isDark)),
          ),
          Text(
            _filteredInquiries.length == _inquiries.length
                ? 'inquiries'
                : 'of ${_inquiries.length} inquiries',
            style: TextStyle(fontSize: 13, color: _textSecondary(isDark)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _showSortOptions(isDark),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _cardBg(isDark),
                borderRadius: BorderRadius.circular(Brand.r(8)),
                border: Border.all(color: _borderColor(isDark)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded,
                      size: 14, color: _textSecondary(isDark)),
                  const SizedBox(width: 4),
                  Text(
                    _getSortLabel(_sortBy),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _textSecondary(isDark)),
                  ),
                ],
              ),
            ),
          ),
          if (_filterStage != 'all' || _searchController.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() {
                  _filterStage = 'all';
                  _sortBy = 'newest';
                  _applyFilters();
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  // FIX: .withOpacity() → .withAlpha()
                  color: AdminColors.error.withAlpha(isDark ? 31 : 20),
                  borderRadius: BorderRadius.circular(Brand.r(8)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded,
                        size: 12, color: AdminColors.error),
                    SizedBox(width: 4),
                    Text(
                      'Clear',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.error),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSortOptions(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: _sheetBg(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _handleColor(isDark),
                  borderRadius: BorderRadius.circular(Brand.r(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sort By',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor(isDark)),
              ),
              const SizedBox(height: 12),
              ...['newest', 'oldest', 'deal_value', 'priority', 'last_activity']
                  .map((sort) {
                final icons = {
                  'newest': Icons.arrow_downward_rounded,
                  'oldest': Icons.arrow_upward_rounded,
                  'deal_value': Icons.payments_rounded,
                  'priority': Icons.flag_rounded,
                  'last_activity': Icons.access_time_rounded,
                };
                final labels = {
                  'newest': 'Newest First',
                  'oldest': 'Oldest First',
                  'deal_value': 'Highest Value',
                  'priority': 'Highest Priority',
                  'last_activity': 'Recent Activity',
                };
                final isSelected = _sortBy == sort;

                return ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSelected
                          // FIX: .withOpacity() → .withAlpha()
                          ? _primaryColor(isDark).withAlpha(26)
                          : _cardElevated(isDark),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                    ),
                    child: Icon(
                      icons[sort],
                      size: 18,
                      color: isSelected
                          ? _primaryColor(isDark)
                          : _textSecondary(isDark),
                    ),
                  ),
                  title: Text(
                    labels[sort]!,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? _primaryColor(isDark)
                          : _textPrimary(isDark),
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded,
                          color: _accentColor(isDark), size: 22)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    setState(() {
                      _sortBy = sort;
                      _applyFilters();
                    });
                  },
                );
              }),
              SizedBox(height: MediaQuery.of(sheetCtx).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }

  // ─── INQUIRY CARD ──────────────────────────────────────────
  Widget _buildInquiryCard(Map<String, dynamic> inquiry, bool isDark) {
    final salesStage = (inquiry['sales_stage'] ?? 'new').toString();
    final stageColor = _getStageColor(salesStage);
    final customerName = (inquiry['customer_name'] ?? 'Unknown').toString();
    final customerCompany = (inquiry['customer_company'] ?? '').toString();
    final customerCity = (inquiry['customer_city'] ?? '').toString();
    final machineName = inquiry['machine_name']?.toString();
    final machineBrand = (inquiry['machine_brand'] ?? '').toString();
    final machineImage = inquiry['machine_image']?.toString();
    final machineModel = (inquiry['machine_model'] ?? '').toString();
    final dealValue = _toNum(inquiry['deal_value']);
    final quoteAmount = _toNum(inquiry['quote_amount']);
    final createdAt =
        DateTime.tryParse(inquiry['created_at']?.toString() ?? '') ??
            DateTime.now();
    final unreadCount = _toNum(inquiry['unread_count']).toInt();
    final messageCount = _toNum(inquiry['message_count']).toInt();
    final daysOpen = _toNum(inquiry['days_open']).toInt();
    final isHotLead = inquiry['is_hot_lead'] == true;
    final followUpDate = inquiry['follow_up_date']?.toString();
    final priority = inquiry['priority']?.toString();
    final lastMessagePreview = inquiry['last_message_preview']?.toString();
    final assignedName =
        (inquiry['assigned_engineer_name'] ?? inquiry['assigned_sales_name'])
            ?.toString();

    final bool isOverdueFollowUp = followUpDate != null &&
        (DateTime.tryParse(followUpDate)?.isBefore(DateTime.now()) ?? false) &&
        salesStage != 'won' &&
        salesStage != 'lost';

    final nextStage = _getNextStage(salesStage);
    final canAdvance = salesStage != 'won' && salesStage != 'lost';

    return GestureDetector(
      onTap: () => _navigateTo(InquiryDetailPage(inquiryId: inquiry['id'])),
      onLongPress: () => _showQuickActions(inquiry, isDark),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: isHotLead
              ? Border.all(
                  // FIX: .withOpacity() → .withAlpha()
                  color: Colors.orange.withAlpha(isDark ? 102 : 77),
                  width: 1.5)
              : isOverdueFollowUp
                  ? Border.all(
                      color: AdminColors.error.withAlpha(isDark ? 77 : 51),
                      width: 1.5)
                  : isDark
                      ? Border.all(color: _borderColor(isDark))
                      : null,
          boxShadow: isHotLead
              ? [
                  BoxShadow(
                    // FIX: .withOpacity() → .withAlpha()
                    color: Colors.orange.withAlpha(isDark ? 26 : 20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : _cardShadow(isDark),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Row 1: Badges ──
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          // FIX: .withOpacity() → .withAlpha()
                          color: stageColor.withAlpha(isDark ? 38 : 26),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getStageIcon(salesStage),
                                size: 11, color: stageColor),
                            const SizedBox(width: 4),
                            Text(
                              salesStage.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: stageColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isHotLead) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _toggleHotLead(inquiry),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              // FIX: .withOpacity() → .withAlpha()
                              color: Colors.orange.withAlpha(isDark ? 38 : 26),
                              borderRadius: BorderRadius.circular(Brand.r(10)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_fire_department_rounded,
                                    size: 12, color: Colors.orange),
                                SizedBox(width: 2),
                                Text('HOT',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: Colors.orange)),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (priority != null && priority != 'medium') ...[
                        const SizedBox(width: 6),
                        Text(_getPriorityLabel(priority),
                            style: const TextStyle(fontSize: 12)),
                      ],
                      if (daysOpen > 7 &&
                          salesStage != 'won' &&
                          salesStage != 'lost') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            // FIX: .withOpacity() → .withAlpha()
                            color: (daysOpen > 14
                                    ? AdminColors.error
                                    : Colors.orange)
                                .withAlpha(isDark ? 38 : 26),
                            borderRadius: BorderRadius.circular(Brand.r(10)),
                          ),
                          child: Text(
                            '${daysOpen}d',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: daysOpen > 14
                                  ? AdminColors.error
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (unreadCount > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AdminColors.error,
                            borderRadius: BorderRadius.circular(Brand.r(10)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_rounded,
                                  size: 10, color: Colors.white),
                              const SizedBox(width: 3),
                              Text('$unreadCount',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        TimeUtils.getTimeAgo(createdAt),
                        style:
                            TextStyle(fontSize: 12, color: _textMuted(isDark)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Row 2: Customer ──
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AdminColors.primary
                                // FIX: .withOpacity() → .withAlpha()
                                .withAlpha(isDark ? 38 : 20),
                            _accentColor(isDark).withAlpha(isDark ? 38 : 20),
                          ]),
                          borderRadius: BorderRadius.circular(Brand.r(12)),
                        ),
                        child: Center(
                          child: Text(
                            StringUtils.getInitials(customerName),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _primaryColor(isDark)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _textPrimary(isDark)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                if (customerCompany.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      customerCompany,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _textSecondary(isDark)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (customerCity.isNotEmpty) ...[
                                  if (customerCompany.isNotEmpty)
                                    Text(
                                      ' • ',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _textMuted(isDark)),
                                    ),
                                  Text(
                                    customerCity,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: _textMuted(isDark)),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (dealValue > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                // FIX: .withOpacity() → .withAlpha()
                                color: _accentColor(isDark)
                                    .withAlpha(isDark ? 38 : 26),
                                borderRadius: BorderRadius.circular(Brand.r(8)),
                              ),
                              child: Text(
                                _formatCurrency(dealValue),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _accentColor(isDark)),
                              ),
                            )
                          else if (quoteAmount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                // FIX: .withOpacity() → .withAlpha()
                                color:
                                    Colors.orange.withAlpha(isDark ? 38 : 26),
                                borderRadius: BorderRadius.circular(Brand.r(8)),
                              ),
                              child: Text(
                                _formatCurrency(quoteAmount),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade700),
                              ),
                            ),
                          if (assignedName != null) ...[
                            const SizedBox(height: 4),
                            Text(assignedName,
                                style: TextStyle(
                                    fontSize: 11, color: _textMuted(isDark))),
                          ],
                        ],
                      ),
                    ],
                  ),

                  // ── Machine info ──
                  if (machineName != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _cardElevated(isDark),
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                        border: isDark
                            ? Border.all(color: _borderColor(isDark))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _cardBg(isDark),
                              borderRadius: BorderRadius.circular(Brand.r(10)),
                              border: isDark
                                  ? Border.all(color: _borderColor(isDark))
                                  : null,
                            ),
                            child:
                                machineImage != null && machineImage.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(Brand.r(10)),
                                        child: CachedNetworkImage(
                                          imageUrl: machineImage,
                                          fit: BoxFit.cover,
                                          width: 42,
                                          height: 42,
                                          placeholder: (_, __) => Icon(
                                              Icons.inventory_2_rounded,
                                              color: _primaryColor(isDark),
                                              size: 20),
                                          errorWidget: (_, __, ___) => Icon(
                                              Icons.inventory_2_rounded,
                                              color: _primaryColor(isDark),
                                              size: 20),
                                        ),
                                      )
                                    : Icon(Icons.inventory_2_rounded,
                                        color: _primaryColor(isDark), size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (machineBrand.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          // FIX: .withOpacity() → .withAlpha()
                                          color: _primaryColor(isDark)
                                              .withAlpha(isDark ? 31 : 15),
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(4)),
                                        ),
                                        child: Text(
                                          machineBrand,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _primaryColor(isDark)),
                                        ),
                                      ),
                                    if (machineBrand.isNotEmpty)
                                      const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        machineModel,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: _textSecondary(isDark)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  machineName,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _textPrimary(isDark)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Follow-up / Last message ──
                  if (isOverdueFollowUp ||
                      followUpDate != null ||
                      lastMessagePreview != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (isOverdueFollowUp)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              // FIX: .withOpacity() → .withAlpha()
                              color:
                                  AdminColors.error.withAlpha(isDark ? 31 : 20),
                              borderRadius: BorderRadius.circular(Brand.r(10)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.alarm_rounded,
                                    size: 12, color: AdminColors.error),
                                SizedBox(width: 4),
                                Text(
                                  'Follow-up overdue',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AdminColors.error),
                                ),
                              ],
                            ),
                          )
                        else if (followUpDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              // FIX: .withOpacity() → .withAlpha()
                              color: _infoColor.withAlpha(isDark ? 31 : 20),
                              borderRadius: BorderRadius.circular(Brand.r(10)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.event_rounded,
                                    size: 12, color: _infoColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Follow-up: $followUpDate',
                                  style: const TextStyle(
                                      fontSize: 12, color: _infoColor),
                                ),
                              ],
                            ),
                          ),
                        if (lastMessagePreview != null &&
                            !isOverdueFollowUp) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '💬 $lastMessagePreview',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _textMuted(isDark),
                                  fontStyle: FontStyle.italic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (messageCount > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_outlined,
                                  size: 12, color: _textMuted(isDark)),
                              const SizedBox(width: 3),
                              Text('$messageCount',
                                  style: TextStyle(
                                      fontSize: 12, color: _textMuted(isDark))),
                            ],
                          ),
                      ],
                    ),
                  ],

                  // ── Quick advance ──
                  if (canAdvance && nextStage != salesStage) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _quickUpdateStage(inquiry, nextStage),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          // FIX: .withOpacity() → .withAlpha()
                          color: _getStageColor(nextStage)
                              .withAlpha(isDark ? 26 : 15),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                          border: Border.all(
                            color: _getStageColor(nextStage)
                                .withAlpha(isDark ? 51 : 38),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_forward_rounded,
                                size: 14, color: _getStageColor(nextStage)),
                            const SizedBox(width: 6),
                            Text(
                              'Move to ${nextStage.toUpperCase()}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _getStageColor(nextStage)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Progress bar ──
            Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(Brand.r(18))),
                color: isDark ? Brand.darkBorder : Colors.grey.shade100,
              ),
              child: LayoutBuilder(builder: (context, constraints) {
                return Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      width:
                          constraints.maxWidth * _getStageProgress(salesStage),
                      decoration: BoxDecoration(
                        color: salesStage == 'lost'
                            ? AdminColors.error
                            : stageColor,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(Brand.r(18)),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ─── QUICK ACTIONS SHEET ───────────────────────────────────
  void _showQuickActions(Map<String, dynamic> inquiry, bool isDark) {
    HapticFeedback.mediumImpact();
    final salesStage = (inquiry['sales_stage'] ?? 'new').toString();
    final isHotLead = inquiry['is_hot_lead'] == true;
    final customerName = (inquiry['customer_name'] ?? 'Unknown').toString();
    final ticketNumber = (inquiry['ticket_number'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: _sheetBg(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _handleColor(isDark),
                  borderRadius: BorderRadius.circular(Brand.r(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$customerName • $ticketNumber',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor(isDark)),
              ),
              const SizedBox(height: 8),

              // Stage chips
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'new',
                    'contacted',
                    'quoted',
                    'negotiating',
                    'won',
                    'lost'
                  ].map((stage) {
                    final isCurrentStage = salesStage == stage;
                    final color = _getStageColor(stage);
                    return GestureDetector(
                      onTap: isCurrentStage
                          ? null
                          : () {
                              Navigator.pop(sheetCtx);
                              _quickUpdateStage(inquiry, stage);
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isCurrentStage
                              ? color
                              // FIX: .withOpacity() → .withAlpha()
                              : color.withAlpha(isDark ? 31 : 26),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                          border: Border.all(
                            color: color.withAlpha(isDark ? 77 : 64),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getStageIcon(stage),
                                size: 14,
                                color: isCurrentStage ? Colors.white : color),
                            const SizedBox(width: 6),
                            Text(
                              stage.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isCurrentStage ? Colors.white : color),
                            ),
                            if (isCurrentStage) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.white),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              Divider(height: 24, color: _borderLight(isDark)),

              _buildQuickActionTile(
                icon: isHotLead
                    ? Icons.local_fire_department_rounded
                    : Icons.local_fire_department_outlined,
                label: isHotLead ? 'Remove Hot Lead' : 'Mark as Hot Lead',
                color: Colors.orange,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _toggleHotLead(inquiry);
                },
              ),
              _buildQuickActionTile(
                icon: Icons.open_in_new_rounded,
                label: 'View Details',
                color: _primaryColor(isDark),
                isDark: isDark,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _navigateTo(InquiryDetailPage(inquiryId: inquiry['id']));
                },
              ),

              SizedBox(height: MediaQuery.of(sheetCtx).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          // FIX: .withOpacity() → .withAlpha()
          color: color.withAlpha(isDark ? 38 : 26),
          borderRadius: BorderRadius.circular(Brand.r(10)),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _textPrimary(isDark)),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded,
          size: 14, color: _textMuted(isDark)),
      onTap: onTap,
    );
  }

  // ─── LOADING SKELETON ──────────────────────────────────────
  Widget _buildLoadingSkeleton(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: _cardBg(isDark),
            borderRadius: BorderRadius.circular(Brand.r(14)),
            border: isDark ? Border.all(color: _borderColor(isDark)) : null,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Brand.darkCard, Brand.darkCardElevated]
                  : [Colors.grey.shade200, Colors.grey.shade100],
            ),
            borderRadius: BorderRadius.circular(Brand.r(18)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 42,
          child: Row(
            children: List.generate(
              4,
              (i) => Container(
                width: 80,
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isDark ? Brand.darkCard : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...List.generate(
          4,
          (i) => Container(
            height: 160,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _cardBg(isDark),
              borderRadius: BorderRadius.circular(Brand.r(18)),
              border: isDark ? Border.all(color: _borderColor(isDark)) : null,
            ),
          ),
        ),
      ],
    );
  }

  // ─── EMPTY STATE ───────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    final hasFilters =
        _filterStage != 'all' || _searchController.text.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                // FIX: .withOpacity() → .withAlpha()
                color: _primaryColor(isDark).withAlpha(isDark ? 26 : 15),
                borderRadius: BorderRadius.circular(Brand.r(24)),
              ),
              child: Icon(
                hasFilters
                    ? Icons.filter_alt_off_rounded
                    : Icons.mail_outline_rounded,
                size: 40,
                color: _textMuted(isDark),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilters ? 'No matching inquiries' : 'No inquiries yet',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary(isDark)),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try adjusting your filters or search'
                  : 'Customer inquiries will appear here when '
                      'they express interest in your machines',
              style: TextStyle(fontSize: 13, color: _textMuted(isDark)),
              textAlign: TextAlign.center,
            ),
            if (hasFilters) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {
                    _filterStage = 'all';
                    _sortBy = 'newest';
                    _applyFilters();
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    // FIX: .withOpacity() → .withAlpha()
                    color: _accentColor(isDark).withAlpha(isDark ? 38 : 26),
                    borderRadius: BorderRadius.circular(Brand.r(12)),
                  ),
                  child: Text(
                    'Clear All Filters',
                    style: TextStyle(
                        color: _accentColor(isDark),
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
