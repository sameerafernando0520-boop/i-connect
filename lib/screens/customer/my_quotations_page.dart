// ════════════════════════════════════════════════════════════════
// Customer — My Quotations (list + inline detail page)
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../l10n/s.dart';
import '../../widgets/ds/ds_widgets.dart';

// ── file-level helpers ──────────────────────────────────────────
final _cur = NumberFormat('#,##0.00', 'en_US');
final _dateFmt = DateFormat('MMM dd, yyyy');

String _fmtCur(dynamic v) => 'Rs. ${_cur.format((v as num?)?.toDouble() ?? 0)}';

String _fmtDate(dynamic v) {
  if (v == null) return '—';
  final dt = DateTime.tryParse(v.toString());
  return dt == null ? '—' : _dateFmt.format(dt);
}

// Unified through the DS status palette (single source of truth).
Color _qStatusColor(String s) => DsStatusPill.colorFor(s);

String _qStatusLabel(String s) {
  switch (s) {
    case 'sent':
      return 'Pending';
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
      return s;
  }
}

// ═══════════════════════════════════════════════════════════════
//  QUOTATION LIST PAGE
// ═══════════════════════════════════════════════════════════════
class MyQuotationsPage extends StatefulWidget {
  const MyQuotationsPage({super.key});

  @override
  State<MyQuotationsPage> createState() => _MyQuotationsPageState();
}

