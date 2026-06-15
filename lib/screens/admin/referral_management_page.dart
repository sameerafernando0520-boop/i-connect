import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import '../../widgets/admin/shimmer_loading.dart';
import '../../widgets/ds/ds_widgets.dart';
import 'referral_rules_page.dart';

class ReferralManagementPage extends StatefulWidget {
  const ReferralManagementPage({super.key});

  @override
  State<ReferralManagementPage> createState() => _ReferralManagementPageState();
}

class _ReferralManagementPageState extends State<ReferralManagementPage> {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0.00', 'en_US');
  final _searchCtrl = TextEditingController();

  bool _loadingOverview = true;
  bool _loadingList = true;
  String? _listError;
  Map<String, dynamic> _overview = {};
  List<Map<String, dynamic>> _referrals = [];
  String? _statusFilter;
  bool _showSearch = false;
  Timer? _debounce;

  String? get _userId => _supabase.auth.currentUser?.id;

  // FIX: Use AdminColors named constants for semantic colors.
  // static const tuples — colors must be compile-time const so we
  // use literal values that exactly match AdminColors statics.
  static const _filters = <(String?, String, Color)>[
    (null, 'All', AdminColors.primary),
    ('pending', 'Pending', Color(0xFF94A3B8)),
    ('signed_up', 'Signed Up', Color(0xFF8B5CF6)),
    ('cooling', 'Cooling', Color(0xFF06B6D4)),
    // FIX: AdminColors.success = 0xFF22C55E
    ('approved', 'Approved', Color(0xFF22C55E)),
    // FIX: AdminColors.info = 0xFF3B82F6
    ('paid', 'Paid', Color(0xFF3B82F6)),
    // FIX: AdminColors.error = 0xFFEF4444
    ('rejected', 'Rejected', Color(0xFFEF4444)),
    // FIX: AdminColors.warning = 0xFFF59E0B
    ('expired', 'Expired', Color(0xFFF59E0B)),
  ];

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // FIX: Explicit <dynamic> type on Future.wait
  Future<void> _loadAll() async {
    await Future.wait<dynamic>([_loadOverview(), _loadList()]);
  }

  Future<void> _loadOverview() async {
    setState(() => _loadingOverview = true);
    try {
      final res = await _supabase.rpc('get_admin_referral_overview');
      if (!mounted) return;
      setState(() {
        _overview = res is Map<String, dynamic> ? res : {};
        _loadingOverview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overview = {};
        _loadingOverview = false;
      });
    }
  }

