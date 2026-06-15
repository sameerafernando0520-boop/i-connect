// lib/screens/admin/admin_installments_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import 'installment_detail_page.dart';
import 'admin_register_machine_page.dart';

class AdminInstallmentsPage extends StatefulWidget {
  final String? customerIdFilter;
  const AdminInstallmentsPage({
    super.key,
    this.customerIdFilter,
  });

  @override
  State<AdminInstallmentsPage> createState() => _AdminInstallmentsPageState();
}

class _AdminInstallmentsPageState extends State<AdminInstallmentsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _plans = [];
  String? _statusFilter;
  String _searchQuery = '';
  String _role = 'admin';

  final _cf = NumberFormat('#,##0.00', 'en_US');
  String _fmtCur(num v) => 'Rs. ${_cf.format(v)}';
  String _fmtDate(String? d) {
    if (d == null) return '—';
    try {
      return DateFormat('MMM dd, yyyy').format(DateTime.parse(d));
    } catch (_) {
      return d;
    }
  }

  // ── Theme helpers ──
  // FIX: replaced AdminColors.background/surface with Brand equivalents
  Color _bg(bool dk) => dk ? Brand.darkBg : Brand.scaffoldLight;
  Color _cardBg(bool dk) => dk ? Brand.darkCard : Colors.white;
  Color _inputBg(bool dk) => dk ? Brand.darkCard : Colors.white;
  Color _textSub(bool dk) =>
      dk ? Brand.darkTextSecondary : const Color(0xFF64748B);
  Color _textHint(bool dk) =>
      dk ? Brand.darkTextTertiary : const Color(0xFF94A3B8);
  Color _border(bool dk) => dk ? Brand.darkBorder : Brand.borderLight;

  List<BoxShadow> _shadow(bool dk) => dk
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final result = await SupabaseConfig.client.rpc(
        'get_installment_plans',
        params: {
          'p_user_id_filter': widget.customerIdFilter,
          'p_status_filter': _statusFilter,
        },
      );
      if (!mounted) return;
      setState(() {
        _plans = List<Map<String, dynamic>>.from(
          result['plans'] as List? ?? [],
        );
        _role = (result['role'] ?? 'customer').toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Failed to load: $e', isError: true);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _plans;
    final q = _searchQuery.toLowerCase();
    return _plans.where((p) {
      return (p['customer_name'] ?? '').toString().toLowerCase().contains(q) ||
          (p['machine_name'] ?? '').toString().toLowerCase().contains(q) ||
          (p['serial_number'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  int get _totalActive =>
      _plans.where((p) => p['payment_status'] == 'active').length;
  int get _totalCompleted =>
      _plans.where((p) => p['payment_status'] == 'completed').length;
  int get _totalOverdue => _plans.fold<int>(
        0,
        (s, p) => s + (((p['overdue_count'] as num?) ?? 0).toInt()),
      );

  void _showSnackBar(
    String message, {
    bool isError = false,
  }) {
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
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : AdminColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final list = _filtered;
    final isAdmin = _role == 'admin';

    return Scaffold(
      backgroundColor: _bg(isDark),
      appBar: DsPageHeader(
        title: widget.customerIdFilter != null ? 'Customer Installments' : 'All Installments',
        subtitle: '${_plans.length} plans',
        accent: HeroAccent.navy,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? _buildLoadingSkeleton(isDark)
                  : RefreshIndicator(
                      onRefresh: _load,
                      color:
                          isDark ? Brand.lightGreenBright : AdminColors.accent,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: _buildStatsRow(isDark),
                          ),
                          SliverToBoxAdapter(
                            child: _buildFilterChips(isDark),
                          ),
                          SliverToBoxAdapter(
                            child: _buildSearchBar(isDark),
                          ),
                          list.isEmpty
                              ? SliverFillRemaining(
                                  child: _buildEmptyState(
                                    isDark,
                                  ),
                                )
                              : SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    4,
                                    20,
                                    100,
                                  ),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (ctx, i) => _buildPlanCard(
                                        isDark,
                                        list[i],
                                      ),
                                      childCount: list.length,
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
      floatingActionButton: isAdmin ? _buildFAB(isDark) : null,
    );
  }

  // ─── STATS ROW ───────────────────────────────────────────
  Widget _buildStatsRow(bool isDark) {
    // FIX: replaced Colors.teal with const color
    const tealColor = Color(0xFF14B8A6);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _buildStatCard(
            isDark,
            '${_plans.length}',
            'Total',
            isDark ? Brand.royalBlueGlow : AdminColors.primary,
            Icons.receipt_long_rounded,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            isDark,
            '$_totalActive',
            'Active',
            isDark ? Brand.lightGreenBright : AdminColors.accent,
            Icons.check_circle_rounded,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            isDark,
            '$_totalCompleted',
            'Done',
            isDark ? const Color(0xFF4DD0B8) : tealColor,
            Icons.task_alt_rounded,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            isDark,
            '$_totalOverdue',
            'Overdue',
            AdminColors.error,
            Icons.warning_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    bool isDark,
    String value,
    String label,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border: isDark ? Border.all(color: _border(isDark)) : null,
          boxShadow: _shadow(isDark),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                // FIX: replaced Colors.grey.shade500
                color: _textSub(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── FILTER CHIPS ────────────────────────────────────────
  Widget _buildFilterChips(bool isDark) {
    // FIX: replaced Colors.teal with const
    const tealColor = Color(0xFF14B8A6);

    final filters = [
      {
        'label': 'All',
        'value': null,
        'icon': Icons.apps_rounded,
        'color': isDark ? Brand.royalBlueGlow : AdminColors.primary,
      },
      {
        'label': 'Active',
        'value': 'active',
        'icon': Icons.check_circle_rounded,
        'color': isDark ? Brand.lightGreenBright : AdminColors.accent,
      },
      {
        'label': 'Completed',
        'value': 'completed',
        'icon': Icons.task_alt_rounded,
        'color': isDark ? const Color(0xFF4DD0B8) : tealColor,
      },
      {
        'label': 'Defaulted',
        'value': 'defaulted',
        'icon': Icons.cancel_rounded,
        'color': AdminColors.error,
      },
    ];

    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 14),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = filters[index];
          final isSelected = _statusFilter == f['value'];
          final color = f['color'] as Color;

          return GestureDetector(
            onTap: () {
              // FIX: combined setState + _load
              // avoids double rebuild
              setState(() {
                _statusFilter = f['value'] as String?;
              });
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: isSelected ? color : _cardBg(isDark),
                borderRadius: BorderRadius.circular(Brand.r(12)),
                border: Border.all(
                  color: isSelected ? color : _border(isDark),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : _shadow(isDark),
              ),
              child: Row(
                children: [
                  Icon(
                    f['icon'] as IconData,
                    size: 14,
                    color: isSelected ? Colors.white : color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    f['label'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : _textSub(isDark),
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

  // ─── SEARCH BAR ──────────────────────────────────────────
  Widget _buildSearchBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      decoration: BoxDecoration(
        color: _inputBg(isDark),
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: isDark ? Border.all(color: _border(isDark)) : null,
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Brand.royalBlue.withAlpha(13),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        // FIX: replaced Colors.black87
        style: TextStyle(
          color: isDark ? Brand.darkTextPrimary : const Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          hintText: 'Search customer, machine, serial...',
          hintStyle: TextStyle(
            color: _textHint(isDark),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _textHint(isDark),
            size: 22,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () => setState(
                    () => _searchQuery = '',
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Brand.darkBorderLight
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: _textSub(isDark),
                      size: 18,
                    ),
                  ),
                )
              : null,
          filled: true,
          fillColor: _inputBg(isDark),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ─── PLAN CARD ───────────────────────────────────────────
  Widget _buildPlanCard(
    bool isDark,
    Map<String, dynamic> plan,
  ) {
    final status = (plan['payment_status'] ?? 'active').toString();
    final paidCount = (plan['paid_count'] as num?)?.toDouble() ?? 0;
    final total = (plan['num_installments'] as num?)?.toDouble() ?? 1;
    final overdueCount = (plan['overdue_count'] as num?) ?? 0;
    // FIX: explicit double division — avoids integer division
    final progress = total > 0 ? paidCount / total : 0.0;

    Color statusColor;
    switch (status) {
      case 'completed':
        statusColor = isDark ? Brand.lightGreenBright : AdminColors.accent;
        break;
      case 'defaulted':
        statusColor = AdminColors.error;
        break;
      default:
        statusColor = isDark ? Brand.royalBlueGlow : AdminColors.primary;
    }

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InstallmentDetailPage(
              planId: plan['id'].toString(),
            ),
          ),
        );
        if (mounted) _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardBg(isDark),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: isDark
              ? Border.all(color: _border(isDark))
              : overdueCount > 0
                  ? Border.all(
                      color: AdminColors.error.withAlpha(51),
                      width: 1.5,
                    )
                  : null,
          boxShadow: isDark
              ? []
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header row
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          // FIX: replaced .withOpacity() with .withAlpha()
                          // 0.12 ≈ 31 alpha, 0.08 ≈ 20 alpha
                          color: statusColor.withAlpha(isDark ? 31 : 20),
                          borderRadius: BorderRadius.circular(Brand.r(13)),
                          border: Border.all(
                            // 0.2 ≈ 51 alpha, 0.15 ≈ 38 alpha
                            color: statusColor.withAlpha(
                              isDark ? 51 : 38,
                            ),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.precision_manufacturing_rounded,
                          size: 22,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (plan['machine_name'] ?? '').toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isDark
                                    ? Brand.darkTextPrimary
                                    : AdminColors.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (plan['customer_name'] ?? '').toString(),
                              style: TextStyle(
                                fontSize: 13,
                                // FIX: replaced Colors.grey.shade600
                                color: _textSub(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          // FIX: replaced .withOpacity() with .withAlpha()
                          color: statusColor.withAlpha(isDark ? 31 : 20),
                          borderRadius: BorderRadius.circular(Brand.r(8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Amount + progress label
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmtCur(
                          plan['installment_amount'] as num? ?? 0,
                        ),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : AdminColors.primary,
                        ),
                      ),
                      Text(
                        '${paidCount.toInt()} / ${total.toInt()} paid',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          // FIX: replaced Colors.grey.shade500
                          color: _textSub(isDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Animated progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Brand.r(6)),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: progress.clamp(0.0, 1.0),
                      ),
                      duration: const Duration(
                        milliseconds: 600,
                      ),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => LinearProgressIndicator(
                        value: val,
                        minHeight: 7,
                        backgroundColor: isDark
                            ? Brand.darkBorderLight
                            : const Color(0xFFF1F5F9),
                        valueColor: AlwaysStoppedAnimation(
                          status == 'completed'
                              ? (isDark
                                  ? Brand.lightGreenBright
                                  : AdminColors.accent)
                              : status == 'defaulted'
                                  ? AdminColors.error
                                  : (isDark
                                      ? Brand.royalBlueGlow
                                      : AdminColors.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Footer strip
            Container(
              decoration: BoxDecoration(
                color: Brand.canvas(isDark),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(Brand.r(18)),
                ),
              ),
              child: Row(
                children: [
                  if (overdueCount > 0)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AdminColors.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$overdueCount overdue',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AdminColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (plan['next_due_date'] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: _textHint(isDark),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Next: ${_fmtDate(plan['next_due_date']?.toString())}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _textSub(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: _textHint(isDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── FAB ─────────────────────────────────────────────────
  Widget _buildFAB(bool isDark) {
    return GestureDetector(
      onTap: () async {
        final created = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminRegisterMachinePage(
              preSelectedCustomerId: widget.customerIdFilter,
            ),
          ),
        );
        if (created == true && mounted) _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          // FIX: AdminColors.primaryLight does NOT exist
          // → use Brand.royalBlueLight
          gradient: const LinearGradient(
            colors: [Brand.royalBlue, Brand.royalBlueLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          boxShadow: [
            BoxShadow(
              color: Brand.royalBlue.withAlpha(102),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              'Register',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── LOADING SKELETON ────────────────────────────────────
  Widget _buildLoadingSkeleton(bool isDark) {
    final shimmer = isDark ? Brand.darkCardElevated : const Color(0xFFEEF0F5);
    final cardShimmer = isDark ? Brand.darkCard : const Color(0xFFF8FAFC);

    // M6: Lazy-build instead of constructing every skeleton child at mount.
    // Layout is fixed-height, mixed-type, so we switch on the index:
    //   0          → stats row
    //   1, 3, 5    → vertical gaps
    //   2          → filter chips
    //   4          → search bar
    //   6..(6+N-1) → plan card skeletons
    const planCardCount = 4;
    const fixedRows = 6;
    final total = fixedRows + planCardCount;

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      itemCount: total,
      itemBuilder: (_, i) {
        switch (i) {
          case 0:
            return Row(
              children: List.generate(4, (j) {
                return Expanded(
                  child: Container(
                    height: 78,
                    margin: EdgeInsets.only(right: j < 3 ? 8 : 0),
                    decoration: BoxDecoration(
                      color: cardShimmer,
                      borderRadius: BorderRadius.circular(Brand.r(14)),
                      border:
                          isDark ? Border.all(color: Brand.darkBorder) : null,
                    ),
                  ),
                );
              }),
            );
          case 1:
          case 3:
          case 5:
            return const SizedBox(height: 14);
          case 2:
            return SizedBox(
              height: 42,
              child: Row(
                children: List.generate(4, (_) {
                  return Container(
                    width: 80,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: shimmer,
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                    ),
                  );
                }),
              ),
            );
          case 4:
            return Container(
              height: 50,
              decoration: BoxDecoration(
                color: cardShimmer,
                borderRadius: BorderRadius.circular(Brand.r(14)),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
            );
          default:
            return Container(
              height: 145,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cardShimmer,
                borderRadius: BorderRadius.circular(Brand.r(18)),
                border: isDark ? Border.all(color: Brand.darkBorder) : null,
              ),
            );
        }
      },
    );
  }

  // ─── EMPTY STATE ─────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    final hasFilters = _statusFilter != null || _searchQuery.isNotEmpty;

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
                color: (isDark ? Brand.royalBlueGlow : AdminColors.primary)
                    .withAlpha(15),
                borderRadius: BorderRadius.circular(Brand.r(24)),
              ),
              child: Icon(
                hasFilters
                    ? Icons.filter_alt_off_rounded
                    : Icons.receipt_long_outlined,
                size: 40,
                color: _textHint(isDark),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilters ? 'No plans match' : 'No installment plans',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _textSub(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try adjusting your filters'
                  : 'Register a machine to create a plan',
              style: TextStyle(
                fontSize: 13,
                color: _textHint(isDark),
              ),
              textAlign: TextAlign.center,
            ),
            if (hasFilters) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _statusFilter = null;
                    _searchQuery = '';
                  });
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isDark ? Brand.lightGreenBright : AdminColors.accent)
                            .withAlpha(26),
                    borderRadius: BorderRadius.circular(Brand.r(12)),
                  ),
                  child: Text(
                    'Clear Filters',
                    style: TextStyle(
                      color:
                          isDark ? Brand.lightGreenBright : AdminColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
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
