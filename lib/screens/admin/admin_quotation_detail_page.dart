import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../widgets/admin/shimmer_loading.dart';
import 'admin_invoice_detail_page.dart';

// Quotation accent — matches create_quotation_page.dart
const _kQuotationPurple = StatusColors.assigned;

class AdminQuotationDetailPage extends StatefulWidget {
  final String quotationId;
  const AdminQuotationDetailPage({
    super.key,
    required this.quotationId,
  });

  @override
  State<AdminQuotationDetailPage> createState() =>
      _AdminQuotationDetailPageState();
}

class _AdminQuotationDetailPageState extends State<AdminQuotationDetailPage> {
  final _supabase = SupabaseConfig.client;
  final _fmt = NumberFormat('#,##0.00', 'en_US');
  final _dateFmt = DateFormat('MMM d, yyyy');

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  String? get _userId => _supabase.auth.currentUser?.id;

  Map<String, dynamic> get _quo =>
      _data['quotation'] as Map<String, dynamic>? ?? {};
  List get _items => _data['items'] as List? ?? [];

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  // FIX: Format raw date string helper
  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return _dateFmt.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

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
        'get_quotation_detail',
        params: {'p_quotation_id': widget.quotationId},
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
    final status = _quo['status']?.toString() ?? 'draft';

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: DsPageHeader(
        title: _quo['quotation_number']?.toString() ?? 'Quotation',
        accent: HeroAccent.navy,
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
                        if (_quo['converted_invoice_number'] != null) ...[
                          const SizedBox(height: 16),
                          _buildConvertedBanner(isDark),
                        ],
                        if ((_quo['notes'] ?? '').toString().isNotEmpty ||
                            (_quo['terms'] ?? '').toString().isNotEmpty ||
                            (_quo['internal_notes'] ?? '')
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
    final status = _quo['status']?.toString() ?? 'draft';
    final sColor = _statusColor(status);
    final total = _d(_quo['total_amount']);
    final validUntilRaw = _quo['valid_until']?.toString() ?? '';
    final issueDateRaw = _quo['issue_date']?.toString() ?? '';

    // FIX: Format dates
    final issueDateFormatted = _formatDate(issueDateRaw);
    final validUntilFormatted = _formatDate(validUntilRaw);

    final isExpired = validUntilRaw.isNotEmpty &&
        DateTime.tryParse(validUntilRaw)?.isBefore(DateTime.now()) == true &&
        !['accepted', 'converted', 'expired'].contains(status);

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
        borderRadius: BorderRadius.circular(Brand.r(20)),
        border: Border.all(color: sColor.withAlpha(50)),
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
              // FIX: Use AdminColors.warning not hardcoded Color
              if (isExpired)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AdminColors.warning.withAlpha(26),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 12,
                        color: AdminColors.warning,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Validity Expired',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.warning,
                        ),
                      ),
                    ],
                  ),
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
          const SizedBox(height: 12),
          Row(
            children: [
              // FIX: Show formatted dates not raw strings
              _heroStat('Issued', issueDateFormatted),
              const Spacer(),
              _heroStat(
                'Valid Until',
                validUntilFormatted,
                isAlert: isExpired,
              ),
            ],
          ),
          // Accepted timestamp
          if (_quo['accepted_at'] != null) ...[
            const SizedBox(height: 10),
            _timestampRow(
              icon: Icons.check_circle_rounded,
              color: AdminColors.success,
              label: 'Accepted on',
              dateStr: _quo['accepted_at'].toString(),
            ),
          ],
          // Rejected timestamp
          if (_quo['rejected_at'] != null) ...[
            const SizedBox(height: 6),
            _timestampRow(
              icon: Icons.cancel_rounded,
              color: AdminColors.error,
              label: 'Rejected on',
              dateStr: _quo['rejected_at'].toString(),
            ),
          ],
          // Sent timestamp
          if (_quo['sent_at'] != null && !['draft'].contains(status)) ...[
            const SizedBox(height: 6),
            _timestampRow(
              icon: Icons.send_rounded,
              color: _kQuotationPurple,
              label: 'Sent on',
              dateStr: _quo['sent_at'].toString(),
            ),
          ],
        ],
      ),
    );
  }

  // FIX: Extracted timestamp row — avoids repeated try/catch inline
  Widget _timestampRow({
    required IconData icon,
    required Color color,
    required String label,
    required String dateStr,
  }) {
    String formatted;
    try {
      formatted = _dateFmt.format(DateTime.parse(dateStr));
    } catch (_) {
      formatted = dateStr;
    }
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '$label $formatted',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _heroStat(
    String label,
    String value, {
    bool isAlert = false,
  }) {
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
            // FIX: AdminColors.warning not hardcoded Color
            color: isAlert ? AdminColors.warning : AdminColors.text(context),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  2. CUSTOMER
  // ═══════════════════════════════════════════════════════

  Widget _buildCustomerCard(bool isDark) {
    final address =
        '${_quo['customer_address'] ?? ''} ${_quo['customer_city'] ?? ''}'
            .trim();

    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader('Customer', Icons.person_rounded),
            const SizedBox(height: 12),
            _row('Name', _quo['customer_name']),
            _row('Company', _quo['customer_company']),
            _row('Email', _quo['customer_email']),
            _row('Phone', _quo['customer_phone']),
            if (address.isNotEmpty) _row('Address', address),
            if (_quo['ticket_number'] != null)
              _row('Ticket', _quo['ticket_number']),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(
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
                final itemType = item['item_type']?.toString() ?? '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AdminColors.primary.withAlpha(15),
                          borderRadius: BorderRadius.circular(Brand.r(10)),
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AdminColors.primary.withAlpha(12),
                                      borderRadius: BorderRadius.circular(Brand.r(4)),
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
                                  '${item['quantity'] ?? 1} × Rs. ${_fmt.format(_d(item['unit_price']))}',
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
                        'Rs. ${_fmt.format(_d(item['total_price']))}',
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
  //  4. FINANCIAL
  // ═══════════════════════════════════════════════════════

  Widget _buildFinancialCard(bool isDark) {
    final sub = _d(_quo['subtotal']);
    final discAmt = _d(_quo['discount_amount']);
    final taxAmt = _d(_quo['tax_amount']);
    final total = _d(_quo['total_amount']);
    final discType = _quo['discount_type']?.toString();
    final discVal = _d(_quo['discount_value']);
    final taxRate = _d(_quo['tax_rate']);

    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _finRow('Subtotal', sub),
            if (discAmt > 0)
              _finRow(
                'Discount'
                '${discType == 'percentage' ? ' (${discVal.toStringAsFixed(1)}%)' : ''}',
                -discAmt,
                color: AdminColors.success,
              ),
            if (taxAmt > 0)
              _finRow(
                'Tax (${taxRate.toStringAsFixed(1)}%)',
                taxAmt,
              ),
            Divider(
              color: AdminColors.divider(context),
              height: 24,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.text(context),
                  ),
                ),
                Text(
                  'Rs. ${_fmt.format(total)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.primary,
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
    double amount, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AdminColors.textSub(context),
            ),
          ),
          Text(
            // FIX: Proper Unicode minus sign
            '${amount < 0 ? '− ' : ''}Rs. ${_fmt.format(amount.abs())}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? AdminColors.text(context),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  5. CONVERTED BANNER
  // ═══════════════════════════════════════════════════════

  Widget _buildConvertedBanner(bool isDark) {
    final invNumber = _quo['converted_invoice_number']?.toString();
    final invId = _quo['converted_invoice_id']?.toString();

    // FIX: Use AdminColors.info instead of hardcoded AdminColors.info
    const bannerColor = AdminColors.info;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Brand.r(16)),
        onTap: invId != null
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminInvoiceDetailPage(invoiceId: invId),
                  ),
                )
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bannerColor.withAlpha(isDark ? 20 : 12),
            borderRadius: BorderRadius.circular(Brand.r(16)),
            border: Border.all(color: bannerColor.withAlpha(50)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bannerColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 18,
                  color: bannerColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Converted to Invoice',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: bannerColor,
                      ),
                    ),
                    if (invNumber != null)
                      Text(
                        invNumber,
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSub(context),
                        ),
                      ),
                  ],
                ),
              ),
              if (invId != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: bannerColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  6. NOTES
  // ═══════════════════════════════════════════════════════

  Widget _buildNotesCard(bool isDark) {
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader('Notes', Icons.notes_rounded),
            const SizedBox(height: 10),
            if ((_quo['notes'] ?? '').toString().isNotEmpty)
              _noteBlock('Customer Notes', _quo['notes']),
            // FIX: Show terms if present
            if ((_quo['terms'] ?? '').toString().isNotEmpty)
              _noteBlock('Terms & Conditions', _quo['terms']),
            if ((_quo['internal_notes'] ?? '').toString().isNotEmpty)
              _noteBlock(
                'Internal Notes',
                _quo['internal_notes'],
                isInternal: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _noteBlock(
    String label,
    dynamic text, {
    bool isInternal = false,
  }) {
    // FIX: Use AdminColors.warning not hardcoded Color
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
              borderRadius: BorderRadius.circular(Brand.r(8)),
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
  //  7. ACTIONS
  // ═══════════════════════════════════════════════════════

  Widget _buildActions(bool isDark, String status) {
    final canSend = status == 'draft';
    final canConvert = status == 'accepted';
    final canWithdraw = ['draft', 'sent', 'viewed'].contains(status);

    if (!canSend && !canConvert && !canWithdraw) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (canConvert)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _convertToInvoice,
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text(
                'Convert to Invoice',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(14))),
              ),
            ),
          ),
        if (canSend) ...[
          if (canConvert) const SizedBox(height: 10),
          GestureDetector(
            onTap: _sendQuotation,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [StatusColors.deepPurple, _kQuotationPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(Brand.r(14)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: _kQuotationPurple.withAlpha(89),
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
                    'Send Quotation',
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
        if (canWithdraw) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _withdrawQuotation,
              icon: const Icon(
                Icons.cancel_rounded,
                size: 18,
                color: AdminColors.error,
              ),
              label: const Text(
                'Withdraw Quotation',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AdminColors.error,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AdminColors.error.withAlpha(80)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.r(14))),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  ACTION HANDLERS
  // ═══════════════════════════════════════════════════════

  Future<void> _sendQuotation() async {
    try {
      final res = await _supabase.rpc('send_quotation', params: {
        'p_quotation_id': widget.quotationId,
        'p_admin_id': _userId,
      });
      if (!mounted) return;

      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (result['success'] == true) {
        _snack('Quotation sent!');
        await _load();
      } else {
        // FIX: Fallback — update status directly if RPC
        //      doesn't return success flag
        try {
          await _supabase.from('quotations').update({
            'status': 'sent',
            'sent_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', widget.quotationId);
          if (!mounted) return;
          _snack('Quotation sent!');
          await _load();
        } catch (_) {
          if (!mounted) return;
          _snack(
            result['error']?.toString() ?? 'Failed to send quotation',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to send quotation', isError: true);
    }
  }

  Future<void> _withdrawQuotation() async {
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.card(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(20))),
        title: Text(
          'Withdraw Quotation?',
          style: TextStyle(color: AdminColors.text(ctx)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This will mark the quotation as expired.',
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
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(10))),
            ),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    // FIX: Always dispose controller before early return
    final reason =
        reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (confirmed != true) return;
    // FIX: mounted check after dialog dismissed
    if (!mounted) return;

    try {
      final res = await _supabase.rpc('withdraw_quotation', params: {
        'p_quotation_id': widget.quotationId,
        'p_admin_id': _userId,
        'p_reason': reason,
      });
      if (!mounted) return;

      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};
      if (result['success'] == true) {
        _snack('Quotation withdrawn');
        await _load();
      } else {
        // FIX: Fallback — update status directly
        try {
          await _supabase.from('quotations').update({
            'status': 'expired',
            if (reason != null) 'rejection_reason': reason,
          }).eq('id', widget.quotationId);
          if (!mounted) return;
          _snack('Quotation withdrawn');
          await _load();
        } catch (_) {
          if (!mounted) return;
          _snack(
            result['error']?.toString() ?? 'Failed to withdraw',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to withdraw quotation', isError: true);
    }
  }

  Future<void> _convertToInvoice() async {
    final dueDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: 'SELECT INVOICE DUE DATE',
    );

    // FIX: mounted check after showDatePicker
    if (!mounted) return;
    if (dueDate == null) return;

    try {
      final res = await _supabase.rpc(
        'create_invoice_from_quotation',
        params: {
          'p_quotation_id': widget.quotationId,
          'p_admin_id': _userId,
          'p_due_date': dueDate.toIso8601String().split('T')[0],
        },
      );
      if (!mounted) return;

      final result = res is Map<String, dynamic> ? res : <String, dynamic>{};

      if (result['success'] == true) {
        final invNum = result['invoice_number']?.toString() ?? '';
        _snack(
          invNum.isNotEmpty ? 'Invoice $invNum created!' : 'Invoice created!',
        );
        await _load();
        if (!mounted) return;
        final invId = result['invoice_id']?.toString();
        if (invId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminInvoiceDetailPage(invoiceId: invId),
            ),
          );
        }
      } else {
        _snack(
          result['error']?.toString() ?? 'Failed to convert quotation',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to convert quotation', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AdminColors.card(context),
        borderRadius: BorderRadius.circular(Brand.r(18)),
        border: Border.all(color: AdminColors.border(context)),
      ),
      child: child,
    );
  }

  Widget _cardHeader(String title, IconData icon) {
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

  Widget _row(String label, dynamic value) {
    final v = value?.toString().trim() ?? '';
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
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
        borderRadius: BorderRadius.circular(Brand.r(8)),
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

  // FIX: Use AdminColors named constants + no context-aware calls
  Color _statusColor(String s) {
    switch (s) {
      case 'draft':
        return Brand.subtleLight;
      case 'sent':
        return _kQuotationPurple;
      case 'viewed':
        return StatusColors.info;
      case 'accepted':
        return AdminColors.success;
      case 'rejected':
        return AdminColors.error;
      case 'expired':
        return AdminColors.warning;
      case 'converted':
        return AdminColors.info;
      default:
        return Brand.subtleLight;
    }
  }

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
          box(180),
          box(160),
          box(120),
          box(140),
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
              'Failed to load quotation',
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
                    borderRadius: BorderRadius.circular(Brand.r(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
