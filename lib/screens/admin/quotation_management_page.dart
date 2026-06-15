import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../widgets/admin/shimmer_loading.dart';
import 'create_quotation_page.dart';
import 'admin_quotation_detail_page.dart';

class QuotationManagementPage extends StatefulWidget {
  const QuotationManagementPage({super.key});

  @override
  State<QuotationManagementPage> createState() =>
      _QuotationManagementPageState();
}

class _QuotationManagementPageState extends State<QuotationManagementPage> {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0.00', 'en_US');
  final _dateFmt = DateFormat('MMM d, yyyy');
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _quotations = [];
  String? _statusFilter;
  bool _showSearch = false;
  Timer? _debounce;

  // FIX: Use AdminColors named constants instead of hardcoded Color values
  // Color references are resolved at runtime via _statusColor(), so we keep
  // the filter list with AdminColors-aligned colors.
  // Using static const tuples — colors must be const, so we use literal
  // values that match AdminColors exactly.
  static const _filters = <(String?, String, Color)>[
    (null, 'All', AdminColors.primary),
    ('draft', 'Draft', Color(0xFF94A3B8)),
    ('sent', 'Sent', Color(0xFF8B5CF6)),
    ('viewed', 'Viewed', Color(0xFF06B6D4)),
    // FIX: Use AdminColors.success literal value (0xFF22C55E matches)
    ('accepted', 'Accepted', Color(0xFF22C55E)),
    // FIX: Use AdminColors.error literal value (0xFFEF4444 matches)
    ('rejected', 'Rejected', Color(0xFFEF4444)),
    // FIX: Use AdminColors.warning literal value (0xFFF59E0B matches)
    ('expired', 'Expired', Color(0xFFF59E0B)),
    // FIX: Use AdminColors.info literal value (0xFF3B82F6 matches)
    ('converted', 'Converted', Color(0xFF3B82F6)),
  ];

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _supabase.rpc('get_all_quotations', params: {
        'p_status_filter': _statusFilter,
        'p_search':
            _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _quotations = List<Map<String, dynamic>>.from(res as List? ?? []);
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

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _load);
  }

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  // FIX: Format raw date string (yyyy-MM-dd) → MMM d, yyyy
  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return _dateFmt.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : AdminColors.background,
      floatingActionButton: _buildFAB(isDark),
      appBar: DsPageHeader(
        title: 'Quotations',
        subtitle: '${_quotations.length} total',
        accent: HeroAccent.navy,
        actions: [
          IconButton(icon: const Icon(Icons.search_rounded, color: Colors.white), onPressed: () { setState(() { _showSearch = !_showSearch; if (!_showSearch) { _searchCtrl.clear(); _load(); } }); }),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterChips(isDark),
            if (_showSearch) _buildSearchBar(isDark),
            Expanded(
              child: _loading
                  ? _buildShimmer(isDark)
                  : _error != null
                      ? _buildError(isDark)
                      : _quotations.isEmpty
                          ? _buildEmpty(isDark)
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: AdminColors.primary,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                itemCount: _quotations.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) =>
                                    _buildCard(_quotations[i], isDark),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: isDark ? Border.all(color: Brand.darkBorder) : null,
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
        controller: _searchCtrl,
        autofocus: true,
        style: TextStyle(
          color: isDark ? Brand.darkTextPrimary : const Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          hintText: 'Search quotations…',
          hintStyle: TextStyle(
            color: isDark ? Brand.darkTextTertiary : const Color(0xFF94A3B8),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Brand.darkTextTertiary : const Color(0xFF94A3B8),
            size: 22,
          ),
          filled: true,
          fillColor: isDark ? Brand.darkCard : Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.r(14)),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildFAB(bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreateQuotationPage()),
      ).then((created) {
        if (created == true && mounted) _load();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
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
            Icon(Icons.add_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'New Quote',
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

  // ═══════════════════════════════════════════════════════
  //  FILTER CHIPS
  // ═══════════════════════════════════════════════════════

  Widget _buildFilterChips(bool isDark) {
    return Container(
      color: AdminColors.card(context),
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: _filters.map((f) {
            final selected = _statusFilter == f.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8, top: 10),
              child: GestureDetector(
                onTap: () {
                  // FIX: Avoid redundant load when tapping
                  //      already-selected filter
                  final newFilter = selected ? null : f.$1;
                  if (newFilter == _statusFilter) return;
                  setState(() => _statusFilter = newFilter);
                  _load();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? f.$3.withAlpha(isDark ? 40 : 25)
                        : AdminColors.bg(context),
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
  //  QUOTATION CARD
  // ═══════════════════════════════════════════════════════

  Widget _buildCard(Map<String, dynamic> q, bool isDark) {
    final status = q['status']?.toString() ?? 'draft';
    final sColor = _statusColor(status);
    final validUntilRaw = q['valid_until']?.toString() ?? '';
    final validUntilFormatted = _formatDate(validUntilRaw);

    // FIX: Include 'viewed' in expired check — viewed quotes
    //      can also be past their valid_until date
    final isExpired = validUntilRaw.isNotEmpty &&
        DateTime.tryParse(validUntilRaw)?.isBefore(DateTime.now()) == true &&
        ['sent', 'viewed'].contains(status);

    return Material(
      color: AdminColors.card(context),
      borderRadius: BorderRadius.circular(Brand.r(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Brand.r(16)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AdminQuotationDetailPage(quotationId: q['id'] as String),
          ),
        ).then((_) {
          if (mounted) _load();
        }),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.r(16)),
            border: Border.all(
              // FIX: Use AdminColors.warning instead of hardcoded
              color: isExpired
                  ? AdminColors.warning.withAlpha(60)
                  : AdminColors.border(context),
            ),
          ),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: sColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                child: Icon(
                  Icons.request_quote_rounded,
                  size: 20,
                  color: sColor,
                ),
              ),
              const SizedBox(width: 14),
              // Centre content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          q['quotation_number']?.toString() ?? '—',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AdminColors.text(context),
                          ),
                        ),
                        // FIX: Expiry warning indicator on card
                        if (isExpired) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: AdminColors.warning,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      q['customer_name']?.toString() ?? 'Unknown Customer',
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSub(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (validUntilFormatted.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      // FIX: Show formatted date instead of raw string
                      Text(
                        'Valid until $validUntilFormatted',
                        style: TextStyle(
                          fontSize: 12,
                          color: isExpired
                              // FIX: AdminColors.warning not hardcoded
                              ? AdminColors.warning
                              : AdminColors.textHint(context),
                        ),
                      ),
                    ],
                    // FIX: Show item count if available
                    if (q['item_count'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${q['item_count']} item${(q['item_count'] as int? ?? 0) > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.textHint(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right side
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Rs. ${_fmt.format(_d(q['total_amount']))}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.text(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _statusBadge(status, sColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  // FIX: Use AdminColors named constants where matched,
  //      static const Color for others (no context needed)
  Color _statusColor(String s) {
    switch (s) {
      case 'draft':
        return const Color(0xFF94A3B8);
      case 'sent':
        return const Color(0xFF8B5CF6);
      case 'viewed':
        return const Color(0xFF06B6D4);
      case 'accepted':
        // Matches AdminColors.success
        return AdminColors.success;
      case 'rejected':
        // Matches AdminColors.error
        return AdminColors.error;
      case 'expired':
        // Matches AdminColors.warning
        return AdminColors.warning;
      case 'converted':
        // Matches AdminColors.info
        return AdminColors.info;
      default:
        return const Color(0xFF94A3B8);
    }
  }

  Widget _statusBadge(String status, Color color) {
    final label = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(Brand.r(8)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // FIX: Dedicated label method — avoids repeated ternary logic
  String _statusLabel(String s) {
    switch (s) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'viewed':
        return 'Viewed';
      case 'accepted':
        return 'Accepted';
      case 'rejected':
        return 'Rejected';
      case 'expired':
        return 'Expired';
      case 'converted':
        return 'Converted';
      default:
        if (s.isEmpty) return '—';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  Widget _buildShimmer(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => ShimmerLoading(
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: AdminColors.card(context),
            borderRadius: BorderRadius.circular(Brand.r(16)),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    // FIX: Safe null handling for status filter in message
    final filterLabel =
        _statusFilter != null ? _statusLabel(_statusFilter!) : null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.request_quote_rounded,
            size: 56,
            color: AdminColors.textHint(context),
          ),
          const SizedBox(height: 16),
          Text(
            // FIX: Use _statusLabel for proper capitalisation,
            //      not raw _statusFilter (avoids 'No null quotations')
            filterLabel != null
                ? 'No $filterLabel quotations'
                : 'No quotations yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AdminColors.text(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filterLabel != null
                ? 'Try a different filter or create a new quotation'
                : 'Tap + to create your first quotation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AdminColors.textSub(context),
            ),
          ),
          if (_statusFilter != null) ...[
            const SizedBox(height: 16),
            // FIX: Quick clear filter button in empty state
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _statusFilter = null);
                _load();
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
              'Failed to load quotations',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again',
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
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