  Future<void> _loadList() async {
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      final res = await _supabase.rpc('get_admin_referrals_list', params: {
        'p_status_filter': _statusFilter,
        'p_search':
            _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _referrals = List<Map<String, dynamic>>.from(res as List? ?? []);
        _loadingList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = e.toString();
        _loadingList = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _loadList);
  }

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int _i(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  // ═══════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: DsPageHeader(
        title: 'Referral Program',
        accent: HeroAccent.navy,
        actions: [
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchCtrl.clear();
                  _loadList();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Commission Rules',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReferralRulesPage()),
            ).then((_) {
              if (mounted) _loadAll();
            }),
          ),
        ],
        bottom: _showSearch
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search referrals…',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(179)),
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                ),
                onChanged: _onSearchChanged,
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: AdminColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildOverview(isDark),
              _buildFilterChips(isDark),
              _loadingList
                  ? _buildShimmer(isDark)
                  : _listError != null
                      ? _buildError(isDark)
                      : _referrals.isEmpty
                          ? _buildEmpty(isDark)
                          : _buildList(isDark),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  1. OVERVIEW STATS
  // ═══════════════════════════════════════════════════════

  Widget _buildOverview(bool isDark) {
    if (_loadingOverview) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ShimmerLoading(
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        color: AdminColors.card(context),
                        borderRadius: BorderRadius.circular(Brand.r(16)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShimmerLoading(
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        color: AdminColors.card(context),
                        borderRadius: BorderRadius.circular(Brand.r(16)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ShimmerLoading(
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        color: AdminColors.card(context),
                        borderRadius: BorderRadius.circular(Brand.r(16)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShimmerLoading(
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        color: AdminColors.card(context),
                        borderRadius: BorderRadius.circular(Brand.r(16)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final totalRefs = _i(_overview['total_referrals']);
    final successRefs = _i(_overview['successful_referrals']);
    final pendingRefs = _i(_overview['pending_referrals']);
    final totalCommission = _d(_overview['total_commission_earned']);
    final pendingPayout = _d(_overview['pending_payout']);
    final convRate = totalRefs > 0
        ? (successRefs / totalRefs * 100).toStringAsFixed(1)
        : '0.0';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statCard(
                  isDark: isDark,
                  title: 'Total Referrals',
                  value: '$totalRefs',
                  sub: '$successRefs successful',
                  icon: Icons.people_alt_rounded,
                  // FIX: Use AdminColors named constant
                  color: AdminColors.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  isDark: isDark,
                  title: 'Conversion Rate',
                  value: '$convRate%',
                  sub: '$pendingRefs pending',
                  icon: Icons.trending_up_rounded,
                  color: AdminColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  isDark: isDark,
                  title: 'Total Commission',
                  value: 'Rs. ${_fmt.format(totalCommission)}',
                  icon: Icons.payments_rounded,
                  color: AdminColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  isDark: isDark,
                  title: 'Pending Payout',
                  value: 'Rs. ${_fmt.format(pendingPayout)}',
                  icon: Icons.schedule_rounded,
                  // FIX: Use AdminColors.warning
                  color: AdminColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required bool isDark,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(Brand.r(9)),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AdminColors.textSub(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AdminColors.text(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.textHint(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  2. FILTER CHIPS
  // ═══════════════════════════════════════════════════════

  Widget _buildFilterChips(bool isDark) {
    return Container(
      color: AdminColors.bg(context),
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: _filters.map((f) {
            final selected = _statusFilter == f.$1;
            return Padding(
              // FIX: Add top padding to match quotation page
              padding: const EdgeInsets.only(right: 8, top: 10),
              child: GestureDetector(
                onTap: () {
                  // FIX: Avoid redundant load when tapping
                  //      already-selected filter
                  final newFilter = selected ? null : f.$1;
                  if (newFilter == _statusFilter) return;
                  setState(() => _statusFilter = newFilter);
                  _loadList();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? f.$3.withAlpha(isDark ? 40 : 25)
                        : AdminColors.card(context),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                    border: Border.all(
                      color: selected
                          ? f.$3.withAlpha(100)
                          : AdminColors.border(context),
                    ),
                  ),
                  child: Text(
                    f.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? f.$3 : AdminColors.textSub(context),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  3. REFERRAL LIST
  // ═══════════════════════════════════════════════════════

  Widget _buildList(bool isDark) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: _referrals.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildReferralCard(_referrals[i], isDark),
    );
  }

  Widget _buildReferralCard(Map<String, dynamic> ref, bool isDark) {
    final status = ref['status']?.toString() ?? 'pending';
    final sColor = _statusColor(status);
    final commission = _d(ref['commission_amount']);
    final canApprove = status == 'cooling' || status == 'signed_up';
    final canReject = !['paid', 'rejected', 'expired'].contains(status);

    return Container(
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(16))),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: sColor.withAlpha(26),
              borderRadius: BorderRadius.circular(Brand.r(12)),
            ),
            child: Icon(
              Icons.people_alt_rounded,
              size: 20,
              color: sColor,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref['referrer_name']?.toString() ?? 'Unknown',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.text(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '→ ',
                            style: TextStyle(
                              color: AdminColors.textHint(context),
                            ),
                          ),
                          TextSpan(
                            text: ref['referred_name']?.toString() ?? 'Unknown',
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSub(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (commission > 0)
                    Text(
                      'Rs. ${_fmt.format(commission)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(context),
                      ),
                    ),
                  const SizedBox(height: 4),
                  _statusBadge(status, sColor),
                ],
              ),
            ],
          ),
          children: [
            _detailRow('Code', ref['code_used'], isDark),
            _detailRow('Referrer Email', ref['referrer_email'], isDark),
            _detailRow('Referred Email', ref['referred_email'], isDark),
            if (ref['machine_category'] != null)
              _detailRow('Category', ref['machine_category'], isDark),
            if (_d(ref['qualifying_amount']) > 0)
              _detailRow(
                'Purchase',
                'Rs. ${_fmt.format(_d(ref['qualifying_amount']))}',
                isDark,
              ),
            if (ref['commission_type'] != null)
              _detailRow(
                'Commission',
                ref['commission_type'] == 'percentage'
                    ? '${_d(ref['commission_rate']).toStringAsFixed(1)}%'
                    : 'Fixed Rs. ${_fmt.format(_d(ref['commission_amount']))}',
                isDark,
              ),
            if (ref['rule_name'] != null)
              _detailRow('Rule', ref['rule_name'], isDark),
            if (ref['cooling_ends_at'] != null)
              _detailRow(
                'Cooling Ends',
                TimeUtils.formatDateFull(
                  DateTime.parse(ref['cooling_ends_at'].toString()),
                ),
                isDark,
              ),
            if (ref['approved_by_name'] != null)
              _detailRow('Approved By', ref['approved_by_name'], isDark),
            if (ref['rejection_reason'] != null)
              _detailRow('Rejection', ref['rejection_reason'], isDark),
            if ((ref['admin_notes'] ?? '').toString().isNotEmpty)
              _detailRow('Admin Notes', ref['admin_notes'], isDark),
            if (ref['created_at'] != null)
              _detailRow(
                'Created',
                TimeUtils.formatDateFull(
                  DateTime.parse(ref['created_at'].toString()),
                ),
                isDark,
              ),
            // ── Action Buttons ──
            if (canApprove || canReject) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (canApprove)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _approveReferral(ref),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Approve & Pay',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Brand.r(12)),
                          ),
                        ),
                      ),
                    ),
                  if (canApprove && canReject) const SizedBox(width: 10),
                  if (canReject)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _rejectReferral(ref),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AdminColors.error,
                        ),
                        label: const Text(
                          'Reject',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AdminColors.error,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AdminColors.error.withAlpha(80),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Brand.r(12)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, dynamic value, bool isDark) {
    final v = value?.toString().trim() ?? '';
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminColors.textHint(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  4. APPROVE / REJECT
  // ═══════════════════════════════════════════════════════

  Future<void> _approveReferral(Map<String, dynamic> ref) async {
    // FIX: Remove unused methodCtrl — method state var handles it
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String method = 'bank_transfer';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AdminColors.card(sheetCtx),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
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
                          color: AdminColors.border(sheetCtx),
                          borderRadius: BorderRadius.circular(Brand.r(2)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Approve & Pay Commission',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(sheetCtx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Commission: Rs. ${_fmt.format(_d(ref['commission_amount']))}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.success,
                      ),
                    ),
                    Text(
                      'Referrer: ${ref['referrer_name'] ?? 'Unknown'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AdminColors.textSub(sheetCtx),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Payment Method
                    Text(
                      'Payment Method',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.textSub(sheetCtx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AdminColors.bg(sheetCtx),
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: method,
                          isExpanded: true,
                          dropdownColor: AdminColors.card(sheetCtx),
                          style: TextStyle(
                            color: AdminColors.text(sheetCtx),
                            fontSize: 14,
                          ),
                          icon: Icon(
                            Icons.expand_more_rounded,
                            color: AdminColors.textSub(sheetCtx),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'bank_transfer',
                              child: Text(
                                'Bank Transfer',
                                style: TextStyle(
                                    color: AdminColors.text(sheetCtx)),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'cash',
                              child: Text(
                                'Cash',
                                style: TextStyle(
                                    color: AdminColors.text(sheetCtx)),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'cheque',
                              child: Text(
                                'Cheque',
                                style: TextStyle(
                                    color: AdminColors.text(sheetCtx)),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setSheet(() => method = v ?? method),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Payment Reference
                    TextField(
                      controller: refCtrl,
                      style: TextStyle(
                        color: AdminColors.text(sheetCtx),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Payment Reference',
                        labelStyle: TextStyle(
                          color: AdminColors.textSub(sheetCtx),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: AdminColors.bg(sheetCtx),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Brand.r(12)),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Notes
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      style: TextStyle(
                        color: AdminColors.text(sheetCtx),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        labelStyle: TextStyle(
                          color: AdminColors.textSub(sheetCtx),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: AdminColors.bg(sheetCtx),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Brand.r(12)),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(sheetCtx, true),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Confirm & Pay',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Brand.r(14)),
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
            );
          },
        );
      },
    );

    // FIX: Capture values before dispose
    final paymentRef = refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim();
    final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();

    // FIX: Always dispose controllers — before early return
    refCtrl.dispose();
    notesCtrl.dispose();

    if (confirmed != true) return;
    // FIX: mounted check after sheet dismissed
    if (!mounted) return;

    try {
      final res = await _supabase.rpc('approve_referral_commission', params: {
        'p_referral_id': ref['id'],
        'p_admin_id': _userId,
        'p_payment_method': method,
        'p_payment_reference': paymentRef,
        'p_notes': notes,
      });
      if (!mounted) return;
      // FIX: Safe cast instead of hard cast
      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (result['success'] == true) {
        _snack('Referral approved & commission paid');
        await _loadAll();
      } else {
        _snack(
          result['error']?.toString() ?? 'Failed to approve referral',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to approve referral', isError: true);
    }
  }

  Future<void> _rejectReferral(Map<String, dynamic> ref) async {
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.card(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(20))),
        title: Text(
          'Reject Referral?',
          style: TextStyle(color: AdminColors.text(ctx)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Referrer: ${ref['referrer_name'] ?? 'Unknown'}\n'
              'Referred: ${ref['referred_name'] ?? 'Unknown'}',
              style: TextStyle(
                color: AdminColors.textSub(ctx),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              style: TextStyle(color: AdminColors.text(ctx)),
              decoration: InputDecoration(
                hintText: 'Reason for rejection *',
                hintStyle: TextStyle(color: AdminColors.textHint(ctx)),
                filled: true,
                fillColor: AdminColors.bg(ctx),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AdminColors.textSub(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(10))),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    // FIX: Capture reason then always dispose
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (confirmed != true) return;
    // FIX: mounted check after dialog closed
    if (!mounted) return;

    try {
      final res = await _supabase.rpc('reject_referral_commission', params: {
        'p_referral_id': ref['id'],
        'p_admin_id': _userId,
        'p_reason': reason.isEmpty ? null : reason,
      });
      if (!mounted) return;
      // FIX: Safe cast
      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (result['success'] == true) {
        _snack('Referral rejected');
        await _loadAll();
      } else {
        _snack(
          result['error']?.toString() ?? 'Failed to reject referral',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to reject referral', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  // FIX: Use AdminColors named constants for semantic statuses
  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return const Color(0xFF94A3B8);
      case 'signed_up':
        return const Color(0xFF8B5CF6);
      case 'cooling':
        return const Color(0xFF06B6D4);
      case 'approved':
        return AdminColors.success;
      case 'paid':
        return AdminColors.info;
      case 'rejected':
        return AdminColors.error;
      case 'expired':
        return AdminColors.warning;
      default:
        return const Color(0xFF94A3B8);
    }
  }

  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(Brand.r(8)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // FIX: Explicit cases for all statuses
  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'signed_up':
        return 'Signed Up';
      case 'cooling':
        return 'Cooling';
      case 'approved':
        return 'Approved';
      case 'paid':
        return 'Paid';
      case 'rejected':
        return 'Rejected';
      case 'expired':
        return 'Expired';
      default:
        if (s.isEmpty) return '—';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  // FIX: Success snack uses AdminColors.success not .accent
  void _snack(String msg, {bool isError = false}) {
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
                msg,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : AdminColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Widget _buildShimmer(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ShimmerLoading(
              child: Container(
                height: 88,
                decoration: BoxDecoration(
                  color: AdminColors.card(context),
                  borderRadius: BorderRadius.circular(Brand.r(16)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    final filterLabel =
        _statusFilter != null ? _statusLabel(_statusFilter!) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 56,
              color: AdminColors.textHint(context),
            ),
            const SizedBox(height: 16),
            Text(
              filterLabel != null
                  ? 'No $filterLabel referrals'
                  : 'No referrals yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filterLabel != null
                  ? 'Try a different filter'
                  : 'Referrals will appear here as customers share codes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.textSub(context),
              ),
            ),
            if (_statusFilter != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _statusFilter = null);
                  _loadList();
                },
                icon: const Icon(Icons.filter_list_off_rounded, size: 16),
                label: const Text('Clear Filter'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.primary,
                  side: BorderSide(color: AdminColors.primary.withAlpha(80)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.r(10))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: AdminColors.textHint(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load referrals',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again',
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.textSub(context),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
