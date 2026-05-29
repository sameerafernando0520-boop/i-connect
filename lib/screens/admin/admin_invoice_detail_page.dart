import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/admin/shimmer_loading.dart';
import '../../widgets/admin/sheets/record_payment_sheet.dart';

class AdminInvoiceDetailPage extends StatefulWidget {
  final String invoiceId;
  const AdminInvoiceDetailPage({
    super.key,
    required this.invoiceId,
  });

  @override
  State<AdminInvoiceDetailPage> createState() => _AdminInvoiceDetailPageState();
}

class _AdminInvoiceDetailPageState extends State<AdminInvoiceDetailPage> {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0.00', 'en_US');
  final _dateFmt = DateFormat('MMM d, yyyy');

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  String? get _userId => _supabase.auth.currentUser?.id;

  Map<String, dynamic> get _inv =>
      _data['invoice'] as Map<String, dynamic>? ?? {};
  List get _items => _data['items'] as List? ?? [];
  List get _payments => _data['payments'] as List? ?? [];
  Map<String, dynamic>? get _company =>
      _data['company'] as Map<String, dynamic>?;

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  // M2: Client-side invoice status transition guard. The canonical graph is
  // also enforced by a DB trigger (see migration), but gating on the client
  // avoids a wasted round-trip and gives the admin a useful error inline.
  //
  //   draft        → sent, cancelled
  //   sent         → viewed, paid, partially_paid, overdue, cancelled
  //   viewed       → paid, partially_paid, overdue, cancelled
  //   partially_paid → paid, overdue, cancelled
  //   overdue      → paid, partially_paid, cancelled
  //   paid         → refunded
  //   cancelled    → (terminal)
  //   refunded     → (terminal)
  static const Map<String, Set<String>> _invoiceTransitions = {
    'draft': {'sent', 'cancelled'},
    'sent': {'viewed', 'paid', 'partially_paid', 'overdue', 'cancelled'},
    'viewed': {'paid', 'partially_paid', 'overdue', 'cancelled'},
    'partially_paid': {'paid', 'overdue', 'cancelled'},
    'overdue': {'paid', 'partially_paid', 'cancelled'},
    'paid': {'refunded'},
    'cancelled': {},
    'refunded': {},
  };

