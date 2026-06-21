// lib/screens/admin/payment_dashboard_page.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../widgets/admin/shimmer_loading.dart';
import 'admin_invoice_detail_page.dart';

class PaymentDashboardPage extends StatefulWidget {
  const PaymentDashboardPage({super.key});

  @override
  State<PaymentDashboardPage> createState() => _PaymentDashboardPageState();
}

class _PaymentDashboardPageState extends State<PaymentDashboardPage> {
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  bool _loading = true;
  Map<String, dynamic> _data = {};
  String? _error;

  // ── Lifecycle ──────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // FIX: added mounted check at start
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await SupabaseConfig.client.rpc('get_payment_dashboard');
      if (!mounted) return;
      setState(() {
        if (res is Map<String, dynamic>) {
          _data = res;
        } else if (res is List && res.isNotEmpty && res.first is Map) {
          _data = Map<String, dynamic>.from(res.first as Map);
        } else {
          _data = {};
        }
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

  // ── Parse helpers ──────────────────────────────────────

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

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Payment Dashboard',
        accent: HeroAccent.navy,
      ),
      body: _loading
          ? _buildShimmer(isDark)
          : _error != null
              ? _buildError(isDark)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: Brand.royalBlue,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryCards(isDark),
                        const SizedBox(height: 24),
                        _buildRevenueChart(isDark),
                        const SizedBox(height: 24),
                        _buildStatusBreakdown(isDark),
                        const SizedBox(height: 24),
                        _buildRecentInvoices(isDark),
                        const SizedBox(height: 24),
                        _buildRecentPayments(isDark),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  1.  SUMMARY CARDS  (2×2 grid)
  // ═══════════════════════════════════════════════════════

  Widget _buildSummaryCards(bool isDark) {
    final s = _data['summary'] as Map<String, dynamic>? ?? {};

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                isDark: isDark,
                title: 'Total Revenue',
                value: 'Rs. ${_fmt.format(_d(s['total_paid']))}',
                sub: '${_i(s['paid_invoices'])} paid',
                icon: Icons.account_balance_wallet_rounded,
                color: Brand.lightGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                isDark: isDark,
                title: 'Outstanding',
                value: 'Rs. ${_fmt.format(_d(s['total_outstanding']))}',
                sub: '${_i(s['unpaid_invoices'])} unpaid',
                icon: Icons.pending_actions_rounded,
                color: Brand.royalBlue,
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
                title: 'Overdue',
                value: 'Rs. ${_fmt.format(_d(s['total_overdue']))}',
                sub: '${_i(s['overdue_invoices'])} overdue',
                icon: Icons.warning_amber_rounded,
                color: AdminColors.error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                isDark: isDark,
                title: 'This Month',
                value: 'Rs. ${_fmt.format(_d(s['this_month_revenue']))}',
                sub: null,
                icon: Icons.trending_up_rounded,
                color: StatusColors.assigned,
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
    String? sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // FIX: replaced Colors.white with Brand.cardLight
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  2.  REVENUE BAR CHART  (last 6 months)
  // ═══════════════════════════════════════════════════════

  Widget _buildRevenueChart(bool isDark) {
    final months = _data['monthly_revenue'] as List? ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // FIX: replaced Colors.white with Brand.cardLight
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revenue Trend',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Last 6 months',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
          const SizedBox(height: 20),
          if (months.isEmpty)
            SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bar_chart_rounded,
                      size: 40,
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No revenue data yet',
                      style: TextStyle(
                        color:
                            isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: BarChart(
                _buildBarChartData(months, isDark),
              ),
            ),
        ],
      ),
    );
  }

  BarChartData _buildBarChartData(
    List months,
    bool isDark,
  ) {
    final maxY = _chartMaxY(months);
    final barW = months.length <= 4 ? 28.0 : 18.0;
    // FIX: guard against division by zero
    final hInterval = maxY > 0 ? maxY / 4 : 25000.0;

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) =>
              isDark ? Brand.darkCardElevated : Brand.cardLight,
          getTooltipItem: (group, gi, rod, ri) {
            final item = months[gi] as Map<String, dynamic>;
            return BarTooltipItem(
              'Rs. ${_fmt.format(_d(item['total']))}',
              TextStyle(
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 52,
            getTitlesWidget: (v, _) => Text(
              _axisLabel(v),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, _) {
              final idx = v.toInt();
              if (idx < 0 || idx >= months.length) {
                return const SizedBox.shrink();
              }
              final m = (months[idx] as Map)['month']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _monthLabel(m),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        // FIX: safe interval
        horizontalInterval: hInterval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: isDark ? Brand.darkBorder : Brand.borderLight,
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      barGroups: List.generate(months.length, (i) {
        final item = months[i] as Map<String, dynamic>;
        return BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: _d(item['total']),
              color: Brand.royalBlue,
              width: barW,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(Brand.r(6)),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY,
                color: isDark
                    ? Brand.darkBorder.withAlpha(77)
                    : Brand.royalBlueSurface.withAlpha(77),
              ),
            ),
          ],
        );
      }),
    );
  }

  double _chartMaxY(List months) {
    double mx = 0;
    for (final m in months) {
      final v = _d((m as Map)['total']);
      if (v > mx) mx = v;
    }
    return mx > 0 ? mx * 1.2 : 100000;
  }

  String _axisLabel(double v) {
    if (v >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(1)}M';
    }
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(0)}K';
    }
    return v.toStringAsFixed(0);
  }

  String _monthLabel(String yyyyMM) {
    if (yyyyMM.length < 7) return yyyyMM;
    try {
      return DateFormat('MMM').format(DateTime.parse('$yyyyMM-01'));
    } catch (_) {
      return yyyyMM.substring(5);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  3.  INVOICE STATUS BREAKDOWN  (horizontal bars)
  // ═══════════════════════════════════════════════════════

  Widget _buildStatusBreakdown(bool isDark) {
    final counts = _data['status_counts'] as Map<String, dynamic>? ?? {};
    final total = counts.values.fold<int>(0, (s, v) => s + _i(v));

    const statuses = <(String, String, Color)>[
      ('paid', 'Paid', Brand.lightGreen),
      ('partially_paid', 'Partial', AdminColors.info),
      ('sent', 'Sent', StatusColors.assigned),
      ('viewed', 'Viewed', StatusColors.info),
      ('overdue', 'Overdue', AdminColors.error),
      ('draft', 'Draft', Brand.subtleLight),
      ('cancelled', 'Cancelled', StatusColors.gray),
      ('refunded', 'Refunded', AdminColors.warning),
    ];

    final visible = statuses.where((s) => _i(counts[s.$1]) > 0).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // FIX: replaced Colors.white with Brand.cardLight
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
              Text(
                'Invoice Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const Spacer(),
              Text(
                '$total total',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 16,
              ),
              child: Center(
                child: Text(
                  'No invoices yet',
                  style: TextStyle(
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  ),
                ),
              ),
            )
          else
            ...visible.map((s) {
              final cnt = _i(counts[s.$1]);
              // FIX: explicit double division
              final pct = total > 0 ? cnt / total.toDouble() : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.$3,
                        borderRadius: BorderRadius.circular(Brand.r(3)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 65,
                      child: Text(
                        s.$2,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Brand.r(4)),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 8,
                          backgroundColor:
                              isDark ? Brand.darkBorder : Brand.borderLight,
                          valueColor: AlwaysStoppedAnimation(s.$3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 26,
                      child: Text(
                        '$cnt',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
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

  // ═══════════════════════════════════════════════════════
  //  4.  RECENT INVOICES
  // ═══════════════════════════════════════════════════════

  Widget _buildRecentInvoices(bool isDark) {
    final invoices = _data['recent_invoices'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Text(
                'Recent Invoices',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const Spacer(),
              if (invoices.isNotEmpty)
                Text(
                  'Latest ${invoices.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  ),
                ),
            ],
          ),
        ),
        if (invoices.isEmpty)
          _emptyCard(
            isDark: isDark,
            icon: Icons.receipt_long_rounded,
            label: 'No invoices yet',
          )
        else
          ...invoices.map(
            (inv) => _invoiceRow(
              inv as Map<String, dynamic>,
              isDark,
            ),
          ),
      ],
    );
  }

  Widget _invoiceRow(
    Map<String, dynamic> i,
    bool isDark,
  ) {
    final status = i['status']?.toString() ?? 'draft';
    final sColor = _statusColor(status);
    final due = i['due_date']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        // FIX: replaced Colors.white with Brand.cardLight
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Brand.r(16)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminInvoiceDetailPage(
                invoiceId: i['id'].toString(),
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.r(16)),
              border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: sColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(Brand.r(12)),
                  ),
                  child: Icon(
                    Icons.receipt_rounded,
                    size: 20,
                    color: sColor,
                  ),
                ),
                const SizedBox(width: 14),
                // Centre
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i['invoice_number']?.toString() ?? '—',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        i['customer_name']?.toString() ?? 'Unknown',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Brand.subtleLight,
                        ),
                      ),
                      if (due.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Due $due',
                          style: TextStyle(
                            fontSize: 12,
                            color: status == 'overdue'
                                ? AdminColors.error
                                : isDark
                                    ? Brand.darkTextTertiary
                                    : Brand.subtleLight,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Right
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rs. ${_fmt.format(_d(i['total_amount']))}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _badge(status, sColor),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  5.  RECENT PAYMENTS
  // ═══════════════════════════════════════════════════════

  Widget _buildRecentPayments(bool isDark) {
    final payments = _data['recent_payments'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Text(
                'Recent Payments',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const Spacer(),
              if (payments.isNotEmpty)
                Text(
                  'Latest ${payments.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                  ),
                ),
            ],
          ),
        ),
        if (payments.isEmpty)
          _emptyCard(
            isDark: isDark,
            icon: Icons.payments_rounded,
            label: 'No payments recorded yet',
          )
        else
          ...payments.map(
            (p) => _paymentRow(
              p as Map<String, dynamic>,
              isDark,
            ),
          ),
      ],
    );
  }

  Widget _paymentRow(
    Map<String, dynamic> p,
    bool isDark,
  ) {
    final method = p['payment_method']?.toString() ?? 'unknown';
    final verified = p['verified'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // FIX: replaced Colors.white with Brand.cardLight
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(16)),
          border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Brand.lightGreen.withAlpha(26),
                borderRadius: BorderRadius.circular(Brand.r(12)),
              ),
              child: Icon(
                _methodIcon(method),
                size: 20,
                color: Brand.lightGreen,
              ),
            ),
            const SizedBox(width: 14),
            // Centre
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['payment_number']?.toString() ?? '—',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: p['customer_name']?.toString() ?? 'Unknown',
                        ),
                        TextSpan(
                          text: '  •  ${_methodLabel(method)}',
                          style: TextStyle(
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Brand.subtleLight,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
            // Right
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs. ${_fmt.format(_d(p['amount']))}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Brand.lightGreen,
                  ),
                ),
                const SizedBox(height: 4),
                if (verified)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: Brand.lightGreen,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Verified',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Brand.lightGreen,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  Color _statusColor(String s) {
    switch (s) {
      case 'paid':
        return Brand.lightGreen;
      case 'partially_paid':
        return AdminColors.info;
      case 'sent':
        return StatusColors.assigned;
      case 'viewed':
        return StatusColors.info;
      case 'overdue':
        return AdminColors.error;
      case 'draft':
        return Brand.subtleLight;
      case 'cancelled':
        return StatusColors.gray;
      case 'refunded':
        return AdminColors.warning;
      default:
        return Brand.subtleLight;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'partially_paid':
        return 'Partial';
      default:
        if (s.isEmpty) return '—';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  Widget _badge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
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

  IconData _methodIcon(String m) {
    switch (m) {
      case 'bank_transfer':
        return Icons.account_balance_rounded;
      case 'cash':
        return Icons.payments_rounded;
      case 'cheque':
        return Icons.description_rounded;
      case 'card':
        return Icons.credit_card_rounded;
      case 'online':
        return Icons.language_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'bank_transfer':
        return 'Bank';
      case 'cash':
        return 'Cash';
      case 'cheque':
        return 'Cheque';
      case 'card':
        return 'Card';
      case 'online':
        return 'Online';
      default:
        return m;
    }
  }

  Widget _emptyCard({
    required bool isDark,
    required IconData icon,
    required String label,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        // FIX: replaced Colors.white with Brand.cardLight
        color: Brand.surface(isDark),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SHIMMER  +  ERROR
  // ═══════════════════════════════════════════════════════

  Widget _buildShimmer(bool isDark) {
    Widget box(double h) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ShimmerLoading(
            child: Container(
              height: h,
              decoration: BoxDecoration(
                // FIX: replaced Colors.white with Brand.cardLight
                color: Brand.surface(isDark),
                borderRadius: BorderRadius.circular(Brand.r(18)),
              ),
            ),
          ),
        );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // FIX: added SizedBox(height:12) between stat rows
          // (matched the real layout gap)
          Row(
            children: [
              Expanded(child: box(130)),
              const SizedBox(width: 12),
              Expanded(child: box(130)),
            ],
          ),
          // Already has bottom padding from box()
          Row(
            children: [
              Expanded(child: box(130)),
              const SizedBox(width: 12),
              Expanded(child: box(130)),
            ],
          ),
          box(260),
          box(200),
          ...List.generate(3, (_) => box(80)),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load dashboard',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Brand.royalBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