class _MyQuotationsPageState extends State<MyQuotationsPage> {
  List<Map<String, dynamic>> _quotations = [];
  bool _isLoading = true;
  String _filter = 'all';
  DateTime? _lastFetch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── data ────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) return;

      final data = await SupabaseConfig.client
          .from('quotations')
          .select('*')
          .eq('customer_id', uid)
          .neq('status', 'draft')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _quotations = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
        _lastFetch = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(S.of(context)!.quotationLoadFailed)),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: StatusColors.danger,
        ),
      );
    }
  }

  void _refreshIfStale() {
    if (_lastFetch == null ||
        DateTime.now().difference(_lastFetch!).inSeconds > 10) {
      _load();
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _quotations;
    if (_filter == 'active') {
      return _quotations
          .where((q) => ['sent', 'viewed'].contains(q['status']))
          .toList();
    }
    return _quotations.where((q) => q['status'] == _filter).toList();
  }

  // ── build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: Column(
        children: [
          const DsPageHeader(title: 'My Quotations'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: Brand.royalBlue,
              child: _isLoading
                  ? _buildShimmer(isDark)
                  : Column(
                      children: [
                        _buildFilters(isDark),
                        Expanded(
                          child: _filtered.isEmpty
                              ? _buildEmpty(isDark)
                              : _buildList(isDark),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── filter chips ────────────────────────────────────────────
  Widget _buildFilters(bool isDark) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          _chip('All', 'all', isDark),
          _chip('Active', 'active', isDark),
          _chip('Accepted', 'accepted', isDark),
          _chip('Expired', 'expired', isDark),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, bool isDark) {
    final sel = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: sel
              ? Brand.royalBlue.withAlpha(isDark ? 40 : 25)
              : Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(
            color: sel
                ? Brand.royalBlue
                : (isDark ? Brand.darkBorder : Brand.borderLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel
                ? (isDark ? Brand.royalBlueGlow : Brand.royalBlue)
                : (isDark ? Brand.darkTextSecondary : Brand.subtleLight),
            fontSize: 13,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ── list ────────────────────────────────────────────────────
  Widget _buildList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _quoteCard(_filtered[i], isDark),
    );
  }

  Widget _quoteCard(Map<String, dynamic> q, bool isDark) {
    final status = q['status'] as String? ?? 'sent';
    final sc = _qStatusColor(status);
    final total = (q['total_amount'] as num?)?.toDouble() ?? 0;
    final validUntil = DateTime.tryParse(q['valid_until']?.toString() ?? '');
    final validity = _validityLine(status, validUntil);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _QuotationDetailPage(quotation: q),
          ),
        ).then((_) {
          if (mounted) _refreshIfStale();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── row 1: number + status ──
            Row(
              children: [
                Expanded(
                  child: Text(
                    q['quotation_number'] ?? '—',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                ),
                _statusBadge(status, sc),
              ],
            ),
            const SizedBox(height: 12),

            // ── row 2: amount ──
            Text(
              _fmtCur(total),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: isDark ? Colors.white : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 12),

            // ── row 3: dates ──
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 14,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                const SizedBox(width: 6),
                Text(
                  _fmtDate(q['issue_date']),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
                if (validUntil != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward,
                        size: 12,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : Brand.subtleLight),
                  ),
                  Text(
                    'Valid until ${_fmtDate(q['valid_until'])}',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ],
            ),

            // ── row 4: validity hint ──
            if (validity != null) ...[
              const SizedBox(height: 6),
              Text(
                validity.$1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: validity.$2,
                ),
              ),
            ],

            // ── action hint for active quotes ──
            if (['sent', 'viewed'].contains(status)) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.touch_app_rounded,
                      size: 14, color: Brand.royalBlue),
                  const SizedBox(width: 6),
                  Text(
                    'Tap to review & respond',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Brand.royalBlue,
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

  (String, Color)? _validityLine(String status, DateTime? validUntil) {
    if (validUntil == null) return null;
    if (!['sent', 'viewed'].contains(status)) return null;

    final diff = validUntil.difference(DateTime.now()).inDays;
    if (diff < 0) {
      return ('Expired', StatusColors.danger);
    }
    if (diff == 0) {
      return ('Expires today', const Color(0xFFF59E0B));
    }
    if (diff <= 14) {
      return (
        'Valid for $diff more day${diff == 1 ? '' : 's'}',
        const Color(0xFFF59E0B)
      );
    }
    return null;
  }

  Widget _statusBadge(String status, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(26),
        borderRadius: BorderRadius.circular(Brand.r(10)),
      ),
      child: Text(
        _qStatusLabel(status).toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ── shimmer ─────────────────────────────────────────────────
  Widget _buildShimmer(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_box(130, 16, isDark), _box(60, 22, isDark)],
            ),
            const SizedBox(height: 16),
            _box(180, 24, isDark),
            const SizedBox(height: 14),
            _box(210, 14, isDark),
          ],
        ),
      ),
    );
  }

  Widget _box(double w, double h, bool isDark) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: isDark
              ? Brand.darkBorder.withAlpha(80)
              : Brand.borderLight.withAlpha(180),
          borderRadius: BorderRadius.circular(Brand.r(10)),
        ),
      );

  // ── empty ───────────────────────────────────────────────────
  Widget _buildEmpty(bool isDark) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.request_quote_outlined,
                  size: 64,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
              const SizedBox(height: 16),
              Text(
                _filter == 'all'
                    ? 'No quotations yet'
                    : 'No $_filter quotations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your quotations will appear here',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  QUOTATION DETAIL PAGE  (private — navigated from list above)
// ═══════════════════════════════════════════════════════════════
class _QuotationDetailPage extends StatefulWidget {
  final Map<String, dynamic> quotation;

  const _QuotationDetailPage({required this.quotation});

  @override
  State<_QuotationDetailPage> createState() => _QuotationDetailPageState();
}

class _QuotationDetailPageState extends State<_QuotationDetailPage> {
  late Map<String, dynamic> _quo;
  List<Map<String, dynamic>> _items = [];
  bool _detailLoading = true;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _quo = {...widget.quotation};
    _loadDetails();
    _markViewed();
  }

  // ── data ────────────────────────────────────────────────────
  Future<void> _loadDetails() async {
    try {
      final data = await SupabaseConfig.client
          .from('quotations')
          .select('*, quotation_items(*)')
          .eq('id', _quo['id'])
          .single();

      if (!mounted) return;
      final items =
          List<Map<String, dynamic>>.from(data['quotation_items'] ?? []);
      items.sort((a, b) => ((a['display_order'] ?? 0) as int)
          .compareTo((b['display_order'] ?? 0) as int));

      setState(() {
        _quo = {...data};
        _quo.remove('quotation_items');
        _items = items;
        _detailLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _detailLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(S.of(context)!.quotationDetailLoadFailed)),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: StatusColors.danger,
        ),
      );
    }
  }

  Future<void> _markViewed() async {
    try {
      await SupabaseConfig.client.rpc('mark_document_viewed', params: {
        'p_document_id': _quo['id'],
        'p_document_type': 'quotation',
      });
    } catch (_) {}
  }

  // ── accept / reject ─────────────────────────────────────────
  Future<void> _respond(String response) async {
    final verb = response == 'accepted' ? 'accept' : 'reject';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark
            ? Brand.darkCard
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(18))),
        title: Text(
          '${verb[0].toUpperCase()}${verb.substring(1)} Quotation?',
          style: TextStyle(
            color: Theme.of(ctx).brightness == Brightness.dark
                ? Brand.darkTextPrimary
                : Brand.royalBlueDark,
          ),
        ),
        content: Text(
          response == 'accepted'
              ? 'By accepting, you agree to proceed with this quotation. An invoice will be generated for you.'
              : 'Are you sure you want to reject this quotation? You can request a new one later.',
          style: TextStyle(
            color: Theme.of(ctx).brightness == Brightness.dark
                ? Brand.darkTextSecondary
                : Brand.subtleLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(ctx).brightness == Brightness.dark
                    ? Brand.darkTextSecondary
                    : Brand.subtleLight,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: response == 'accepted'
                  ? Brand.lightGreen
                  : StatusColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(10))),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(verb[0].toUpperCase() + verb.substring(1)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _responding = true);
    try {
      final result =
          await SupabaseConfig.client.rpc('respond_to_quotation', params: {
        'p_quotation_id': _quo['id'],
        'p_response': response,
      });

      if (!mounted) return;

      final res = result as Map<String, dynamic>? ?? {};
      if (res['success'] == true) {
        setState(() {
          _quo = {..._quo, 'status': response};
          _responding = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Quotation ${_qStatusLabel(response).toLowerCase()}'),
            ]),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Brand.lightGreen,
          ),
        );
      } else {
        setState(() => _responding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error'] ?? 'Failed to update'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: StatusColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _responding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(S.of(context)!.commonSomethingWentWrong)),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: StatusColors.danger,
        ),
      );
    }
  }

  // ── build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _quo['status'] as String? ?? 'sent';
    final canRespond = ['sent', 'viewed'].contains(status);

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Brand.canvas(isDark),
            foregroundColor: Brand.isWorkshop
                ? Brand.ink(isDark)
                : (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
            elevation: 0,
            scrolledUnderElevation: Brand.isWorkshop ? 0 : 1,
            shape: Brand.isWorkshop
                ? Border(bottom: BorderSide(color: Brand.cardBorder(isDark), width: 1.5))
                : null,
            title: Text(
              _quo['quotation_number'] ?? 'Quotation',
              style: TextStyle(
                fontWeight: Brand.isWorkshop ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: Brand.isWorkshop ? -0.5 : -0.3,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHero(isDark, status),
                const SizedBox(height: 16),
                _buildDates(isDark, status),
                const SizedBox(height: 16),
                if (_detailLoading)
                  ..._shimmerCards(isDark)
                else ...[
                  if (_items.isNotEmpty) ...[
                    _buildItems(isDark),
                    const SizedBox(height: 16),
                  ],
                  _buildFinancials(isDark),
                  if ((_quo['notes'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildNotes(isDark),
                  ],
                  if ((_quo['terms'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildTerms(isDark),
                  ],
                  if (canRespond) ...[
                    const SizedBox(height: 24),
                    _buildActions(isDark),
                  ],
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── hero ────────────────────────────────────────────────────
  Widget _buildHero(bool isDark, String status) {
    final sc = _qStatusColor(status);
    final total = (_quo['total_amount'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            sc.withAlpha(isDark ? 50 : 30),
            sc.withAlpha(isDark ? 25 : 12),
          ],
        ),
        borderRadius: BorderRadius.circular(Brand.r(22)),
        border: Border.all(color: sc.withAlpha(isDark ? 70 : 50)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: sc.withAlpha(40),
              borderRadius: BorderRadius.circular(Brand.r(20)),
              border: Border.all(color: sc.withAlpha(90)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status == 'accepted'
                      ? Icons.check_circle
                      : status == 'rejected'
                          ? Icons.cancel
                          : Icons.request_quote,
                  size: 16,
                  color: sc,
                ),
                const SizedBox(width: 6),
                Text(
                  _qStatusLabel(status),
                  style: TextStyle(
                    color: sc,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _fmtCur(total),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Brand.royalBlueDark,
            ),
          ),
        ],
      ),
    );
  }

  // ── dates ───────────────────────────────────────────────────
  Widget _buildDates(bool isDark, String status) {
    final validUntil = DateTime.tryParse(_quo['valid_until']?.toString() ?? '');
    String? hint;
    Color? hintColor;

    if (validUntil != null && ['sent', 'viewed'].contains(status)) {
      final diff = validUntil.difference(DateTime.now()).inDays;
      if (diff < 0) {
        hint = 'Expired';
        hintColor = StatusColors.danger;
      } else if (diff == 0) {
        hint = 'Expires today';
        hintColor = const Color(0xFFF59E0B);
      } else if (diff <= 14) {
        hint = 'Valid for $diff more day${diff == 1 ? '' : 's'}';
        hintColor = const Color(0xFFF59E0B);
      }
    }

    return _section(
      title: S.of(context)!.quotationDates,
      icon: Icons.event_outlined,
      isDark: isDark,
      child: Column(
        children: [
          _row('Issued', _fmtDate(_quo['issue_date']), isDark),
          const SizedBox(height: 8),
          _row('Valid Until', _fmtDate(_quo['valid_until']), isDark,
              hint: hint, hintColor: hintColor),
          if (_quo['accepted_at'] != null) ...[
            const SizedBox(height: 8),
            _row('Accepted', _fmtDate(_quo['accepted_at']), isDark),
          ],
          if (_quo['rejected_at'] != null) ...[
            const SizedBox(height: 8),
            _row('Rejected', _fmtDate(_quo['rejected_at']), isDark),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, bool isDark,
      {String? hint, Color? hintColor}) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
        ),
        if (hint != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (hintColor ?? Brand.royalBlue).withAlpha(20),
              borderRadius: BorderRadius.circular(Brand.r(8)),
            ),
            child: Text(
              hint,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: hintColor ?? Brand.royalBlue,
              ),
            ),
          ),
      ],
    );
  }

  // ── items ───────────────────────────────────────────────────
  Widget _buildItems(bool isDark) {
    return _section(
      title: 'Items (${_items.length})',
      icon: Icons.list_alt_rounded,
      isDark: isDark,
      child: Column(
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
          final totalPrice = (item['total_price'] as num?)?.toDouble() ?? 0;
          final isLast = i == _items.length - 1;

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: isLast
                ? null
                : BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Brand.darkBorder : Brand.borderLight,
                      ),
                    ),
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Brand.royalBlue.withAlpha(isDark ? 40 : 20),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Brand.royalBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['description'] ?? '—',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$qty × ${_fmtCur(unitPrice)}',
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
                const SizedBox(width: 8),
                Text(
                  _fmtCur(totalPrice),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Brand.royalBlueDark,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── financials ──────────────────────────────────────────────
  Widget _buildFinancials(bool isDark) {
    final subtotal = (_quo['subtotal'] as num?)?.toDouble() ?? 0;
    final discAmt = (_quo['discount_amount'] as num?)?.toDouble() ?? 0;
    final taxAmt = (_quo['tax_amount'] as num?)?.toDouble() ?? 0;
    final total = (_quo['total_amount'] as num?)?.toDouble() ?? 0;
    final taxRate = (_quo['tax_rate'] as num?)?.toDouble();
    final discType = _quo['discount_type'] as String?;
    final discVal = (_quo['discount_value'] as num?)?.toDouble();

    String discLabel = 'Discount';
    if (discType == 'percentage' && discVal != null) {
      discLabel = 'Discount (${discVal.toStringAsFixed(0)}%)';
    }

    String taxLabel = 'Tax';
    if (taxRate != null && taxRate > 0) {
      taxLabel = 'Tax (${taxRate.toStringAsFixed(0)}%)';
    }

    return _section(
      title: S.of(context)!.quotationSummary,
      icon: Icons.calculate_outlined,
      isDark: isDark,
      child: Column(
        children: [
          _sumRow('Subtotal', _fmtCur(subtotal), isDark),
          if (discAmt > 0) ...[
            const SizedBox(height: 6),
            _sumRow(discLabel, '- ${_fmtCur(discAmt)}', isDark,
                valueColor: const Color(0xFFF59E0B)),
          ],
          if (taxAmt > 0) ...[
            const SizedBox(height: 6),
            _sumRow(taxLabel, _fmtCur(taxAmt), isDark),
          ],
          const SizedBox(height: 10),
          Divider(
            color: isDark ? Brand.darkBorder : Brand.borderLight,
            height: 1,
          ),
          const SizedBox(height: 10),
          _sumRow('Total', _fmtCur(total), isDark, bold: true, large: true),
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value, bool isDark,
      {bool bold = false, bool large = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: large ? 15 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: large ? 17 : 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: valueColor ??
                (isDark ? Brand.darkTextPrimary : Brand.royalBlueDark),
          ),
        ),
      ],
    );
  }

  // ── notes ───────────────────────────────────────────────────
  Widget _buildNotes(bool isDark) {
    return _section(
      title: S.of(context)!.quotationNotes,
      icon: Icons.notes_rounded,
      isDark: isDark,
      child: Text(
        _quo['notes'] as String? ?? '',
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        ),
      ),
    );
  }

  Widget _buildTerms(bool isDark) {
    return _section(
      title: 'Terms & Conditions',
      icon: Icons.gavel_rounded,
      isDark: isDark,
      child: Text(
        _quo['terms'] as String? ?? '',
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        ),
      ),
    );
  }

  // ── accept / reject buttons ─────────────────────────────────
  Widget _buildActions(bool isDark) {
    return Row(
      children: [
        // ── reject ──
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _responding ? null : () => _respond('rejected'),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(S.of(context)!.quotationReject),
            style: OutlinedButton.styleFrom(
              foregroundColor: StatusColors.danger,
              side: const BorderSide(color: Color(0xFFEF4444)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(14))),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // ── accept ──
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _responding ? null : () => _respond('accepted'),
            icon: _responding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_responding
                ? S.of(context)!.quotationProcessing
                : S.of(context)!.quotationAcceptQuotation),
            style: FilledButton.styleFrom(
              backgroundColor: Brand.lightGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(14))),
            ),
          ),
        ),
      ],
    );
  }

  // ── shimmer cards ───────────────────────────────────────────
  List<Widget> _shimmerCards(bool isDark) {
    return List.generate(
      3,
      (_) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 120,
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(18)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
      ),
    );
  }

  // ── section wrapper ─────────────────────────────────────────
  Widget _section({
    required String title,
    required IconData icon,
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Brand.royalBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