  bool _canTransition(String from, String to) {
    return _invoiceTransitions[from]?.contains(to) ?? false;
  }

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _supabase.rpc(
        'get_invoice_detail',
        params: {'p_invoice_id': widget.invoiceId},
      );
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
    final status = _inv['status']?.toString() ?? 'draft';

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: AppBar(
        title: Text(
          _inv['invoice_number']?.toString() ?? 'Invoice',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: isDark ? Brand.darkTextPrimary : AdminColors.text(context),
          ),
        ),
        backgroundColor: AdminColors.card(context),
        foregroundColor: AdminColors.text(context),
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _statusBadge(status),
            ),
        ],
      ),
      body: _loading
          ? _buildShimmer(isDark)
          : _error != null
              ? _buildError(isDark)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AdminColors.primary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(isDark),
                        const SizedBox(height: 16),
                        _buildCustomerCard(isDark),
                        const SizedBox(height: 16),
                        _buildItemsCard(isDark),
                        const SizedBox(height: 16),
                        _buildFinancialCard(isDark),
                        if (_payments.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildPaymentsCard(isDark),
                        ],
                        if (_company != null) ...[
                          const SizedBox(height: 16),
                          _buildBankInfo(isDark),
                        ],
                        if ((_inv['notes'] ?? '').toString().isNotEmpty ||
                            (_inv['internal_notes'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildNotesCard(isDark),
                        ],
                        const SizedBox(height: 16),
                        _buildActions(isDark, status),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  1. HERO
  // ═══════════════════════════════════════════════════════

  Widget _buildHero(bool isDark) {
    final status = _inv['status']?.toString() ?? 'draft';
    final sColor = _statusColor(status);
    final total = _d(_inv['total_amount']);
    final paid = _d(_inv['amount_paid']);
    final balance = _d(_inv['balance_due']);
    final paidPct = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;

    // FIX: Format dates properly instead of raw string display
    final issueDateRaw = _inv['issue_date']?.toString() ?? '';
    final dueDateRaw = _inv['due_date']?.toString() ?? '';
    final issueFormatted = _formatDateStr(issueDateRaw);
    final dueFormatted = _formatDateStr(dueDateRaw);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            sColor.withAlpha(isDark ? 35 : 20),
            AdminColors.card(context),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sColor.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Total Amount',
                style: TextStyle(
                  fontSize: 13,
                  color: AdminColors.textSub(context),
                ),
              ),
              const Spacer(),
              // FIX: Formatted date display
              if (issueFormatted.isNotEmpty || dueFormatted.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 11,
                      color: AdminColors.textHint(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$issueFormatted → $dueFormatted',
                      style: TextStyle(
                        fontSize: 12,
                        color: AdminColors.textHint(context),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Rs. ${_fmt.format(total)}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AdminColors.text(context),
            ),
          ),
          const SizedBox(height: 14),
          // Payment progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: paidPct,
              minHeight: 8,
              backgroundColor: AdminColors.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                paid >= total ? AdminColors.success : sColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _heroStat(
                'Paid',
                'Rs. ${_fmt.format(paid)}',
                AdminColors.success,
              ),
              const Spacer(),
              _heroStat(
                'Balance Due',
                'Rs. ${_fmt.format(balance)}',
                balance > 0 && status == 'overdue'
                    ? AdminColors.error
                    : balance > 0
                        ? AdminColors.warning
                        : AdminColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AdminColors.textHint(context),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  // FIX: Helper to format raw date string (yyyy-MM-dd) → MMM d, yyyy
  String _formatDateStr(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw);
      return _dateFmt.format(dt);
    } catch (_) {
      return raw; // fallback to raw if parse fails
    }
  }

  // ═══════════════════════════════════════════════════════
  //  2. CUSTOMER
  // ═══════════════════════════════════════════════════════

  Widget _buildCustomerCard(bool isDark) {
    final address =
        '${_inv['customer_address'] ?? ''} ${_inv['customer_city'] ?? ''}'
            .trim();

    return _card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Customer', Icons.person_rounded),
            const SizedBox(height: 12),
            _detailRow('Name', _inv['customer_name']),
            _detailRow('Company', _inv['customer_company']),
            _detailRow('Email', _inv['customer_email']),
            _detailRow('Phone', _inv['customer_phone']),
            if (address.isNotEmpty) _detailRow('Address', address),
            if (_inv['ticket_number'] != null)
              _detailRow('Ticket', _inv['ticket_number']),
            if (_inv['quotation_number'] != null)
              _detailRow('Quotation', _inv['quotation_number']),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  3. LINE ITEMS
  // ═══════════════════════════════════════════════════════

  Widget _buildItemsCard(bool isDark) {
    return _card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(
              'Items (${_items.length})',
              Icons.list_alt_rounded,
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No items',
                    style: TextStyle(
                      color: AdminColors.textHint(context),
                    ),
                  ),
                ),
              )
            else
              ..._items.asMap().entries.map((e) {
                // FIX: Safe cast instead of hard cast
                final item = e.value is Map<String, dynamic>
                    ? e.value as Map<String, dynamic>
                    : <String, dynamic>{};
                final qty = item['quantity'] ?? 1;
                final unitPrice = _d(item['unit_price']);
                final lineTotal = _d(item['total_price']);
                final itemType = item['item_type']?.toString() ?? '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Index badge
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AdminColors.primary.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${e.key + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['description']?.toString() ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AdminColors.text(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (itemType.isNotEmpty) ...[
                                  // FIX: Show item type badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AdminColors.primary.withAlpha(12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      itemType.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AdminColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  '$qty × Rs. ${_fmt.format(unitPrice)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AdminColors.textSub(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Rs. ${_fmt.format(lineTotal)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.text(context),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  4. FINANCIAL BREAKDOWN
  // ═══════════════════════════════════════════════════════

  Widget _buildFinancialCard(bool isDark) {
    final subtotal = _d(_inv['subtotal']);
    final discAmt = _d(_inv['discount_amount']);
    final taxAmt = _d(_inv['tax_amount']);
    final total = _d(_inv['total_amount']);
    final paid = _d(_inv['amount_paid']);
    final balance = _d(_inv['balance_due']);
    final discType = _inv['discount_type']?.toString();
    final discValue = _d(_inv['discount_value']);
    final taxRate = _d(_inv['tax_rate']);

    return _card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _finRow('Subtotal', subtotal, isDark),
            if (discAmt > 0)
              _finRow(
                'Discount'
                '${discType == 'percentage' ? ' (${discValue.toStringAsFixed(1)}%)' : ''}',
                -discAmt,
                isDark,
                color: AdminColors.success,
              ),
            if (taxAmt > 0)
              _finRow(
                'Tax (${taxRate.toStringAsFixed(1)}%)',
                taxAmt,
                isDark,
              ),
            Divider(
              color: AdminColors.divider(context),
              height: 24,
            ),
            _finRow('Total', total, isDark, bold: true),
            _finRow(
              'Paid',
              paid,
              isDark,
              color: AdminColors.success,
            ),
            Divider(
              color: AdminColors.divider(context),
              height: 24,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Balance Due',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color:
                        balance > 0 ? AdminColors.error : AdminColors.success,
                  ),
                ),
                Text(
                  'Rs. ${_fmt.format(balance)}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color:
                        balance > 0 ? AdminColors.error : AdminColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _finRow(
    String label,
    double amount,
    bool isDark, {
    Color? color,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: color ?? AdminColors.textSub(context),
            ),
          ),
          Text(
            // FIX: Use proper minus sign (−) for negative amounts
            '${amount < 0 ? '− ' : ''}Rs. ${_fmt.format(amount.abs())}',
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color ?? AdminColors.text(context),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  5. PAYMENTS
  // ═══════════════════════════════════════════════════════

  Widget _buildPaymentsCard(bool isDark) {
    return _card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(
              'Payments (${_payments.length})',
              Icons.payments_rounded,
            ),
            const SizedBox(height: 12),
            ..._payments.map((p) {
              // FIX: Safe cast
              final pay = p is Map<String, dynamic> ? p : <String, dynamic>{};
              final method = pay['payment_method']?.toString() ?? '';
              final verified = pay['verified'] == true;
              // FIX: Format payment date
              final payDateRaw = pay['payment_date']?.toString() ?? '';
              final payDate = _formatDateStr(payDateRaw);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdminColors.bg(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AdminColors.border(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AdminColors.success.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _methodIcon(method),
                          size: 18,
                          color: AdminColors.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pay['payment_number']?.toString() ?? '—',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AdminColors.text(context),
                              ),
                            ),
                            Text(
                              '${_methodLabel(method)}'
                              '${payDate.isNotEmpty ? ' • $payDate' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AdminColors.textSub(context),
                              ),
                            ),
                            // FIX: Show reference if present
                            if ((pay['reference'] ?? '').toString().isNotEmpty)
                              Text(
                                'Ref: ${pay['reference']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AdminColors.textHint(context),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Rs. ${_fmt.format(_d(pay['amount']))}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.success,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: verified
                                  ? AdminColors.success.withAlpha(20)
                                  : AdminColors.warning.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  verified
                                      ? Icons.verified_rounded
                                      : Icons.schedule_rounded,
                                  size: 10,
                                  color: verified
                                      ? AdminColors.success
                                      : AdminColors.warning,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  verified ? 'Verified' : 'Pending',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: verified
                                        ? AdminColors.success
                                        : AdminColors.warning,
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  6. BANK INFO
  // ═══════════════════════════════════════════════════════

  Widget _buildBankInfo(bool isDark) {
    final c = _company!;
    return _card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(
              'Payment Instructions',
              Icons.account_balance_rounded,
            ),
            const SizedBox(height: 12),
            _detailRow('Bank', c['bank_name']),
            _detailRow('Branch', c['bank_branch']),
            _detailRow('Account', c['bank_account']),
            _detailRow('Name', c['bank_acc_name']),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  7. NOTES
  // ═══════════════════════════════════════════════════════

  Widget _buildNotesCard(bool isDark) {
    return _card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Notes', Icons.notes_rounded),
            const SizedBox(height: 10),
            if ((_inv['notes'] ?? '').toString().isNotEmpty)
              _noteBlock(
                'Customer Notes',
                _inv['notes'],
                isDark,
              ),
            if ((_inv['terms'] ?? '').toString().isNotEmpty)
              _noteBlock(
                'Terms & Conditions',
                _inv['terms'],
                isDark,
              ),
            if ((_inv['internal_notes'] ?? '').toString().isNotEmpty)
              _noteBlock(
                'Internal Notes',
                _inv['internal_notes'],
                isDark,
                isInternal: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _noteBlock(
    String label,
    dynamic text,
    bool isDark, {
    bool isInternal = false,
  }) {
    // FIX: Use AdminColors.warning instead of hardcoded Color
    final labelColor =
        isInternal ? AdminColors.warning : AdminColors.textSub(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isInternal) ...[
                Icon(
                  Icons.lock_rounded,
                  size: 12,
                  color: labelColor,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isInternal
                  ? AdminColors.warning.withAlpha(10)
                  : AdminColors.bg(context),
              borderRadius: BorderRadius.circular(8),
              border: isInternal
                  ? Border.all(color: AdminColors.warning.withAlpha(40))
                  : null,
            ),
            child: Text(
              text?.toString() ?? '',
              style: TextStyle(
                fontSize: 13,
                color: AdminColors.text(context),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  8. ACTIONS
  // ═══════════════════════════════════════════════════════

  Widget _buildActions(bool isDark, String status) {
    final canSend = status == 'draft';
    final canPay = [
      'sent',
      'viewed',
      'partially_paid',
      'overdue',
    ].contains(status);
    final canCancel = !['paid', 'cancelled', 'refunded'].contains(status) &&
        _d(_inv['amount_paid']) == 0;

    if (!canSend && !canPay && !canCancel) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (canPay)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _recordPayment,
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: const Text(
                'Record Payment',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        if (canSend) ...[
          if (canPay) const SizedBox(height: 10),
          GestureDetector(
            onTap: _sendInvoice,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Brand.royalBlueDark, Brand.royalBlueLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Brand.royalBlue.withAlpha(89),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Send Invoice',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (canCancel) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cancelInvoice,
              icon: const Icon(
                Icons.cancel_rounded,
                size: 18,
                color: AdminColors.error,
              ),
              label: const Text(
                'Cancel Invoice',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AdminColors.error,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: AdminColors.error.withAlpha(80),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════════

  Future<void> _sendInvoice() async {
    // M2: Pre-flight status check. The `canSend` flag in `_buildActions` only
    // reflects the state at render time — `_data` may be stale if another
    // admin updated the invoice in the interim. Re-check against the current
    // snapshot before attempting the transition.
    final currentStatus = (_inv['status'] as String?) ?? 'draft';
    if (!_canTransition(currentStatus, 'sent')) {
      _snack(
        'Cannot send invoice in "$currentStatus" state',
        isError: true,
      );
      return;
    }

    try {
      final res = await _supabase.rpc('send_invoice', params: {
        'p_invoice_id': widget.invoiceId,
        'p_admin_id': _userId,
      });
      if (!mounted) return;

      final result = res is Map<String, dynamic> ? res : {};
      if (result['success'] == true) {
        _snack('Invoice sent successfully!');
        await _load();
      } else {
        // FIX: Fallback — update status directly if RPC
        //      doesn't return success flag. Still gated by _canTransition
        //      above so we can never write an illegal transition.
        try {
          await _supabase.from('invoices').update({
            'status': 'sent',
            'sent_at': DateTime.now().toIso8601String(),
          }).eq('id', widget.invoiceId);
          if (!mounted) return;
          _snack('Invoice sent!');
          await _load();
        } catch (_) {
          _snack(
            result['error']?.toString() ?? 'Failed to send',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to send invoice', isError: true);
    }
  }

  Future<void> _cancelInvoice() async {
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AdminColors.card(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Cancel Invoice?',
            style: TextStyle(color: AdminColors.text(ctx)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This action cannot be undone. The invoice will be marked as cancelled.',
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
                  hintText: 'Reason (optional)',
                  hintStyle: TextStyle(
                    color: AdminColors.textHint(ctx),
                  ),
                  filled: true,
                  fillColor: AdminColors.bg(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Back',
                style: TextStyle(
                  color: AdminColors.textSub(ctx),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Cancel Invoice'),
            ),
          ],
        );
      },
    );

    // FIX: Always dispose controller — regardless of confirm result
    final reason =
        reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final res = await _supabase.rpc('cancel_invoice', params: {
        'p_invoice_id': widget.invoiceId,
        'p_admin_id': _userId,
        'p_reason': reason,
      });
      if (!mounted) return;

      final result = res is Map<String, dynamic> ? res : {};
      if (result['success'] == true) {
        _snack('Invoice cancelled');
        await _load();
      } else {
        // FIX: Fallback — update status directly
        try {
          await _supabase.from('invoices').update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toIso8601String(),
            if (reason != null) 'cancellation_reason': reason,
          }).eq('id', widget.invoiceId);
          if (!mounted) return;
          _snack('Invoice cancelled');
          await _load();
        } catch (_) {
          if (!mounted) return;
          _snack(
            result['error']?.toString() ?? 'Failed to cancel',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to cancel invoice', isError: true);
    }
  }

  void _recordPayment() {
    RecordPaymentSheet.show(
      context,
      invoiceId: widget.invoiceId,
      balanceDue: _d(_inv['balance_due']),
      onPaymentRecorded: _load,
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  Widget _card({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: child,
    );
  }

  Widget _cardTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AdminColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AdminColors.text(context),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, dynamic value) {
    final v = value?.toString().trim() ?? '';
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
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

  Widget _statusBadge(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c,
        ),
      ),
    );
  }

  // FIX: Remove context-aware calls from color method —
  //      use Brand/AdminColors static consts only
  Color _statusColor(String s) {
    switch (s) {
      case 'paid':
        return AdminColors.success;
      case 'partially_paid':
        return AdminColors.info;
      case 'sent':
        return Brand.royalBlueLight;
      case 'viewed':
        return const Color(0xFF06B6D4);
      case 'overdue':
        return AdminColors.error;
      case 'draft':
        return const Color(0xFF6B7280);
      case 'cancelled':
        return const Color(0xFF6B7280);
      case 'refunded':
        return AdminColors.warning;
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'partially_paid':
        return 'Partial';
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'viewed':
        return 'Viewed';
      case 'paid':
        return 'Paid';
      case 'overdue':
        return 'Overdue';
      case 'cancelled':
        return 'Cancelled';
      case 'refunded':
        return 'Refunded';
      default:
        if (s.isEmpty) return '—';
        return s[0].toUpperCase() + s.substring(1);
    }
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
        return m.isEmpty ? 'Payment' : m;
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          box(180),
          box(160),
          box(120),
          box(140),
          box(100),
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
              'Failed to load invoice',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
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
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
