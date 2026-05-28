// ════════════════════════════════════════════════════════════════
// Customer — Invoice Detail
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';

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

String _statusLabel(String s) {
  switch (s) {
    case 'sent':
      return 'Sent';
    case 'viewed':
      return 'Viewed';
    case 'partially_paid':
      return 'Partially Paid';
    case 'paid':
      return 'Paid';
    case 'overdue':
      return 'Overdue';
    case 'cancelled':
      return 'Cancelled';
    case 'refunded':
      return 'Refunded';
    default:
      return s;
  }
}

IconData _paymentIcon(String m) {
  switch (m) {
    case 'bank_transfer':
      return Icons.account_balance;
    case 'cash':
      return Icons.money;
    case 'cheque':
      return Icons.receipt_long;
    case 'card':
      return Icons.credit_card;
    case 'online':
      return Icons.language;
    default:
      return Icons.payment;
  }
}

String _paymentLabel(String m) {
  switch (m) {
    case 'bank_transfer':
      return 'Bank Transfer';
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

// ── page ────────────────────────────────────────────────────────
class CustomerInvoiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> invoice;

  const CustomerInvoiceDetailPage({super.key, required this.invoice});

  @override
  State<CustomerInvoiceDetailPage> createState() =>
      _CustomerInvoiceDetailPageState();
}

class _CustomerInvoiceDetailPageState extends State<CustomerInvoiceDetailPage> {
  late Map<String, dynamic> _inv;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];
  bool _detailLoading = true;

  @override
  void initState() {
    super.initState();
    _inv = {...widget.invoice};
    _loadDetails();
    _markViewed();
  }

  // ── data ────────────────────────────────────────────────────
  Future<void> _loadDetails() async {
    try {
      final data = await SupabaseConfig.client
          .from('invoices')
          .select('*, invoice_items(*), payments(*)')
          .eq('id', _inv['id'])
          .single();

      if (!mounted) return;
      final items =
          List<Map<String, dynamic>>.from(data['invoice_items'] ?? []);
      items.sort((a, b) => ((a['display_order'] ?? 0) as int)
          .compareTo((b['display_order'] ?? 0) as int));

      final pay = List<Map<String, dynamic>>.from(data['payments'] ?? []);
      pay.sort((a, b) {
        final da = DateTime.tryParse(a['payment_date']?.toString() ?? '') ??
            DateTime(2000);
        final db = DateTime.tryParse(b['payment_date']?.toString() ?? '') ??
            DateTime(2000);
        return da.compareTo(db);
      });

      setState(() {
        _inv = {...data};
        // Remove nested lists from _inv map to keep it clean
        _inv.remove('invoice_items');
        _inv.remove('payments');
        _items = items;
        _payments = pay;
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
            const Expanded(child: Text('Failed to load details')),
          ]),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _markViewed() async {
    try {
      await SupabaseConfig.client.rpc('mark_document_viewed', params: {
        'p_document_id': _inv['id'],
        'p_document_type': 'invoice',
      });
    } catch (_) {
      // Silent — not critical
    }
  }

  // ── build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _inv['status'] as String? ?? 'sent';

    return Scaffold(
      backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
      body: CustomScrollView(
        slivers: [
          // ── app bar ──
          SliverAppBar(
            expandedHeight: 0,
            pinned: true,
            backgroundColor: isDark ? Brand.darkBg : Colors.white,
            foregroundColor:
                isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            elevation: 0,
            scrolledUnderElevation: 1,
            title: Text(
              _inv['invoice_number'] ?? 'Invoice',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
          ),

          // ── body ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHero(isDark, status),
                const SizedBox(height: 16),
                _buildDates(isDark, status),
                const SizedBox(height: 16),
                if (_detailLoading) _detailShimmer(isDark),
                if (!_detailLoading) ...[
                  if (_items.isNotEmpty) ...[
                    _buildItems(isDark),
                    const SizedBox(height: 16),
                  ],
                  _buildFinancials(isDark),
                  const SizedBox(height: 16),
                  if (_payments.isNotEmpty) ...[
                    _buildPaymentHistory(isDark),
                    const SizedBox(height: 16),
                  ],
                  if ((_inv['payment_instructions'] as String? ?? '')
                      .isNotEmpty) ...[
                    _buildPaymentInstructions(isDark),
                    const SizedBox(height: 16),
                  ],
                  if ((_inv['notes'] as String? ?? '').isNotEmpty)
                    _buildNotes(isDark),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── hero card ───────────────────────────────────────────────
  Widget _buildHero(bool isDark, String status) {
    final sc = _statusColor(status);
    final total = (_inv['total_amount'] as num?)?.toDouble() ?? 0;
    final paid = (_inv['amount_paid'] as num?)?.toDouble() ?? 0;
    final balance = (_inv['balance_due'] as num?)?.toDouble() ?? 0;
    final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    final pct = (progress * 100).toStringAsFixed(0);
    final showProgress = !['cancelled', 'refunded', 'draft'].contains(status);

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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: sc.withAlpha(isDark ? 70 : 50)),
      ),
      child: Column(
        children: [
          // ── status badge ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: sc.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sc.withAlpha(90)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status == 'paid'
                      ? Icons.check_circle
                      : status == 'overdue'
                          ? Icons.warning_amber_rounded
                          : Icons.receipt_long,
                  size: 16,
                  color: sc,
                ),
                const SizedBox(width: 6),
                Text(
                  _statusLabel(status),
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

          // ── total amount ──
          Text(
            _fmtCur(total),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Brand.royalBlueDark,
            ),
          ),

          // ── progress ──
          if (showProgress && total > 0) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$pct% paid',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Brand.lightGreen,
                  ),
                ),
                if (balance > 0)
                  Text(
                    'Balance: ${_fmtCur(balance)}',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: isDark ? Brand.darkBorder : Brand.borderLight,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? Brand.lightGreen : Brand.royalBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── dates card ──────────────────────────────────────────────
  Widget _buildDates(bool isDark, String status) {
    final dueDate = DateTime.tryParse(_inv['due_date']?.toString() ?? '');

    String? dueHint;
    Color? hintColor;
    if (dueDate != null &&
        !['paid', 'cancelled', 'refunded'].contains(status)) {
      final diff = dueDate.difference(DateTime.now()).inDays;
      if (diff < 0) {
        dueHint = 'Overdue by ${diff.abs()} day${diff.abs() == 1 ? '' : 's'}';
        hintColor = const Color(0xFFEF4444);
      } else if (diff == 0) {
        dueHint = 'Due today';
        hintColor = const Color(0xFFF59E0B);
      } else if (diff <= 14) {
        dueHint = 'Due in $diff day${diff == 1 ? '' : 's'}';
        hintColor = const Color(0xFFF59E0B);
      }
    }

    return _section(
      title: 'Dates',
      icon: Icons.event_outlined,
      isDark: isDark,
      child: Column(
        children: [
          _dateRow('Issued', _fmtDate(_inv['issue_date']), isDark),
          const SizedBox(height: 8),
          _dateRow('Due', _fmtDate(_inv['due_date']), isDark,
              hint: dueHint, hintColor: hintColor),
          if (_inv['paid_date'] != null) ...[
            const SizedBox(height: 8),
            _dateRow('Paid', _fmtDate(_inv['paid_date']), isDark),
          ],
        ],
      ),
    );
  }

  Widget _dateRow(String label, String value, bool isDark,
      {String? hint, Color? hintColor}) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (hintColor ?? Brand.royalBlue).withAlpha(20),
              borderRadius: BorderRadius.circular(8),
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
      ],
    );
  }

  // ── line items ──────────────────────────────────────────────
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
                // ── index ──
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Brand.royalBlue.withAlpha(isDark ? 40 : 20),
                    borderRadius: BorderRadius.circular(10),
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

                // ── desc + price ──
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

  // ── financial summary ───────────────────────────────────────
  Widget _buildFinancials(bool isDark) {
    final subtotal = (_inv['subtotal'] as num?)?.toDouble() ?? 0;
    final discAmt = (_inv['discount_amount'] as num?)?.toDouble() ?? 0;
    final taxAmt = (_inv['tax_amount'] as num?)?.toDouble() ?? 0;
    final total = (_inv['total_amount'] as num?)?.toDouble() ?? 0;
    final paid = (_inv['amount_paid'] as num?)?.toDouble() ?? 0;
    final balance = (_inv['balance_due'] as num?)?.toDouble() ?? 0;
    final taxRate = (_inv['tax_rate'] as num?)?.toDouble();
    final discType = _inv['discount_type'] as String?;
    final discVal = (_inv['discount_value'] as num?)?.toDouble();

    String discLabel = 'Discount';
    if (discType == 'percentage' && discVal != null) {
      discLabel = 'Discount (${discVal.toStringAsFixed(0)}%)';
    }

    String taxLabel = 'Tax';
    if (taxRate != null && taxRate > 0) {
      taxLabel = 'Tax (${taxRate.toStringAsFixed(0)}%)';
    }

    return _section(
      title: 'Summary',
      icon: Icons.calculate_outlined,
      isDark: isDark,
      child: Column(
        children: [
          _summaryRow('Subtotal', _fmtCur(subtotal), isDark),
          if (discAmt > 0) ...[
            const SizedBox(height: 6),
            _summaryRow(discLabel, '- ${_fmtCur(discAmt)}', isDark,
                valueColor: const Color(0xFFF59E0B)),
          ],
          if (taxAmt > 0) ...[
            const SizedBox(height: 6),
            _summaryRow(taxLabel, _fmtCur(taxAmt), isDark),
          ],
          const SizedBox(height: 10),
          Divider(
              color: isDark ? Brand.darkBorder : Brand.borderLight, height: 1),
          const SizedBox(height: 10),
          _summaryRow('Total', _fmtCur(total), isDark, bold: true, large: true),
          if (paid > 0) ...[
            const SizedBox(height: 8),
            _summaryRow('Paid', _fmtCur(paid), isDark,
                valueColor: Brand.lightGreen),
          ],
          if (balance > 0) ...[
            const SizedBox(height: 6),
            _summaryRow('Balance Due', _fmtCur(balance), isDark,
                bold: true, valueColor: const Color(0xFFEF4444)),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark,
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

  // ── payment history ─────────────────────────────────────────
  Widget _buildPaymentHistory(bool isDark) {
    return _section(
      title: 'Payment History (${_payments.length})',
      icon: Icons.history,
      isDark: isDark,
      child: Column(
        children: _payments.map((p) {
          final method = p['payment_method'] as String? ?? '';
          final verified = p['verified'] == true;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
              borderRadius: BorderRadius.circular(14),
              border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
            ),
            child: Row(
              children: [
                // ── icon ──
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Brand.lightGreen.withAlpha(isDark ? 30 : 20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _paymentIcon(method),
                    size: 20,
                    color: Brand.lightGreen,
                  ),
                ),
                const SizedBox(width: 12),

                // ── details ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['payment_number'] ?? '—',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _paymentLabel(method),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _fmtDate(p['payment_date']),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Brand.darkTextSecondary
                                  : Brand.subtleLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── amount + verified ──
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmtCur(p['amount']),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Brand.lightGreen,
                      ),
                    ),
                    if (verified)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified,
                                size: 12, color: Brand.lightGreen),
                            const SizedBox(width: 3),
                            Text(
                              'Verified',
                              style: TextStyle(
                                fontSize: 11,
                                color: Brand.lightGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── payment instructions ────────────────────────────────────
  Widget _buildPaymentInstructions(bool isDark) {
    return _section(
      title: 'Payment Instructions',
      icon: Icons.account_balance_outlined,
      isDark: isDark,
      child: Text(
        _inv['payment_instructions'] as String? ?? '',
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        ),
      ),
    );
  }

  // ── notes ───────────────────────────────────────────────────
  Widget _buildNotes(bool isDark) {
    return _section(
      title: 'Notes',
      icon: Icons.notes_rounded,
      isDark: isDark,
      child: Text(
        _inv['notes'] as String? ?? '',
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
        ),
      ),
    );
  }

  // ── detail shimmer ──────────────────────────────────────────
  Widget _detailShimmer(bool isDark) {
    return Column(
      children: List.generate(3, (_) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          height: 120,
          decoration: BoxDecoration(
            color: isDark ? Brand.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
          ),
        );
      }),
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
