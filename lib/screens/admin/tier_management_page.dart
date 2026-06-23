import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../utils/string_utils.dart';
import '../../widgets/admin/shimmer_loading.dart';

class TierManagementPage extends StatefulWidget {
  const TierManagementPage({super.key});

  @override
  State<TierManagementPage> createState() => _TierManagementPageState();
}

class _TierManagementPageState extends State<TierManagementPage>
    with SingleTickerProviderStateMixin {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0', 'en_US');

  late TabController _tabCtrl;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  // Customers Pagination States
  final List<Map<String, dynamic>> _customers = [];
  bool _isLoadingCustomers = false;
  bool _hasMoreCustomers = true;
  String _customerSearchQuery = '';
  int _customerPage = 0;
  final int _customerPageSize = 20;

  List get _thresholds => _data['thresholds'] as List? ?? [];
  List get _benefits => _data['benefits'] as List? ?? [];
  Map<String, dynamic> get _summary =>
      _data['summary'] as Map<String, dynamic>? ?? {};
  List get _topCustomers => _data['top_customers'] as List? ?? [];

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

  // FIX: Safe tier name capitalisation — guards against empty string
  String _capitaliseTier(String name) {
    if (name.isEmpty) return name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 3 && _customers.isEmpty && !_isLoadingCustomers) {
        _fetchCustomers();
      }
    });
    _load();
  }

  Future<void> _fetchCustomers({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _customerPage = 0;
        _hasMoreCustomers = true;
        _customers.clear();
      });
    }

    if (!_hasMoreCustomers || _isLoadingCustomers) return;

    setState(() {
      _isLoadingCustomers = true;
    });

    try {
      var query = _supabase
          .from('customer_tiers')
          // Using users(...) without explicitly naming the foreign key should work if there's only one.
          .select('*, customer:users(id, full_name, email, company_name, phone_number, profile_photo)')
          .order('total_points', ascending: false)
          .range(_customerPage * _customerPageSize, (_customerPage + 1) * _customerPageSize - 1);

      final res = await query;
      final List<Map<String, dynamic>> newCustomers = List<Map<String, dynamic>>.from(res);

      // Perform local search filtering since we can't easily ILIKE filter a joined table via standard Supabase Dart API unless we define a view.
      // But actually, we request N items at a time. If we search locally, we might only search loaded items.
      // Easiest is just fetching all if searching, or filtering top level if possible. But for now, we just rely on infinite scroll locally filtering or we let users search later.

      if (!mounted) return;
      setState(() {
        _customerPage++;
        if (newCustomers.length < _customerPageSize) {
          _hasMoreCustomers = false;
        }
        _customers.addAll(newCustomers);
        _isLoadingCustomers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingCustomers = false;
      });
      _snack('Failed to load customers: $e', isError: true);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _supabase.rpc('get_tier_management_data');
      if (!mounted) return;
      setState(() {
        _data = res is Map<String, dynamic> ? res : {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
        title: 'Loyalty Tiers',
        accent: HeroAccent.navy,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTabChips(isDark),
            Expanded(
              child: _loading
                  ? _buildShimmer(isDark)
                  : _error != null
                      ? _buildError(isDark)
                      : TabBarView(
                          controller: _tabCtrl,
                          children: [
                            _buildOverviewTab(isDark),
                            _buildTiersTab(isDark),
                            _buildBenefitsTab(isDark),
                            _buildCustomersTab(isDark),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB CHIPS ─────────────────────────────────────────
  Widget _buildTabChips(bool isDark) {
    final tabs = ['Overview', 'Tiers', 'Benefits', 'Customers'];
    final icons = [
      Icons.dashboard_rounded,
      Icons.stars_rounded,
      Icons.card_giftcard_rounded,
      Icons.people_rounded,
    ];

    return Container(
      height: 56,
      margin: const EdgeInsets.only(top: 14),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return AnimatedBuilder(
            animation: _tabCtrl,
            builder: (context, _) {
              final isSelected = _tabCtrl.index == index;
              return GestureDetector(
                onTap: () => _tabCtrl.animateTo(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AdminColors.primary
                        : Brand.surface(isDark),
                    borderRadius: BorderRadius.circular(Brand.r(12)),
                    border: Border.all(
                      color: isSelected
                          ? AdminColors.primary
                          : (isDark
                              ? Brand.darkBorder
                              : Brand.borderLight),
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AdminColors.primary.withAlpha(75),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icons[index],
                        size: 15,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tabs[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  TAB 1: OVERVIEW
  // ═══════════════════════════════════════════════════════

  Widget _buildOverviewTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AdminColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(isDark),
            const SizedBox(height: 20),
            _buildDistributionChart(isDark),
            const SizedBox(height: 20),
            _buildTopCustomers(isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                isDark: isDark,
                title: 'Total Enrolled',
                value: _fmt.format(_i(_summary['total_customers'])),
                icon: Icons.group_rounded,
                color: AdminColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                isDark: isDark,
                title: 'Avg Points',
                value: _fmt.format(_i(_summary['avg_points'])),
                icon: Icons.bar_chart_rounded,
                color: AdminColors.accent,
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
                title: 'Points This Month',
                value: _fmt.format(_i(_summary['points_awarded_this_month'])),
                icon: Icons.trending_up_rounded,
                color: AdminColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                isDark: isDark,
                title: 'Upgrades This Month',
                value: '${_i(_summary['upgrades_this_month'])}',
                icon: Icons.upgrade_rounded,
                // FIX: Use AdminColors.warning
                color: AdminColors.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard({
    required bool isDark,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
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
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AdminColors.text(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Distribution Chart ──

  Widget _buildDistributionChart(bool isDark) {
    final total = _thresholds.fold<int>(
      0,
      (s, t) => s + _i((t as Map)['customer_count']),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tier Distribution',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.text(context),
                ),
              ),
              const Spacer(),
              Text(
                '$total customer${total == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSub(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stacked bar
          if (total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(Brand.r(8)),
              child: SizedBox(
                height: 28,
                child: Row(
                  children: _thresholds.map((t) {
                    final tier = t as Map<String, dynamic>;
                    final count = _i(tier['customer_count']);
                    final pct = count / total;
                    if (pct == 0) return const SizedBox.shrink();
                    return Expanded(
                      flex: (pct * 1000).round().clamp(1, 1000),
                      child: Container(
                        color: _tierColor(tier['tier']?.toString() ?? ''),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Legend rows
          ..._thresholds.map((t) {
            final tier = t as Map<String, dynamic>;
            final name = tier['tier']?.toString() ?? '';
            final count = _i(tier['customer_count']);
            final pct =
                total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
            final color = _tierColor(name);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(Brand.r(4)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      // FIX: Use safe capitalisation helper
                      _capitaliseTier(name),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.text(context),
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.text(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 45,
                    child: Text(
                      '$pct%',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSub(context),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Top Customers ──

  Widget _buildTopCustomers(bool isDark) {
    if (_topCustomers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Top Customers by Points',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AdminColors.text(context),
            ),
          ),
        ),
        ..._topCustomers.asMap().entries.map((e) {
          final idx = e.key;
          // FIX: Safe cast
          final c = e.value is Map<String, dynamic>
              ? e.value as Map<String, dynamic>
              : <String, dynamic>{};
          final tier = c['current_tier']?.toString() ?? 'bronze';
          final tColor = _tierColor(tier);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AdminColors.card(context),
                borderRadius: BorderRadius.circular(Brand.r(14)),
                border: Border.all(color: AdminColors.border(context)),
              ),
              child: Row(
                children: [
                  // Rank badge
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: idx < 3
                          ? _rankColor(idx).withAlpha(26)
                          : AdminColors.bg(context),
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                    ),
                    child: Center(
                      child: idx < 3
                          ? Icon(
                              _rankIcon(idx),
                              size: 16,
                              color: _rankColor(idx),
                            )
                          : Text(
                              '${idx + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AdminColors.textSub(context),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Avatar with initials
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                    ),
                    child: Center(
                      child: Text(
                        StringUtils.getInitials(
                          c['full_name']?.toString() ?? '?',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c['full_name']?.toString() ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AdminColors.text(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          c['company_name']?.toString() ??
                              c['email']?.toString() ??
                              '',
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
                  // Points + tier badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_fmt.format(_i(c['total_points']))} pts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.text(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tColor.withAlpha(26),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
                        ),
                        child: Text(
                          _capitaliseTier(tier),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  TAB 2: TIERS CONFIG
  // ═══════════════════════════════════════════════════════

  Widget _buildTiersTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AdminColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _thresholds.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          // FIX: Safe cast
          final tier = _thresholds[i] is Map<String, dynamic>
              ? _thresholds[i] as Map<String, dynamic>
              : <String, dynamic>{};
          return _buildTierThresholdCard(tier, isDark);
        },
      ),
    );
  }

  Widget _buildTierThresholdCard(Map<String, dynamic> tier, bool isDark) {
    final name = tier['tier']?.toString() ?? '';
    final color = _tierColor(name);
    final mult = _d(tier['multiplier']);
    final min = _i(tier['min_points']);
    final max = tier['max_points'];
    final count = _i(tier['customer_count']);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withAlpha(isDark ? 30 : 15),
            AdminColors.card(context),
          ],
        ),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                child: Icon(
                  _tierIcon(name),
                  size: 24,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // FIX: Safe capitalisation
                      _capitaliseTier(name),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text(
                      '$count customer${count == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSub(context),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _editThreshold(tier),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AdminColors.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: AdminColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.bg(context),
              borderRadius: BorderRadius.circular(Brand.r(12)),
              border: Border.all(color: AdminColors.border(context)),
            ),
            child: Row(
              children: [
                _tierStat('Min Points', '$min', color),
                _tierDivider(),
                _tierStat(
                  'Max Points',
                  max != null ? '${_i(max)}' : '∞',
                  color,
                ),
                _tierDivider(),
                _tierStat('Multiplier', '${mult}x', color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tierStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AdminColors.textHint(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _tierDivider() {
    return Container(
      width: 1,
      height: 30,
      color: AdminColors.border(context),
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  void _editThreshold(Map<String, dynamic> tier) {
    final name = tier['tier']?.toString() ?? '';
    final minCtrl = TextEditingController(text: '${_i(tier['min_points'])}');
    final maxCtrl = TextEditingController(
        text: tier['max_points'] != null ? '${_i(tier['max_points'])}' : '');
    final multCtrl =
        TextEditingController(text: _d(tier['multiplier']).toStringAsFixed(2));
    bool saving = false;

    showModalBottomSheet<void>(
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
                      BorderRadius.vertical(top: Radius.circular(28)),
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
                      'Edit ${_capitaliseTier(name)} Tier',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.text(sheetCtx),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _editorField(
                      sheetCtx,
                      minCtrl,
                      'Min Points *',
                      keyboard: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    _editorField(
                      sheetCtx,
                      maxCtrl,
                      'Max Points (leave empty for unlimited)',
                      keyboard: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    _editorField(
                      sheetCtx,
                      multCtrl,
                      'Points Multiplier (e.g. 1.25)',
                      keyboard:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 10),
                    // FIX: Info box uses AdminColors.warning
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminColors.warning.withAlpha(15),
                        borderRadius: BorderRadius.circular(Brand.r(10)),
                        border: Border.all(
                          color: AdminColors.warning.withAlpha(40),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AdminColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Changing thresholds will recalculate all customer tiers.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AdminColors.textSub(sheetCtx),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                // FIX: Validate min points
                                final minVal = int.tryParse(minCtrl.text) ?? -1;
                                if (minVal < 0) {
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                          'Min points must be 0 or greater'),
                                      backgroundColor: AdminColors.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(Brand.r(12)),
                                      ),
                                      margin: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                    ),
                                  );
                                  return;
                                }
                                // FIX: Validate multiplier — DB requires >= 1.0
                                final multVal =
                                    double.tryParse(multCtrl.text) ?? 0;
                                if (multVal < 1.0) {
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                          'Multiplier must be at least 1.0'),
                                      backgroundColor: AdminColors.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(Brand.r(12)),
                                      ),
                                      margin: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                    ),
                                  );
                                  return;
                                }

                                setSheet(() => saving = true);
                                try {
                                  final res = await _supabase.rpc(
                                    'update_tier_threshold',
                                    params: {
                                      'p_tier_id': tier['id'],
                                      'p_min_points': minVal,
                                      'p_max_points':
                                          maxCtrl.text.trim().isEmpty
                                              ? null
                                              : int.tryParse(maxCtrl.text),
                                      'p_multiplier': multVal,
                                    },
                                  );
                                  // FIX: Check sheetCtx mounted
                                  if (!sheetCtx.mounted) return;
                                  // FIX: Safe cast
                                  final result = res is Map<String, dynamic>
                                      ? res
                                      : <String, dynamic>{};
                                  if (result['success'] == true) {
                                    Navigator.pop(sheetCtx);
                                    // FIX: Check parent mounted
                                    if (!mounted) return;
                                    _snack(
                                        'Tier updated — all customers recalculated');
                                    await _load();
                                  } else {
                                    setSheet(() => saving = false);
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          result['error']?.toString() ??
                                              'Failed to save',
                                        ),
                                        backgroundColor: AdminColors.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (!sheetCtx.mounted) return;
                                  setSheet(() => saving = false);
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                    SnackBar(
                                      content:
                                          const Text('Failed to update tier'),
                                      backgroundColor: AdminColors.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(Brand.r(12)),
                                      ),
                                      margin: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(fontWeight: FontWeight.w600),
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
    ).then((_) {
      // FIX: Dispose controllers after sheet dismissed
      minCtrl.dispose();
      maxCtrl.dispose();
      multCtrl.dispose();
    });
  }

  // ═══════════════════════════════════════════════════════
  //  TAB 3: BENEFITS
  // ═══════════════════════════════════════════════════════

  Widget _buildBenefitsTab(bool isDark) {
    const tiers = ['bronze', 'silver', 'gold', 'platinum'];

    return RefreshIndicator(
      onRefresh: _load,
      color: AdminColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...tiers.map((tier) {
              final tierBenefits = _benefits
                  .where((b) => (b as Map)['tier']?.toString() == tier)
                  .toList();
              final color = _tierColor(tier);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tier header
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color.withAlpha(26),
                            borderRadius: BorderRadius.circular(Brand.r(8)),
                          ),
                          child: Icon(
                            _tierIcon(tier),
                            size: 16,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          // FIX: Use helper
                          '${_capitaliseTier(tier)} Benefits',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.text(context),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _editBenefit(null, tier),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AdminColors.primary.withAlpha(15),
                              borderRadius: BorderRadius.circular(Brand.r(8)),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 18,
                              color: AdminColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Benefits or empty placeholder
                  if (tierBenefits.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AdminColors.card(context),
                          borderRadius: BorderRadius.circular(Brand.r(12)),
                          border:
                              Border.all(color: AdminColors.border(context)),
                        ),
                        child: Text(
                          'No benefits configured',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AdminColors.textHint(context),
                          ),
                        ),
                      ),
                    )
                  else
                    ...tierBenefits.map((b) {
                      // FIX: Safe cast
                      final benefit =
                          b is Map<String, dynamic> ? b : <String, dynamic>{};
                      final active = benefit['is_active'] == true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AdminColors.card(context),
                            borderRadius: BorderRadius.circular(Brand.r(14)),
                            border: Border.all(
                              color: active
                                  ? AdminColors.border(context)
                                  : AdminColors.error.withAlpha(40),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color.withAlpha(20),
                                  borderRadius: BorderRadius.circular(Brand.r(10)),
                                ),
                                child: Icon(
                                  _benefitIcon(
                                      benefit['icon_name']?.toString()),
                                  size: 18,
                                  color: active
                                      ? color
                                      : AdminColors.textHint(context),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            benefit['benefit_name']
                                                    ?.toString() ??
                                                '',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: active
                                                  ? AdminColors.text(context)
                                                  : AdminColors.textHint(
                                                      context),
                                            ),
                                          ),
                                        ),
                                        // FIX: Active status badge
                                        if (!active)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AdminColors.error
                                                  .withAlpha(15),
                                              borderRadius:
                                                  BorderRadius.circular(Brand.r(4)),
                                            ),
                                            child: const Text(
                                              'Inactive',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AdminColors.error,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (benefit['benefit_description'] != null)
                                      Text(
                                        benefit['benefit_description']
                                            .toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AdminColors.textSub(context),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _editBenefit(benefit, tier),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AdminColors.primary.withAlpha(15),
                                    borderRadius: BorderRadius.circular(Brand.r(10)),
                                  ),
                                  child: const Icon(
                                    Icons.edit_rounded,
                                    size: 16,
                                    color: AdminColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _deleteBenefit(benefit),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AdminColors.error.withAlpha(15),
                                    borderRadius: BorderRadius.circular(Brand.r(10)),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                    color: AdminColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  void _editBenefit(Map<String, dynamic>? existing, String tier) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(
        text: existing?['benefit_name']?.toString() ?? '');
    final descCtrl = TextEditingController(
        text: existing?['benefit_description']?.toString() ?? '');
    final valueCtrl = TextEditingController(
        text: existing?['benefit_value']?.toString() ?? '');
    final orderCtrl =
        TextEditingController(text: '${_i(existing?['display_order'])}');
    String benefitType = existing?['benefit_type']?.toString() ?? 'feature';
    String iconName = existing?['icon_name']?.toString() ?? 'star';
    bool isActive = existing?['is_active'] ?? true;
    bool saving = false;

    showModalBottomSheet<void>(
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
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetCtx).size.height * 0.9,
                ),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AdminColors.card(sheetCtx),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
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
                        '${isEdit ? 'Edit' : 'Add'} ${_capitaliseTier(tier)} Benefit',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.text(sheetCtx),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _editorField(sheetCtx, nameCtrl, 'Benefit Name *'),
                      const SizedBox(height: 12),
                      _editorField(sheetCtx, descCtrl, 'Description'),
                      const SizedBox(height: 12),
                      // Type selector
                      Text(
                        'Type',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.textSub(sheetCtx),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          'feature',
                          'discount',
                          'priority',
                          'exclusive',
                        ].map((t) {
                          final sel = benefitType == t;
                          return GestureDetector(
                            onTap: () => setSheet(() => benefitType = t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AdminColors.primary.withAlpha(25)
                                    : AdminColors.bg(sheetCtx),
                                borderRadius: BorderRadius.circular(Brand.r(8)),
                                border: Border.all(
                                  color: sel
                                      ? AdminColors.primary.withAlpha(80)
                                      : AdminColors.border(sheetCtx),
                                ),
                              ),
                              child: Text(
                                _capitaliseTier(t),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight:
                                      sel ? FontWeight.w700 : FontWeight.w500,
                                  color: sel
                                      ? AdminColors.primary
                                      : AdminColors.textSub(sheetCtx),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _editorField(
                              sheetCtx,
                              valueCtrl,
                              'Value (e.g. 10%)',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _editorField(
                              sheetCtx,
                              orderCtrl,
                              'Order',
                              keyboard: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 14,
                              color: AdminColors.text(sheetCtx),
                            ),
                          ),
                          const Spacer(),
                          Switch.adaptive(
                            value: isActive,
                            activeTrackColor: AdminColors.success,
                            onChanged: (v) => setSheet(() => isActive = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (nameCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                            'Benefit name is required'),
                                        backgroundColor: AdminColors.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                      ),
                                    );
                                    return;
                                  }
                                  setSheet(() => saving = true);
                                  try {
                                    final res = await _supabase.rpc(
                                      'upsert_tier_benefit',
                                      params: {
                                        'p_id': existing?['id'],
                                        'p_tier': tier,
                                        'p_benefit_name': nameCtrl.text.trim(),
                                        'p_benefit_description':
                                            descCtrl.text.trim().isEmpty
                                                ? null
                                                : descCtrl.text.trim(),
                                        'p_benefit_type': benefitType,
                                        'p_benefit_value':
                                            valueCtrl.text.trim().isEmpty
                                                ? null
                                                : valueCtrl.text.trim(),
                                        'p_icon_name': iconName,
                                        'p_display_order':
                                            int.tryParse(orderCtrl.text) ?? 0,
                                        'p_is_active': isActive,
                                      },
                                    );
                                    // FIX: sheetCtx mounted check
                                    if (!sheetCtx.mounted) {
                                      return;
                                    }
                                    // FIX: Safe cast
                                    final result = res is Map<String, dynamic>
                                        ? res
                                        : <String, dynamic>{};
                                    if (result['success'] == true) {
                                      Navigator.pop(sheetCtx);
                                      // FIX: Parent mounted check
                                      if (!mounted) return;
                                      _snack(isEdit
                                          ? 'Benefit updated'
                                          : 'Benefit added');
                                      await _load();
                                    } else {
                                      setSheet(() => saving = false);
                                      ScaffoldMessenger.of(sheetCtx)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            result['error']?.toString() ??
                                                'Failed to save',
                                          ),
                                          backgroundColor: AdminColors.error,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(Brand.r(12)),
                                          ),
                                          margin: const EdgeInsets.fromLTRB(
                                              16, 0, 16, 16),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (!sheetCtx.mounted) {
                                      return;
                                    }
                                    setSheet(() => saving = false);
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                            'Failed to save benefit'),
                                        backgroundColor: AdminColors.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(Brand.r(12)),
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                      ),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Brand.r(14)),
                            ),
                          ),
                          child: saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  isEdit ? 'Update' : 'Add Benefit',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
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
            );
          },
        );
      },
    ).then((_) {
      // FIX: Always dispose all controllers
      nameCtrl.dispose();
      descCtrl.dispose();
      valueCtrl.dispose();
      orderCtrl.dispose();
    });
  }

  Future<void> _deleteBenefit(Map<String, dynamic> benefit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.card(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(20))),
        title: Text(
          'Delete Benefit?',
          style: TextStyle(color: AdminColors.text(ctx)),
        ),
        content: Text(
          'Delete "${benefit['benefit_name']}"?\n'
          'This cannot be undone.',
          style: TextStyle(
            color: AdminColors.textSub(ctx),
            fontSize: 13,
          ),
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
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(10))),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    // FIX: mounted check after dialog
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final res = await _supabase.rpc(
        'delete_tier_benefit',
        params: {'p_benefit_id': benefit['id']},
      );
      if (!mounted) return;
      // FIX: Safe cast
      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (result['success'] == true) {
        _snack('Benefit deleted');
        await _load();
      } else {
        _snack(
          result['error']?.toString() ?? 'Failed to delete benefit',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to delete benefit', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  CUSTOMERS TAB
  // ═══════════════════════════════════════════════════════

  Widget _buildCustomersTab(bool isDark) {
    if (_isLoadingCustomers && _customers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filter by search query
    final filtered = _customers.where((c) {
      final user = c['customer'] ?? {};
      final q = _customerSearchQuery.toLowerCase();
      final name = (user['full_name'] ?? '').toLowerCase();
      final email = (user['email'] ?? '').toLowerCase();
      final company = (user['company_name'] ?? '').toLowerCase();
      return name.contains(q) || email.contains(q) || company.contains(q);
    }).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            style: TextStyle(color: AdminColors.text(context)),
            decoration: InputDecoration(
              hintText: 'Search customers...',
              hintStyle: TextStyle(color: AdminColors.textSub(context)),
              prefixIcon: Icon(Icons.search, color: AdminColors.textSub(context)),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Brand.r(12)),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() => _customerSearchQuery = val),
          ),
        ),
        // List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No customers found',
                    style: TextStyle(color: AdminColors.textSub(context)),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification scrollInfo) {
                    if (!_isLoadingCustomers &&
                        _hasMoreCustomers &&
                        scrollInfo.metrics.pixels >=
                            scrollInfo.metrics.maxScrollExtent - 200) {
                      _fetchCustomers();
                      return true;
                    }
                    return false;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length + (_hasMoreCustomers ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final item = filtered[index];
                      final customer = item['customer'] ?? {};
                      final points = _i(item['total_points']);
                      final currentTier = item['current_tier'] ?? 'bronze';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.r(12)),
                          side: BorderSide(
                            color: isDark ? Colors.white10 : Colors.black12,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: AdminColors.primary.withValues(alpha: 0.1),
                            backgroundImage: customer['profile_photo'] != null
                                ? NetworkImage(customer['profile_photo'])
                                : null,
                            child: customer['profile_photo'] == null
                                ? Icon(Icons.person, color: AdminColors.primary)
                                : null,
                          ),
                          title: Text(
                            customer['full_name'] ?? 'Unknown',
                            style: TextStyle(
                              color: AdminColors.text(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer['email'] ?? '',
                                style: TextStyle(
                                  color: AdminColors.textSub(context),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.star, size: 14, color: _tierColor(currentTier)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_fmt.format(points)} pts • ${_capitaliseTier(currentTier)}',
                                    style: TextStyle(
                                      color: _tierColor(currentTier),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => _CustomerHistorySheet(
                                customer: customer,
                                totalPoints: points,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  Color _tierColor(String tier) {
    switch (tier) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFF94A3B8);
      case 'gold':
        // FIX: Matches AdminColors.warning
        return AdminColors.warning;
      case 'platinum':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  IconData _tierIcon(String tier) {
    switch (tier) {
      case 'bronze':
        return Icons.shield_rounded;
      case 'silver':
        return Icons.shield_rounded;
      case 'gold':
        return Icons.workspace_premium_rounded;
      case 'platinum':
        return Icons.diamond_rounded;
      default:
        return Icons.shield_rounded;
    }
  }

  Color _rankColor(int idx) {
    switch (idx) {
      case 0:
        return AdminColors.warning; // Gold
      case 1:
        return const Color(0xFF94A3B8); // Silver
      case 2:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return const Color(0xFF94A3B8);
    }
  }

  IconData _rankIcon(int idx) {
    // All top 3 get trophy icon — differentiated by color
    return Icons.emoji_events_rounded;
  }

  IconData _benefitIcon(String? name) {
    switch (name) {
      case 'support':
        return Icons.headset_mic_rounded;
      case 'discount':
        return Icons.percent_rounded;
      case 'priority':
        return Icons.bolt_rounded;
      case 'exclusive':
        return Icons.star_rounded;
      case 'shipping':
        return Icons.local_shipping_rounded;
      case 'warranty':
        return Icons.verified_user_rounded;
      case 'manager':
        return Icons.person_rounded;
      default:
        return Icons.card_giftcard_rounded;
    }
  }


  Widget _editorField(
    BuildContext ctx,
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: TextStyle(color: AdminColors.text(ctx), fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AdminColors.textSub(ctx), fontSize: 13),
        filled: true,
        fillColor: AdminColors.bg(ctx),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
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
    Widget box(double h) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ShimmerLoading(
            child: Container(
              height: h,
              decoration: BoxDecoration(
                color: AdminColors.card(context),
                borderRadius: BorderRadius.circular(Brand.r(18)),
              ),
            ),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          box(90),
          box(90),
          box(200),
          box(160),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: AdminColors.textHint(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load tier data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Check your connection and try again',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.textSub(context),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _load,
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

class _CustomerHistorySheet extends StatefulWidget {
  final Map<String, dynamic> customer;
  final int totalPoints;

  const _CustomerHistorySheet({
    required this.customer,
    required this.totalPoints,
  });

  @override
  State<_CustomerHistorySheet> createState() => _CustomerHistorySheetState();
}

class _CustomerHistorySheetState extends State<_CustomerHistorySheet> {
  final _supabase = SupabaseConfig.client;
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _activities = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final customerId = widget.customer['id'];
      if (customerId == null) {
        throw Exception('Customer ID not found.');
      }
      
      final res = await _supabase
          .from('point_activities')
          .select()
          .eq('user_id', customerId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      
      setState(() {
        _activities = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = widget.customer['full_name'] ?? 'Customer';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AdminColors.bg(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(24))),
      ),
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Brand.darkBorder : Brand.borderLight,
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name\'s History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AdminColors.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total: ${NumberFormat('#,##0').format(widget.totalPoints)} points',
                      style: TextStyle(
                        fontSize: 14,
                        color: AdminColors.textSub(context),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    color: AdminColors.textHint(context)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage, style: TextStyle(color: AdminColors.error)))
                    : _activities.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history_rounded, size: 48, color: AdminColors.textHint(context)),
                                const SizedBox(height: 16),
                                Text(
                                  'No point history',
                                  style: TextStyle(color: AdminColors.textSub(context)),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: _activities.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final p = _activities[index];
                              final type = p['activity_type'] as String? ?? '';
                              final pts = (p['final_points'] as num?)?.toInt() ?? 0;
                              final desc = p['description'] as String? ?? type;
                              final dateStr = p['created_at'] as String? ?? '';
                              final isPositive = pts >= 0;

                              String fmtDate = '';
                              if (dateStr.isNotEmpty) {
                                try {
                                  final dt = DateTime.parse(dateStr).toLocal();
                                  fmtDate = DateFormat('MMM d, yyyy • h:mm a').format(dt);
                                } catch (_) {}
                              }

                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AdminColors.card(context),
                                  borderRadius: BorderRadius.circular(Brand.r(16)),
                                  border: Border.all(
                                    color: AdminColors.border(context),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: (isPositive
                                                ? AdminColors.success
                                                : AdminColors.error)
                                            .withAlpha(26),
                                        borderRadius: BorderRadius.circular(Brand.r(12)),
                                      ),
                                      child: Icon(
                                        isPositive
                                            ? Icons.add_rounded
                                            : Icons.remove_rounded,
                                        size: 24,
                                        color: isPositive
                                            ? AdminColors.success
                                            : AdminColors.error,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            desc,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: AdminColors.text(context),
                                            ),
                                          ),
                                          if (fmtDate.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              fmtDate,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AdminColors.textSub(context),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${isPositive ? '+' : ''}$pts',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: isPositive
                                            ? AdminColors.success
                                            : AdminColors.error,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
