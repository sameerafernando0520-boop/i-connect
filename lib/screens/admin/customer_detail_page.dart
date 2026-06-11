// lib/screens/admin/customer_detail_page.dart
// Fixed: AdminColors.background/surface/textPrimary/primaryLight removed,
//   Future.wait<dynamic>, mounted guards, spread-safe, AlwaysScrollable

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import '../../widgets/common/ic_icons.dart';
import 'admin_ticket_detail_page.dart';
import 'inquiry_detail_page.dart';
import 'admin_installments_page.dart';
import 'installment_detail_page.dart';

class CustomerDetailPage extends StatefulWidget {
  final String customerId;
  const CustomerDetailPage({super.key, required this.customerId});

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage>
    with SingleTickerProviderStateMixin {
  // ─── Controllers ───────────────────────────────────────────
  late TabController _tabController;

  // ─── Data ──────────────────────────────────────────────────
  Map<String, dynamic>? _customer;
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _inquiries = [];
  List<Map<String, dynamic>> _installmentPlans = [];

  // ─── Connector ─────────────────────────────────────────────
  // Currently-assigned connector's user record (joined from
  // users.connector_id). Null when the customer has no connector yet.
  Map<String, dynamic>? _connector;
  // Cache of all eligible connectors (marketers + admins) — populated
  // the first time the admin opens the connector picker.
  List<Map<String, dynamic>> _allConnectors = [];
  bool _loadingAllConnectors = false;
  bool _savingConnector = false;

  // ─── Journey / Suggestion ──────────────────────────────────
  Map<String, dynamic>? _activeSuggestion;
  bool _loadingSuggestion = false;
  bool _updatingScore = false;
  double _sliderValue = 0.0;
  final _stageNoteCtrl = TextEditingController();

  // ─── State ─────────────────────────────────────────────────
  bool _isLoading = true;
  String? _error;

  // ─── Formatting ────────────────────────────────────────────
  static final _lkrFormat = NumberFormat('#,##0', 'en_US');

  // ─── Computed stats ────────────────────────────────────────
  int get _openTickets => _tickets.where((t) {
        final s = (t['status'] ?? '').toString();
        return const {'open', 'assigned', 'in_progress', 'waiting_customer'}
            .contains(s);
      }).length;

  int get _resolvedTickets => _tickets.where((t) {
        final s = (t['status'] ?? '').toString();
        return s == 'resolved' || s == 'closed';
      }).length;

  int get _activePlans =>
      _installmentPlans.where((p) => p['payment_status'] == 'active').length;

  int get _overduePaymentCount {
    int count = 0;
    for (final plan in _installmentPlans) {
      final payments = (plan['installment_payments'] as List?) ?? [];
      for (final p in payments) {
        if (p is Map && p['status'] == 'overdue') count++;
      }
    }
    return count;
  }

  // ═══════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCustomerData();
    _loadActiveSuggestion();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _stageNoteCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  // ═══════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadCustomerData() async {
    final isInitialLoad = _customer == null;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        // 0 — Customer profile
        SupabaseConfig.client
            .from('users')
            .select('*')
            .eq('id', widget.customerId)
            .single(),

        // 1 — Owned machines + catalog info
        SupabaseConfig.client
            .from('customer_machines')
            .select('''
              *,
              machine_catalog!customer_machines_catalog_machine_id_fkey(
                machine_name, brand, model_number, category, product_images
              )
            ''')
            .eq('user_id', widget.customerId)
            .order('created_at', ascending: false),

        // 2 — All service tickets (support + order + inquiry)
        SupabaseConfig.client
            .from('service_tickets')
            .select('''
              *,
              machine_catalog!service_tickets_catalog_machine_id_fkey(
                machine_name, brand, product_images
              )
            ''')
            .eq('user_id', widget.customerId)
            .eq('is_deleted', false)
            .order('created_at', ascending: false),

        // 3 — Installment plans with nested payments & machine info
        SupabaseConfig.client
            .from('installment_plans')
            .select('''
              *,
              customer_machines!installment_plans_customer_machine_id_fkey(
                serial_number,
                machine_catalog!customer_machines_catalog_machine_id_fkey(
                  machine_name, brand, model_number
                )
              ),
              installment_payments!installment_payments_plan_id_fkey(
                id, installment_number, status, due_date, amount, paid_date
              )
            ''')
            .eq('user_id', widget.customerId)
            .order('created_at', ascending: false),
      ]);

      if (!mounted) return;

      final allTickets = List<Map<String, dynamic>>.from(results[2] as List);

      setState(() {
        _customer =
            Map<String, dynamic>.from(results[0] as Map<String, dynamic>);
        _machines = List<Map<String, dynamic>>.from(results[1] as List);
        _tickets =
            allTickets.where((t) => t['ticket_type'] != 'inquiry').toList();
        _inquiries =
            allTickets.where((t) => t['ticket_type'] == 'inquiry').toList();
        _installmentPlans = List<Map<String, dynamic>>.from(results[3] as List);
        _isLoading = false;
        _error = null;
      });

      // Connector profile is a separate query — keep this in a try/catch so
      // a failed connector lookup does not break the rest of the page.
      _loadConnectorProfile();
    } catch (e) {
      if (!mounted) return;

      final message = e.toString().contains('0 rows')
          ? 'Customer not found'
          : 'Failed to load customer details';

      setState(() {
        _isLoading = false;
        _error = message;
      });

      if (!isInitialLoad) {
        _showSnackBar(message, isError: true);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ACTIONS & HELPERS
  // ═══════════════════════════════════════════════════════════

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ── CONNECTOR ────────────────────────────────────────────────
  // Load the currently-assigned connector's profile based on
  // _customer['connector_id']. Called from _loadCustomerData after the
  // customer row lands so the connector card can render without a flash.
  Future<void> _loadConnectorProfile() async {
    final connectorId = _customer?['connector_id'] as String?;
    if (connectorId == null || connectorId.isEmpty) {
      if (mounted) setState(() => _connector = null);
      return;
    }
    try {
      final row = await SupabaseConfig.client
          .from('users')
          .select('id, full_name, role, phone_number, profile_photo, email')
          .eq('id', connectorId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _connector =
          row == null ? null : Map<String, dynamic>.from(row as Map));
    } catch (e) {
      debugPrint('Failed to load connector profile: $e');
    }
  }

  // Fetch all marketers + admins so the picker has something to show.
  // Lazy: only fires the first time the admin opens the picker.
  Future<void> _ensureConnectorListLoaded() async {
    if (_allConnectors.isNotEmpty || _loadingAllConnectors) return;
    setState(() => _loadingAllConnectors = true);
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select(
              'id, full_name, role, phone_number, profile_photo, email, company_name')
          .inFilter('role', const ['marketing_admin', 'admin', 'super_admin'])
          .or('is_active.is.null,is_active.eq.true')
          .order('full_name');
      if (!mounted) return;
      setState(() {
        _allConnectors = List<Map<String, dynamic>>.from(data as List);
        _loadingAllConnectors = false;
      });
    } catch (e) {
      debugPrint('Failed to load connectors: $e');
      if (!mounted) return;
      setState(() => _loadingAllConnectors = false);
    }
  }

  Future<void> _saveConnector(String? newId) async {
    setState(() => _savingConnector = true);
    try {
      await SupabaseConfig.client.from('users').update({
        'connector_id': newId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.customerId);
      if (!mounted) return;
      // Update local cache so UI reflects immediately.
      _customer = {...?_customer, 'connector_id': newId};
      await _loadConnectorProfile();
      if (!mounted) return;
      setState(() => _savingConnector = false);
      _showSnackBar(newId == null
          ? 'Connector cleared'
          : 'Connector updated successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingConnector = false);
      _showSnackBar('Failed to update connector', isError: true);
    }
  }

  String _formatConnectorRole(String role) {
    switch (role) {
      case 'marketing_admin':
        return 'Marketer';
      case 'admin':
      case 'super_admin':
        return 'Admin';
      default:
        return role.isEmpty ? '' : role[0].toUpperCase() + role.substring(1);
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    String digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('0')) {
      digits = '94${digits.substring(1)}';
    } else if (!digits.startsWith('94') && digits.length <= 10) {
      digits = '94$digits';
    }
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : AdminColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  String _formatLKR(dynamic amount) {
    if (amount == null) return 'Rs. 0';
    final val = amount is num
        ? amount.toDouble()
        : double.tryParse(amount.toString()) ?? 0;
    return 'Rs. ${_lkrFormat.format(val)}';
  }

  // ─── Theme helpers — replaces non-existent AdminColors statics ──
  Color _scaffoldBg(bool isDark) => isDark ? Brand.darkBg : Brand.scaffoldLight;

  Color _cardBg(bool isDark) => isDark ? Brand.darkCard : Colors.white;

  Color _itemBg(bool isDark) =>
      isDark ? Brand.darkCardElevated : Brand.scaffoldLight;

  Color _textPrimary(bool isDark) =>
      isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);

  Color _textSub(bool isDark) =>
      isDark ? Brand.darkTextSecondary : Colors.grey.shade500;

  Color _textTertiary(bool isDark) =>
      isDark ? Brand.darkTextTertiary : Colors.grey.shade400;

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _scaffoldBg(isDark);

    if (_isLoading && _customer == null) {
      return _buildLoadingState(isDark, bg);
    }

    if (_error != null && _customer == null) {
      return _buildErrorState(isDark, bg);
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopHeader(isDark),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadCustomerData,
                color: AdminColors.accent,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    children: [
                      _buildProfileCard(isDark),
                      _buildContactCard(isDark),
                      _buildLocationAndConnectorCard(isDark),
                      _buildStatsRow(isDark),
                      _buildSuggestButton(isDark),
                      _buildTabSection(isDark),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── LOADING STATE ─────────────────────────────────────────

  Widget _buildLoadingState(bool isDark, Color bg) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Back button always accessible
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  _buildHeaderButton(
                    isDark,
                    Icons.arrow_back_ios_new_rounded,
                    () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withAlpha(isDark ? 30 : 20),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AdminColors.primary,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading customer details…',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
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

  // ─── ERROR STATE ───────────────────────────────────────────

  Widget _buildErrorState(bool isDark, Color bg) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  _buildHeaderButton(
                    isDark,
                    Icons.arrow_back_ios_new_rounded,
                    () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Customer Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : AdminColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AdminColors.error.withAlpha(20),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(
                          Icons.error_outline_rounded,
                          color: AdminColors.error,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _error ?? 'Something went wrong',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary(isDark),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please check your connection and try again.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _textSub(isDark),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadCustomerData,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── REUSABLE HEADER BUTTON ────────────────────────────────

  Widget _buildHeaderButton(bool isDark, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(12),
          border: isDark ? Border.all(color: Brand.darkBorder) : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Icon(
          icon,
          color: isDark ? Brand.darkTextPrimary : AdminColors.primary,
          size: 18,
        ),
      ),
    );
  }

  // ─── TOP HEADER ────────────────────────────────────────────

  Widget _buildTopHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _buildHeaderButton(
            isDark,
            Icons.arrow_back_ios_new_rounded,
            () => Navigator.pop(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customer Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: isDark ? Brand.darkTextPrimary : AdminColors.primary,
                  ),
                ),
                Text(
                  _customer?['company_name']?.toString() ??
                      'iFrontiers Customer',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSub(isDark),
                  ),
                ),
              ],
            ),
          ),
          _buildHeaderButton(isDark, Icons.refresh_rounded, _loadCustomerData),
        ],
      ),
    );
  }

  // ─── PROFILE CARD ──────────────────────────────────────────

  Widget _buildProfileCard(bool isDark) {
    final name = _customer!['full_name']?.toString() ?? 'Unknown';
    final company = _customer!['company_name']?.toString() ?? '';
    DateTime joinedAt;
    try {
      joinedAt = DateTime.parse(_customer!['created_at']?.toString() ?? '');
    } catch (_) {
      joinedAt = DateTime.now();
    }
    final daysAgo = DateTime.now().difference(joinedAt).inDays;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [Brand.darkCard, Brand.darkCardElevated]
              : [const Color(0xFF0F2557), Brand.royalBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(89),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // ── Avatar ──
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(38),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withAlpha(50),
                    width: 2,
                  ),
                ),
                child: _buildAvatar(name),
              ),
              const SizedBox(width: 16),
              // ── Info ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (company.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        company,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withAlpha(180),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AdminColors.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Colors.white, size: 12),
                              const SizedBox(width: 3),
                              Text(
                                daysAgo < 30
                                    ? 'New Member'
                                    : _activePlans > 0
                                        ? 'Valued Customer'
                                        : 'Member',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Since ${TimeUtils.formatMonthYear(joinedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withAlpha(128),
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
          const SizedBox(height: 18),
          // ── Quick stats bar ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _profileStat(Icons.precision_manufacturing_rounded,
                    '${_machines.length}', 'Machines'),
                _profileStatDivider(),
                _profileStat(Icons.support_agent_rounded, '${_tickets.length}',
                    'Tickets',
                    iconWidget: const IcChatGearIcon(
                        color: AdminColors.accent, size: 20)),
                _profileStatDivider(),
                _profileStat(
                    Icons.mail_rounded, '${_inquiries.length}', 'Inquiries'),
                if (_installmentPlans.isNotEmpty) ...[
                  _profileStatDivider(),
                  _profileStat(
                      Icons.payments_rounded, '$_activePlans', 'Plans'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String name) {
    final photo = _customer?['profile_photo']?.toString() ?? '';
    if (photo.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: photo,
          fit: BoxFit.cover,
          width: 60,
          height: 60,
          placeholder: (_, __) => _initialsWidget(name),
          errorWidget: (_, __, ___) => _initialsWidget(name),
        ),
      );
    }
    return _initialsWidget(name);
  }

  Widget _initialsWidget(String name) {
    return Center(
      child: Text(
        _getInitials(name),
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _profileStat(IconData icon, String value, String label,
      {Widget? iconWidget}) {
    return Column(
      children: [
        iconWidget ?? Icon(icon, color: AdminColors.accent, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
        ),
      ],
    );
  }

  Widget _profileStatDivider() {
    return Container(width: 1, height: 40, color: Colors.white.withAlpha(38));
  }

  // ─── CONTACT CARD ──────────────────────────────────────────

  Widget _buildContactCard(bool isDark) {
    final email = _customer!['email']?.toString() ?? 'N/A';
    final phone = _customer!['phone_number']?.toString() ?? 'N/A';
    final cardBg = _cardBg(isDark);
    final dividerColor = isDark ? Brand.darkBorder : Colors.grey.shade100;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          _contactRow(Icons.email_outlined, email, AdminColors.primary, isDark),
          Divider(color: dividerColor, height: 20),
          _contactRow(Icons.phone_outlined, phone, AdminColors.accent, isDark),
          const SizedBox(height: 14),

          // ── Action buttons: Email · Call · WhatsApp ──
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  Icons.email_rounded,
                  'Email',
                  AdminColors.primary,
                  isDark,
                  () => _launchEmail(email),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  Icons.phone_rounded,
                  'Call',
                  AdminColors.accent,
                  isDark,
                  () => _launchPhone(phone),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  Icons.message_rounded,
                  'WhatsApp',
                  const Color(0xFF25D366),
                  isDark,
                  () => _launchWhatsApp(phone),
                ),
              ),
            ],
          ),

          // ── View Installments button ──
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: Text(
                _overduePaymentCount > 0
                    ? 'View Installments  ⚠️ $_overduePaymentCount Overdue'
                    : 'View All Installments',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminInstallmentsPage(
                    customerIdFilter: widget.customerId,
                  ),
                ),
              ).then((_) {
                if (mounted) _loadCustomerData();
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: _overduePaymentCount > 0
                    ? AdminColors.error
                    : AdminColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── LOCATION + CONNECTOR ──────────────────────────────────
  Widget _buildLocationAndConnectorCard(bool isDark) {
    final province = (_customer?['province'] as String?)?.trim();
    final district = (_customer?['district'] as String?)?.trim();
    final city = (_customer?['city'] as String?)?.trim();
    final cardBg = _cardBg(isDark);
    final dividerColor = isDark ? Brand.darkBorder : Colors.grey.shade100;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.place_outlined,
                size: 18,
                color: isDark ? Brand.darkIconActive : AdminColors.primary),
            const SizedBox(width: 8),
            Text(
              'Location & Connector',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                letterSpacing: 0.3,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _locationRow(
              'Province', province ?? '—', Icons.map_rounded, isDark),
          Divider(color: dividerColor, height: 16),
          _locationRow('District', district ?? '—',
              Icons.location_on_outlined, isDark),
          if (city != null && city.isNotEmpty) ...[
            Divider(color: dividerColor, height: 16),
            _locationRow('City', city, Icons.location_city_rounded, isDark),
          ],
          Divider(color: dividerColor, height: 22),
          // ── Connector row ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AdminColors.accent.withAlpha(isDark ? 38 : 26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _connector != null &&
                        (_connector!['profile_photo'] as String?)?.isNotEmpty ==
                            true
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: _connector!['profile_photo'] as String,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Icon(
                              Icons.support_agent_rounded,
                              color: AdminColors.accent,
                              size: 20),
                          errorWidget: (_, __, ___) => Icon(
                              Icons.support_agent_rounded,
                              color: AdminColors.accent,
                              size: 20),
                        ),
                      )
                    : Icon(Icons.support_agent_rounded,
                        color: AdminColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connector',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _connector?['full_name'] as String? ??
                          'No connector assigned',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _connector == null
                            ? (isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight)
                            : (isDark
                                ? Brand.darkTextPrimary
                                : Brand.royalBlueDark),
                      ),
                    ),
                    if (_connector != null)
                      Text(
                        _formatConnectorRole(
                            (_connector!['role'] as String?) ?? ''),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                      ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _savingConnector ? null : _openConnectorPicker,
                icon: Icon(
                    _connector == null
                        ? Icons.add_rounded
                        : Icons.swap_horiz_rounded,
                    size: 16),
                label: Text(_connector == null ? 'Assign' : 'Change',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _locationRow(
      String label, String value, IconData icon, bool isDark) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AdminColors.primary.withAlpha(isDark ? 30 : 20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AdminColors.primary, size: 18),
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
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value.isEmpty ? '—' : value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: value.isEmpty || value == '—'
                      ? (isDark ? Brand.darkTextTertiary : Brand.subtleLight)
                      : (isDark
                          ? Brand.darkTextPrimary
                          : Brand.royalBlueDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openConnectorPicker() async {
    await _ensureConnectorListLoaded();
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCard : Brand.cardLight,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkBorder
                        : Colors.grey.withAlpha(77),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Row(
                    children: [
                      Icon(Icons.support_agent_rounded,
                          color: isDark
                              ? Brand.darkIconActive
                              : AdminColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Assign Connector',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark),
                        ),
                      ),
                      if (_connector != null)
                        TextButton(
                          onPressed: () => Navigator.pop(sheetCtx, _ClearConnector()),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loadingAllConnectors
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : _allConnectors.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'No marketers or admins are available yet.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: isDark
                                          ? Brand.darkTextSecondary
                                          : Brand.subtleLight),
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _allConnectors.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final c = _allConnectors[i];
                                final selected =
                                    c['id'] == _customer?['connector_id'];
                                final photo = c['profile_photo'] as String?;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => Navigator.pop(
                                      sheetCtx, c['id'] as String),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AdminColors.primary
                                              .withAlpha(31)
                                          : (isDark
                                              ? Brand.darkCardElevated
                                              : Brand.scaffoldLight),
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      border: Border.all(
                                        color: selected
                                            ? AdminColors.primary
                                            : (isDark
                                                ? Brand.darkBorder
                                                : Brand.borderLight),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: AdminColors.primary
                                                .withAlpha(31),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: photo != null &&
                                                  photo.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          11),
                                                  child:
                                                      CachedNetworkImage(
                                                    imageUrl: photo,
                                                    fit: BoxFit.cover,
                                                    placeholder: (_, __) =>
                                                        Icon(
                                                      Icons.person_rounded,
                                                      color: AdminColors
                                                          .primary,
                                                    ),
                                                    errorWidget:
                                                        (_, __, ___) =>
                                                            Icon(
                                                      Icons.person_rounded,
                                                      color: AdminColors
                                                          .primary,
                                                    ),
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.person_rounded,
                                                  color:
                                                      AdminColors.primary,
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                (c['full_name']
                                                        as String?) ??
                                                    'Connector',
                                                style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  fontSize: 14,
                                                  color: isDark
                                                      ? Brand
                                                          .darkTextPrimary
                                                      : Brand
                                                          .royalBlueDark,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatConnectorRole(
                                                    (c['role']
                                                            as String?) ??
                                                        ''),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Brand
                                                          .darkTextSecondary
                                                      : Brand.subtleLight,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (selected)
                                          Icon(Icons.check_circle_rounded,
                                              color: AdminColors.primary),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) return;
    if (result is _ClearConnector) {
      await _saveConnector(null);
    } else if (result is String) {
      await _saveConnector(result);
    }
  }

  Widget _contactRow(IconData icon, String value, Color color, bool isDark) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(isDark ? 30 : 20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Brand.darkTextPrimary : Colors.grey.shade700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _actionButton(
    IconData icon,
    String label,
    Color color,
    bool isDark,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 30 : 20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(isDark ? 60 : 38)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── STATS ROW ─────────────────────────────────────────────

  Widget _buildStatsRow(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _miniStatCard(
              Icons.support_agent_rounded,
              '$_openTickets',
              'Open Tickets',
              _openTickets > 0 ? AdminColors.warning : AdminColors.accent,
              isDark,
              iconWidget: IcChatGearIcon(
                  color: _openTickets > 0
                      ? AdminColors.warning
                      : AdminColors.accent,
                  size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _miniStatCard(
              Icons.check_circle_rounded,
              '$_resolvedTickets',
              'Resolved',
              AdminColors.accent,
              isDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _miniStatCard(
              Icons.warning_amber_rounded,
              '$_overduePaymentCount',
              'Overdue',
              _overduePaymentCount > 0 ? AdminColors.error : AdminColors.accent,
              isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStatCard(
    IconData icon,
    String value,
    String label,
    Color color,
    bool isDark, {
    Widget? iconWidget,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(8),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withAlpha(isDark ? 30 : 25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: iconWidget ?? Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: _textSub(isDark),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── TAB SECTION ───────────────────────────────────────────

  Widget _buildTabSection(bool isDark) {
    final cardBg = _cardBg(isDark);
    final tabHeaderBg = isDark ? Brand.darkCardElevated : Brand.scaffoldLight;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: tabHeaderBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: isDark ? Brand.darkIconActive : AdminColors.primary,
              unselectedLabelColor:
                  isDark ? Brand.darkTextTertiary : Colors.grey.shade500,
              indicatorColor:
                  isDark ? Brand.darkIconActive : AdminColors.primary,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
              dividerColor: Colors.transparent,
              tabs: [
                _tabLabel(Icons.precision_manufacturing_rounded,
                    '${_machines.length}'),
                _tabLabel(Icons.support_agent_rounded, '${_tickets.length}',
                    iconWidget: Builder(
                        builder: (ctx) => IcChatGearIcon(
                            color: IconTheme.of(ctx).color ??
                                AdminColors.primary,
                            size: 15))),
                _tabLabel(Icons.mail_rounded, '${_inquiries.length}'),
                _tabLabel(
                    Icons.payments_rounded, '${_installmentPlans.length}'),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _buildTabContent(isDark),
          ),
        ],
      ),
    );
  }

  Widget _tabLabel(IconData icon, String count, {Widget? iconWidget}) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconWidget ?? Icon(icon, size: 15),
          const SizedBox(width: 4),
          Text(count),
        ],
      ),
    );
  }

  Widget _buildTabContent(bool isDark) {
    switch (_tabController.index) {
      case 0:
        return _buildMachinesContent(isDark);
      case 1:
        return _buildTicketsContent(isDark);
      case 2:
        return _buildInquiriesContent(isDark);
      case 3:
        return _buildInstallmentsContent(isDark);
      default:
        return _buildMachinesContent(isDark);
    }
  }

  // ─── TAB 0: MACHINES ──────────────────────────────────────

  Widget _buildMachinesContent(bool isDark) {
    if (_machines.isEmpty) {
      return _emptyTab(
        isDark,
        Icons.precision_manufacturing_outlined,
        'No machines registered',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: _machines.map((machine) {
          final catalog = machine['machine_catalog'] as Map<String, dynamic>?;
          final status = (machine['status'] ?? 'active').toString();
          final statusColor = AdminColors.statusColor(status);

          String? purchaseDate;
          try {
            purchaseDate = machine['purchase_date']?.toString();
          } catch (_) {}

          bool warrantyExpired = false;
          try {
            final warrantyEnd = machine['warranty_end_date']?.toString();
            if (warrantyEnd != null) {
              final dt = DateTime.tryParse(warrantyEnd);
              if (dt != null) {
                warrantyExpired = dt.isBefore(DateTime.now());
              }
            }
          } catch (_) {}

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _itemBg(isDark),
              borderRadius: BorderRadius.circular(14),
              border: warrantyExpired
                  ? Border.all(color: AdminColors.error.withAlpha(50))
                  : isDark
                      ? Border.all(color: Brand.darkBorder)
                      : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AdminColors.primary.withAlpha(isDark ? 30 : 20),
                        AdminColors.accent.withAlpha(isDark ? 30 : 20),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.precision_manufacturing_rounded,
                    color: AdminColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        catalog?['machine_name']?.toString() ??
                            'Unknown Machine',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary(isDark),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'S/N: ${machine['serial_number'] ?? 'N/A'}',
                            style: TextStyle(
                                fontSize: 12, color: _textSub(isDark)),
                          ),
                          _statusTag(status.toUpperCase(), statusColor, isDark),
                          if (warrantyExpired)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AdminColors.error.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 9,
                                    color: AdminColors.error,
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    'WARRANTY',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AdminColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (purchaseDate != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Purchased: ${TimeUtils.formatDateFull(DateTime.tryParse(purchaseDate) ?? DateTime.now())}',
                          style: TextStyle(
                            fontSize: 12,
                            color: _textTertiary(isDark),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (catalog?['brand'] != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withAlpha(isDark ? 30 : 15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      catalog!['brand'].toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Brand.darkIconActive : AdminColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── TAB 1: TICKETS ───────────────────────────────────────

  Widget _buildTicketsContent(bool isDark) {
    if (_tickets.isEmpty) {
      return _emptyTab(
        isDark,
        Icons.support_agent_outlined,
        'No support tickets',
        iconWidget: IcChatGearIcon(
            color: isDark ? Brand.darkTextSecondary : Brand.royalBlue,
            size: 36),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: _tickets.map((ticket) {
          final status = (ticket['status'] ?? 'open').toString();
          final priority = (ticket['priority'] ?? 'medium').toString();
          final statusColor = AdminColors.statusColor(status);
          final priorityColor = AdminColors.priorityColor(priority);
          DateTime createdAt;
          try {
            createdAt = DateTime.parse(ticket['created_at']?.toString() ?? '');
          } catch (_) {
            createdAt = DateTime.now();
          }

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AdminTicketDetailPage(ticketId: ticket['id'] as String),
                ),
              ).then((_) {
                if (mounted) _loadCustomerData();
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _itemBg(isDark),
                borderRadius: BorderRadius.circular(14),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 70,
                    decoration: BoxDecoration(
                      color: priorityColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _statusTag(
                                status.toUpperCase().replaceAll('_', ' '),
                                statusColor,
                                isDark,
                              ),
                              const SizedBox(width: 6),
                              _statusTag(
                                priority.toUpperCase(),
                                priorityColor,
                                isDark,
                              ),
                              const Spacer(),
                              Text(
                                TimeUtils.getTimeAgo(createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _textTertiary(isDark),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ticket['subject']?.toString() ?? 'No subject',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary(isDark),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ticket['ticket_number']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: _textTertiary(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _itemBg(isDark),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            isDark ? Border.all(color: Brand.darkBorder) : null,
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : AdminColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── TAB 2: INQUIRIES ─────────────────────────────────────

  Widget _buildInquiriesContent(bool isDark) {
    if (_inquiries.isEmpty) {
      return _emptyTab(
        isDark,
        Icons.mail_outline_rounded,
        'No inquiries submitted',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: _inquiries.map((inquiry) {
          final machine = inquiry['machine_catalog'] as Map<String, dynamic>?;
          final salesStage = (inquiry['sales_stage'] ?? 'new').toString();
          final stageColor = _getSalesStageColor(salesStage);
          DateTime createdAt;
          try {
            createdAt = DateTime.parse(inquiry['created_at']?.toString() ?? '');
          } catch (_) {
            createdAt = DateTime.now();
          }

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      InquiryDetailPage(inquiryId: inquiry['id'] as String),
                ),
              ).then((_) {
                if (mounted) _loadCustomerData();
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _itemBg(isDark),
                borderRadius: BorderRadius.circular(14),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AdminColors.primary.withAlpha(isDark ? 30 : 20),
                          AdminColors.accent.withAlpha(isDark ? 30 : 20),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      color: AdminColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          machine?['machine_name']?.toString() ??
                              inquiry['subject']?.toString() ??
                              'Inquiry',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _textPrimary(isDark),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _statusTag(
                              salesStage.toUpperCase(),
                              stageColor,
                              isDark,
                            ),
                            const Spacer(),
                            Text(
                              TimeUtils.getTimeAgo(createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: _textTertiary(isDark),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _itemBg(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          isDark ? Border.all(color: Brand.darkBorder) : null,
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: isDark
                          ? Brand.darkTextSecondary
                          : AdminColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── TAB 3: INSTALLMENTS ──────────────────────────────────

  Widget _buildInstallmentsContent(bool isDark) {
    if (_installmentPlans.isEmpty) {
      return _emptyTab(
        isDark,
        Icons.payments_outlined,
        'No installment plans',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: _installmentPlans.map((plan) {
          // ── Extract data ──
          final customerMachine =
              plan['customer_machines'] as Map<String, dynamic>?;
          final catalog =
              customerMachine?['machine_catalog'] as Map<String, dynamic>?;
          final machineName =
              catalog?['machine_name']?.toString() ?? 'Unknown Machine';
          final brand = catalog?['brand']?.toString();
          final serial = customerMachine?['serial_number']?.toString() ?? 'N/A';
          final paymentStatus = (plan['payment_status'] ?? 'active').toString();
          final totalWithInterest =
              (plan['total_with_interest'] as num?)?.toDouble() ?? 0;
          final installmentAmount =
              (plan['installment_amount'] as num?)?.toDouble() ?? 0;
          final numInstallments =
              (plan['num_installments'] as num?)?.toInt() ?? 0;

          // ── Payment progress ──
          final payments = List<Map<String, dynamic>>.from(
              (plan['installment_payments'] as List?) ?? []);
          final paidCount = payments.where((p) => p['status'] == 'paid').length;
          final overdueCount =
              payments.where((p) => p['status'] == 'overdue').length;
          final progress =
              numInstallments > 0 ? paidCount / numInstallments : 0.0;

          // ── Status color ──
          Color statusColor;
          IconData statusIcon;
          switch (paymentStatus) {
            case 'completed':
              statusColor = AdminColors.accent;
              statusIcon = Icons.check_circle_rounded;
              break;
            case 'defaulted':
              statusColor = AdminColors.error;
              statusIcon = Icons.cancel_rounded;
              break;
            default:
              statusColor =
                  overdueCount > 0 ? AdminColors.warning : AdminColors.info;
              statusIcon = overdueCount > 0
                  ? Icons.warning_amber_rounded
                  : Icons.schedule_rounded;
          }

          // ── Next due date ──
          String? nextDueText;
          final pendingPayments = payments
              .where(
                  (p) => p['status'] == 'pending' || p['status'] == 'overdue')
              .toList();
          pendingPayments.sort(
              (a, b) => (a['due_date'] ?? '').compareTo(b['due_date'] ?? ''));
          if (pendingPayments.isNotEmpty) {
            try {
              final nextDue =
                  DateTime.parse(pendingPayments.first['due_date'] ?? '');
              final daysUntil = nextDue.difference(DateTime.now()).inDays;
              if (daysUntil < 0) {
                nextDueText = '${daysUntil.abs()}d overdue';
              } else if (daysUntil == 0) {
                nextDueText = 'Due today';
              } else {
                nextDueText = 'Due in ${daysUntil}d';
              }
            } catch (_) {}
          }

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      InstallmentDetailPage(planId: plan['id'] as String),
                ),
              ).then((_) {
                if (mounted) _loadCustomerData();
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _itemBg(isDark),
                borderRadius: BorderRadius.circular(16),
                border: overdueCount > 0
                    ? Border.all(
                        color: AdminColors.error.withAlpha(60),
                        width: 1.5,
                      )
                    : isDark
                        ? Border.all(color: Brand.darkBorder)
                        : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Row 1: Machine + status ──
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(isDark ? 30 : 20),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(statusIcon, color: statusColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              machineName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _textPrimary(isDark),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  'S/N: $serial',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _textSub(isDark),
                                  ),
                                ),
                                if (brand != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AdminColors.primary
                                          .withAlpha(isDark ? 30 : 15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      brand,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Brand.darkIconActive
                                            : AdminColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      _statusTag(
                        paymentStatus.toUpperCase(),
                        statusColor,
                        isDark,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Row 2: Financial info ──
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 12,
                                color: _textTertiary(isDark),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatLKR(totalWithInterest),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _textPrimary(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monthly',
                              style: TextStyle(
                                fontSize: 12,
                                color: _textTertiary(isDark),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatLKR(installmentAmount),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _textPrimary(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (nextDueText != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: overdueCount > 0
                                ? AdminColors.error.withAlpha(20)
                                : AdminColors.warning.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            nextDueText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: overdueCount > 0
                                  ? AdminColors.error
                                  : AdminColors.warning,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Row 3: Progress bar ──
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor: isDark
                                    ? Brand.darkBorder
                                    : Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  paymentStatus == 'completed'
                                      ? AdminColors.accent
                                      : overdueCount > 0
                                          ? AdminColors.error
                                          : AdminColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$paidCount of $numInstallments paid'
                              '${overdueCount > 0 ? '  •  $overdueCount overdue' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: _textSub(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── SHARED HELPERS ────────────────────────────────────────

  Widget _statusTag(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _getSalesStageColor(String stage) {
    switch (stage.toLowerCase()) {
      case 'new':
        return AdminColors.info;
      case 'contacted':
        return const Color(0xFF8E24AA);
      case 'quoted':
        return AdminColors.warning;
      case 'negotiating':
        return const Color(0xFFFF8F00);
      case 'won':
        return AdminColors.accent;
      case 'lost':
        return AdminColors.error;
      default:
        return Colors.grey;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // JOURNEY / SUGGESTION SYSTEM
  // ═══════════════════════════════════════════════════════════

  /// Fetches the active suggestion for this customer (if any).
  Future<void> _loadActiveSuggestion() async {
    if (!mounted) return;
    setState(() => _loadingSuggestion = true);
    try {
      final data = await SupabaseConfig.client
          .from('machine_suggestions')
          .select('''
            id,
            journey_score,
            stage_note,
            is_active,
            viewed_at,
            clicked_at,
            milestone_25_sent,
            milestone_50_sent,
            milestone_75_sent,
            milestone_100_sent,
            score_updated_at,
            batch:suggestion_batches!batch_id(
              id,
              note,
              machine:machine_catalog!machine_id(
                id,
                machine_name,
                image_url
              )
            )
          ''')
          .eq('customer_id', widget.customerId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _activeSuggestion =
            data != null ? Map<String, dynamic>.from(data) : null;
        if (_activeSuggestion != null) {
          final score =
              (_activeSuggestion!['journey_score'] as int? ?? 0).toDouble();
          _sliderValue = (score / 25.0).roundToDouble() * 25.0;
          _stageNoteCtrl.text =
              _activeSuggestion!['stage_note'] as String? ?? '';
        }
      });
    } catch (_) {
      // non-critical
    } finally {
      if (mounted) setState(() => _loadingSuggestion = false);
    }
  }

  Future<void> _updateJourneyScore() async {
    if (_activeSuggestion == null) return;
    if (!mounted) return;
    setState(() => _updatingScore = true);
    try {
      final score = _sliderValue.round();
      final res = await SupabaseConfig.client.functions.invoke(
        'update-journey-score',
        body: {
          'suggestion_id': _activeSuggestion!['id'],
          'new_score': score,
          'stage_note': _stageNoteCtrl.text.trim().isEmpty
              ? null
              : _stageNoteCtrl.text.trim(),
          'admin_id': SupabaseConfig.client.auth.currentUser?.id,
        },
      );
      if (!mounted) return;
      final firedMilestones =
          (res.data?['firedMilestones'] as List?)?.cast<int>() ?? [];
      if (firedMilestones.isNotEmpty) {
        final labels = firedMilestones.map((m) => '$m%').join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🎯 Milestone(s) reached: $labels — notification sent'),
          backgroundColor: AdminColors.success,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Score updated to $score%'),
          backgroundColor: AdminColors.primary,
        ));
      }
      await _loadActiveSuggestion();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to update: $e'),
        backgroundColor: AdminColors.error,
      ));
    } finally {
      if (mounted) setState(() => _updatingScore = false);
    }
  }

  Future<void> _withdrawSuggestion() async {
    if (_activeSuggestion == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw Suggestion?'),
        content: const Text(
            'This will remove the active suggestion from this customer\'s home screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AdminColors.error),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    try {
      await SupabaseConfig.client
          .from('machine_suggestions')
          .update({'is_active': false})
          .eq('id', _activeSuggestion!['id'] as String);
      if (!mounted) return;
      setState(() {
        _activeSuggestion = null;
        _sliderValue = 0;
        _stageNoteCtrl.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Suggestion withdrawn')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AdminColors.error,
      ));
    }
  }

  Widget _buildSuggestButton(bool isDark) {
    if (_loadingSuggestion) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: _cardBg(isDark),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AdminColors.primary),
              ),
            ),
          ),
        ),
      );
    }
    if (_activeSuggestion != null) {
      return _buildActiveSuggestionCard(isDark);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OutlinedButton.icon(
        onPressed: () => _showSuggestSheet(isDark),
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('Suggest a Machine'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AdminColors.primary,
          side: BorderSide(color: AdminColors.primary.withAlpha(128)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildActiveSuggestionCard(bool isDark) {
    final s = _activeSuggestion!;
    final batch = s['batch'] as Map<String, dynamic>?;
    final machine = batch?['machine'] as Map<String, dynamic>?;
    final machineName = machine?['machine_name'] as String? ?? 'Machine';
    final imageUrl = machine?['image_url'] as String?;
    final score = (s['journey_score'] as int? ?? 0);
    final progress = score / 100.0;
    final m25 = s['milestone_25_sent'] as bool? ?? false;
    final m50 = s['milestone_50_sent'] as bool? ?? false;
    final m75 = s['milestone_75_sent'] as bool? ?? false;
    final m100 = s['milestone_100_sent'] as bool? ?? false;
    final viewedAt = s['viewed_at'];
    final clickedAt = s['clicked_at'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(16),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const SizedBox(),
                              errorWidget: (_, __, ___) => Icon(
                                Icons.precision_manufacturing,
                                size: 20,
                                color: AdminColors.primary,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.precision_manufacturing,
                            size: 20,
                            color: AdminColors.primary,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next Journey',
                          style: TextStyle(
                              fontSize: 11,
                              color: _textSub(isDark),
                              fontWeight: FontWeight.w500),
                        ),
                        Text(
                          machineName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary(isDark)),
                        ),
                      ],
                    ),
                  ),
                  if (clickedAt != null)
                    _engagementChip('Clicked', AdminColors.success)
                  else if (viewedAt != null)
                    _engagementChip('Viewed', AdminColors.info)
                  else
                    _engagementChip('Not seen', Colors.grey),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor:
                      isDark ? Brand.darkBorder : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    score == 100
                        ? AdminColors.success
                        : score >= 75
                            ? Brand.lightGreen
                            : AdminColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$score% ready',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary(isDark)),
                  ),
                  Row(
                    children: [
                      _milestoneDot('25', isDark, m25, score >= 25),
                      const SizedBox(width: 4),
                      _milestoneDot('50', isDark, m50, score >= 50),
                      const SizedBox(width: 4),
                      _milestoneDot('75', isDark, m75, score >= 75),
                      const SizedBox(width: 4),
                      _milestoneDot('100', isDark, m100, score >= 100),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('0%',
                      style: TextStyle(
                          fontSize: 11, color: _textSub(isDark))),
                  Expanded(
                    child: Slider(
                      value: _sliderValue,
                      min: 0,
                      max: 100,
                      divisions: 4,
                      activeColor: AdminColors.primary,
                      inactiveColor: isDark
                          ? Brand.darkBorder
                          : Colors.grey.shade300,
                      label: '${_sliderValue.round()}%',
                      onChanged: _updatingScore
                          ? null
                          : (v) => setState(() => _sliderValue = v),
                    ),
                  ),
                  Text('100%',
                      style: TextStyle(
                          fontSize: 11, color: _textSub(isDark))),
                ],
              ),
              TextField(
                controller: _stageNoteCtrl,
                maxLines: 2,
                style: TextStyle(
                    fontSize: 13, color: _textPrimary(isDark)),
                decoration: InputDecoration(
                  hintText:
                      'Stage note (internal, not shown to customer)…',
                  hintStyle:
                      TextStyle(fontSize: 13, color: _textSub(isDark)),
                  filled: true,
                  fillColor: isDark
                      ? Brand.darkCardElevated
                      : Brand.scaffoldLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _updatingScore ? null : _updateJourneyScore,
                      icon: _updatingScore
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save, size: 16),
                      label: Text(_updatingScore ? 'Saving…' : 'Save Score'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () =>
                        _showNudgeDialog(s['id'] as String, score),
                    icon: const Icon(Icons.message_outlined),
                    tooltip: 'Send Nudge',
                    style: IconButton.styleFrom(
                      foregroundColor: AdminColors.primary,
                      backgroundColor: AdminColors.primary.withAlpha(15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _withdrawSuggestion,
                    icon: const Icon(Icons.close),
                    tooltip: 'Withdraw',
                    style: IconButton.styleFrom(
                      foregroundColor: AdminColors.error,
                      backgroundColor: AdminColors.error.withAlpha(15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _milestoneDot(
      String label, bool isDark, bool sent, bool reached) {
    final color = sent
        ? AdminColors.success
        : reached
            ? AdminColors.primary
            : (isDark ? Brand.darkBorder : Colors.grey.shade300);
    return Column(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: _textSub(isDark))),
      ],
    );
  }

  Widget _engagementChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color),
      ),
    );
  }

  Future<void> _showNudgeDialog(
      String suggestionId, int currentScore) async {
    final msgCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBg(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Brand.darkBorder
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Send Nudge Message',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary(isDark))),
            const SizedBox(height: 4),
            Text(
              'This message will appear as a push notification and in-app message.',
              style: TextStyle(fontSize: 13, color: _textSub(isDark)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: msgCtrl,
              autofocus: true,
              maxLines: 4,
              style: TextStyle(
                  fontSize: 14, color: _textPrimary(isDark)),
              decoration: InputDecoration(
                hintText: 'Type your message…',
                hintStyle: TextStyle(color: _textSub(isDark)),
                filled: true,
                fillColor: isDark
                    ? Brand.darkCardElevated
                    : Brand.scaffoldLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final msg = msgCtrl.text.trim();
                  if (msg.isEmpty) return;
                  Navigator.pop(sheetCtx);
                  try {
                    await SupabaseConfig.client.functions.invoke(
                      'send-nudge-message',
                      body: {
                        'suggestion_id': suggestionId,
                        'customer_id': widget.customerId,
                        'admin_id':
                            SupabaseConfig.client.auth.currentUser?.id,
                        'message': msg,
                        'current_score': currentScore,
                      },
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nudge sent ✓')));
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Failed to send nudge: $e'),
                      backgroundColor: AdminColors.error,
                    ));
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Send Message'),
              ),
            ),
          ],
        ),
      ),
    );
    msgCtrl.dispose();
  }

  void _showSuggestSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuggestMachineSheet(
        customerId: widget.customerId,
        isDark: isDark,
        onCreated: _loadActiveSuggestion,
      ),
    );
  }

  // ── Empty-tab placeholder ────────────────────────────────────────────────
  Widget _emptyTab(bool isDark, IconData icon, String message,
      {Widget? iconWidget}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.darkCard
                    : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: iconWidget ??
                  Icon(
                    icon,
                    size: 36,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : Brand.royalBlue,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Brand.darkTextSecondary
                    : Brand.royalBlueDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
} // end _CustomerDetailPageState

// ═══════════════════════════════════════════════════════════
// SUGGEST A MACHINE BOTTOM SHEET
// ═══════════════════════════════════════════════════════════

class _SuggestMachineSheet extends StatefulWidget {
  final String customerId;
  final bool isDark;
  final VoidCallback onCreated;
  const _SuggestMachineSheet({
    required this.customerId,
    required this.isDark,
    required this.onCreated,
  });

  @override
  State<_SuggestMachineSheet> createState() =>
      _SuggestMachineSheetState();
}

class _SuggestMachineSheetState extends State<_SuggestMachineSheet> {
  Map<String, dynamic>? _selectedMachine;
  final _noteCtrl = TextEditingController();
  bool _submitting = false;

  Color get _bg => widget.isDark ? Brand.darkCard : Colors.white;
  Color get _textPrimary =>
      widget.isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
  Color get _textSub =>
      widget.isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedMachine == null) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      final batch = await SupabaseConfig.client
          .from('suggestion_batches')
          .insert({
            'machine_id': _selectedMachine!['id'] as String,
            'note': _noteCtrl.text.trim().isEmpty
                ? null
                : _noteCtrl.text.trim(),
            'suggested_by':
                SupabaseConfig.client.auth.currentUser?.id,
          })
          .select('id')
          .single();

      await SupabaseConfig.client.from('machine_suggestions').insert({
        'batch_id': batch['id'] as String,
        'customer_id': widget.customerId,
        'journey_score': 0,
      });

      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AdminColors.error,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Brand.darkBorder
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Suggest a Machine',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'This will appear on the customer\'s home screen as their next journey goal.',
            style: TextStyle(fontSize: 13, color: _textSub),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async {
              final machine =
                  await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) =>
                    _MachinePickerDialog(isDark: widget.isDark),
              );
              if (machine != null) {
                setState(() => _selectedMachine = machine);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Brand.darkCardElevated
                    : Brand.scaffoldLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.isDark
                      ? Brand.darkBorder
                      : Brand.borderLight,
                ),
              ),
              child: Row(
                children: [
                  if (_selectedMachine != null &&
                      _selectedMachine!['image_url'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl:
                            _selectedMachine!['image_url'] as String,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const SizedBox(width: 36, height: 36),
                        errorWidget: (_, __, ___) => Icon(
                          Icons.precision_manufacturing,
                          size: 24,
                          color: AdminColors.primary,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.precision_manufacturing,
                      size: 24,
                      color: _selectedMachine != null
                          ? AdminColors.primary
                          : _textSub,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedMachine != null
                          ? (_selectedMachine!['machine_name'] as String? ??
                              'Machine')
                          : 'Select a machine…',
                      style: TextStyle(
                        fontSize: 14,
                        color: _selectedMachine != null
                            ? _textPrimary
                            : _textSub,
                        fontWeight: _selectedMachine != null
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: _textSub),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            style: TextStyle(fontSize: 13, color: _textPrimary),
            decoration: InputDecoration(
              hintText: 'Internal note (optional)…',
              hintStyle: TextStyle(color: _textSub),
              filled: true,
              fillColor: widget.isDark
                  ? Brand.darkCardElevated
                  : Brand.scaffoldLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_selectedMachine == null || _submitting)
                  ? null
                  : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AdminColors.primary,
                disabledBackgroundColor:
                    AdminColors.primary.withAlpha(80),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Create Suggestion',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// MACHINE PICKER DIALOG
// ═══════════════════════════════════════════════════════════

class _MachinePickerDialog extends StatefulWidget {
  final bool isDark;
  const _MachinePickerDialog({required this.isDark});

  @override
  State<_MachinePickerDialog> createState() =>
      _MachinePickerDialogState();
}

class _MachinePickerDialogState extends State<_MachinePickerDialog> {
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMachines();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMachines() async {
    try {
      final data = await SupabaseConfig.client
          .from('machine_catalog')
          .select('id, machine_name, image_url, category')
          .order('machine_name')
          .limit(200);
      if (!mounted) return;
      setState(() {
        _machines = List<Map<String, dynamic>>.from(data as List);
        _filtered = List<Map<String, dynamic>>.from(_machines);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List<Map<String, dynamic>>.from(_machines)
          : _machines.where((m) {
              final name =
                  (m['machine_name'] as String? ?? '').toLowerCase();
              final cat =
                  (m['category'] as String? ?? '').toLowerCase();
              return name.contains(q) || cat.contains(q);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? Brand.darkCard : Colors.white;
    final textPrimary =
        isDark ? Brand.darkTextPrimary : const Color(0xFF1E293B);
    final textSub =
        isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select Machine',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: textPrimary),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: textSub),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search machines…',
                  hintStyle: TextStyle(color: textSub),
                  prefixIcon: Icon(Icons.search, color: textSub),
                  filled: true,
                  fillColor: isDark
                      ? Brand.darkCardElevated
                      : Brand.scaffoldLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AdminColors.primary),
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Text('No machines found',
                              style: TextStyle(color: textSub)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final m = _filtered[i];
                            final name =
                                m['machine_name'] as String? ?? '';
                            final imageUrl =
                                m['image_url'] as String?;
                            final cat =
                                m['category'] as String? ?? '';
                            return ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color:
                                      AdminColors.primary.withAlpha(15),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: imageUrl != null
                                    ? ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) =>
                                              const SizedBox(),
                                          errorWidget: (_, __, ___) =>
                                              Icon(
                                            Icons
                                                .precision_manufacturing,
                                            size: 22,
                                            color: AdminColors.primary,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.precision_manufacturing,
                                        size: 22,
                                        color: AdminColors.primary,
                                      ),
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: textPrimary),
                              ),
                              subtitle: cat.isNotEmpty
                                  ? Text(cat,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: textSub))
                                  : null,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              onTap: () =>
                                  Navigator.pop(context, m),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sentinel result returned from the connector picker when the admin taps
// "Remove" — distinguishable from the String id of a chosen connector.
class _ClearConnector {
  const _ClearConnector();
}
