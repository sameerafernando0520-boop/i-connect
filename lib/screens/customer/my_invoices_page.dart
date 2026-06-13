// ════════════════════════════════════════════════════════════════
// Customer — My Invoices (list with filters)
// ════════════════════════════════════════════════════════════════

import 'package:i_connect/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import 'customer_invoice_detail_page.dart';

// ── file-level helpers ──────────────────────────────────────────
final _cur = NumberFormat('#,##0.00', 'en_US');
final _dateFmt = DateFormat('MMM dd, yyyy');

String _fmtCur(dynamic v) => 'Rs. ${_cur.format((v as num?)?.toDouble() ?? 0)}';

String _fmtDate(dynamic v) {
  if (v == null) return '—';
  final dt = DateTime.tryParse(v.toString());
  return dt == null ? '—' : _dateFmt.format(dt);
}

Color _statusColor(String s) {
  switch (s) {
    case 'sent':
      return Brand.royalBlue;
    case 'viewed':
      return const Color(0xFF06B6D4);
    case 'partially_paid':
      return const Color(0xFFF59E0B);
    case 'paid':
      return Brand.lightGreen;
    case 'overdue':
      return const Color(0xFFEF4444);
    case 'cancelled':
      return const Color(0xFF6B7280);
    case 'refunded':
      return const Color(0xFF8B5CF6);
    default:
      return const Color(0xFF6B7280);
  }
}

String _statusLabel(S t, String s) {
  switch (s) {
    case 'sent':
      return t.invoiceStatusSent;
    case 'viewed':
      return t.invoiceStatusViewed;
    case 'partially_paid':
      return t.invoiceStatusPartialShort;
    case 'paid':
      return t.invoiceStatusPaid;
    case 'overdue':
      return t.invoiceStatusOverdue;
    case 'cancelled':
      return t.invoiceStatusCancelled;
    case 'refunded':
      return t.invoiceStatusRefunded;
    default:
      return s;
  }
}

// ── page ────────────────────────────────────────────────────────
class MyInvoicesPage extends StatefulWidget {
  const MyInvoicesPage({super.key});

  @override
  State<MyInvoicesPage> createState() => _MyInvoicesPageState();
}

class _MyInvoicesPageState extends State<MyInvoicesPage> {
  List<Map<String, dynamic>> _invoices = [];
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
          .from('invoices')
          .select('*')
          .eq('customer_id', uid)
          .neq('status', 'draft')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _invoices = List<Map<String, dynamic>>.from(data);
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
            Expanded(child: Text(S.of(context)!.invoiceLoadFailed)),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
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
    if (_filter == 'all') return _invoices;
    if (_filter == 'unpaid') {
      return _invoices
          .where(
              (i) => ['sent', 'viewed', 'partially_paid'].contains(i['status']))
          .toList();
    }
    return _invoices.where((i) => i['status'] == _filter).toList();
  }

  // ── build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = S.of(context)!;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: AppBar(
        title: Text(
          t.invoiceMyInvoices,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        backgroundColor: isDark ? Brand.darkBg : Colors.white,
        foregroundColor: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: Brand.royalBlue,
        child: _isLoading
            ? _buildShimmer(isDark)
            : Column(
                children: [
                  _buildFilters(isDark, t),
                  Expanded(
                    child: _filtered.isEmpty
                        ? _buildEmpty(isDark, t)
                        : _buildList(isDark, t),
                  ),
                ],
              ),
      ),
    );
  }

  // ── filter chips ────────────────────────────────────────────
  Widget _buildFilters(bool isDark, S t) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          _chip(t.commonAll, 'all', isDark),
          _chip(t.statusUnpaid, 'unpaid', isDark),
          _chip(t.invoiceStatusPaid, 'paid', isDark),
          _chip(t.invoiceStatusOverdue, 'overdue', isDark),
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
              : (isDark ? Brand.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(20),
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
  Widget _buildList(bool isDark, S t) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _invoiceCard(_filtered[i], isDark, t),
    );
  }

  Widget _invoiceCard(Map<String, dynamic> inv, bool isDark, S t) {
    final status = inv['status'] as String? ?? 'sent';
    final sColor = _statusColor(status);
    final total = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    final balance = (inv['balance_due'] as num?)?.toDouble() ?? 0;
    final dueDate = DateTime.tryParse(inv['due_date']?.toString() ?? '');
    final dueSub = _dueLine(t, status, dueDate);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerInvoiceDetailPage(invoice: inv),
          ),
        ).then((_) {
          if (mounted) _refreshIfStale();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
                    inv['invoice_number'] ?? '—',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                    ),
                  ),
                ),
                _statusBadge(t, status, sColor),
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
            if (status == 'partially_paid') ...[
              const SizedBox(height: 4),
              Text(
                t.invoiceBalanceAmount(_fmtCur(balance)),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // ── row 3: dates ──
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 14,
                    color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                const SizedBox(width: 6),
                Text(
                  _fmtDate(inv['issue_date']),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ),
                if (dueDate != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward,
                        size: 12,
                        color: isDark
                            ? Brand.darkTextTertiary
                            : Brand.subtleLight),
                  ),
                  Text(
                    _fmtDate(inv['due_date']),
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                ],
              ],
            ),

            // ── row 4: due sub-line ──
            if (dueSub != null) ...[
              const SizedBox(height: 6),
              Text(
                dueSub.$1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: dueSub.$2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Returns (label, color) for the due-date hint line, or null.
  (String, Color)? _dueLine(S t, String status, DateTime? due) {
    if (due == null) return null;
    if (['paid', 'cancelled', 'refunded'].contains(status)) return null;

    final diff = due.difference(DateTime.now()).inDays;
    if (status == 'overdue' || diff < 0) {
      final d = diff.abs();
      return (t.invoiceOverdueByDays(d), const Color(0xFFEF4444));
    }
    if (diff == 0) return (t.invoiceDueToday, const Color(0xFFF59E0B));
    if (diff <= 7) {
      return (t.invoiceDueInDays(diff), const Color(0xFFF59E0B));
    }
    return null;
  }

  Widget _statusBadge(S t, String status, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _statusLabel(t, status).toUpperCase(),
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
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
          borderRadius: BorderRadius.circular(10),
        ),
      );

  // ── empty ───────────────────────────────────────────────────
  Widget _buildEmpty(bool isDark, S t) {
    return ListView(
      // ListView so RefreshIndicator still works
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 64,
                  color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
              const SizedBox(height: 16),
              Text(
                _filter == 'all'
                    ? t.invoiceNoInvoicesYet
                    : t.invoiceFilterNoResults(_statusLabel(t, _filter)),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.invoiceNoInvoicesDesc,
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
