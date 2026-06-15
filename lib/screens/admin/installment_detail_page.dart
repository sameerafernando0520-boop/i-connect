// lib/screens/admin/installment_detail_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../services/points_service.dart';

class InstallmentDetailPage extends StatefulWidget {
  final String planId;
  const InstallmentDetailPage({
    super.key,
    required this.planId,
  });

  @override
  State<InstallmentDetailPage> createState() => _InstallmentDetailPageState();
}

class _InstallmentDetailPageState extends State<InstallmentDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>> _payments = [];
  String _role = 'customer';

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
        'get_installment_detail',
        params: {'p_plan_id': widget.planId},
      );
      if (!mounted) return;
      if (result['success'] != true) {
        _snack(result['error'] ?? 'Access denied', err: true);
        Navigator.pop(context);
        return;
      }
      setState(() {
        _plan = Map<String, dynamic>.from(
          result['plan'] as Map,
        );
        _payments = List<Map<String, dynamic>>.from(
          result['payments'] as List,
        );
        _role = (result['role'] ?? 'customer').toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to load: $e', err: true);
      setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              err
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        // FIX: replaced Colors.red.shade600 with const color
        backgroundColor: err ? const Color(0xFFDC2626) : Brand.lightGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.r(12)),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _markPaid(Map<String, dynamic> payment) async {
    final dk = Theme.of(context).brightness == Brightness.dark;
    String method = 'cash';

    // FIX: controllers must be disposed — use local dispose
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    try {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSS) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: dk ? Brand.darkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dk ? Brand.darkBorderLight : Brand.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mark Payment #${payment['installment_number']}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: dk ? Brand.darkTextPrimary : Brand.royalBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmtCur(payment['amount'] as num),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Brand.lightGreen,
                    ),
                  ),
                  Text(
                    'Due: ${_fmtDate(payment['due_date']?.toString())}',
                    style: TextStyle(
                      fontSize: 13,
                      color: dk ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Payment method chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      'cash',
                      'bank_transfer',
                      'card',
                      'cheque',
                      'online',
                    ].map((m) {
                      final isSelected = method == m;
                      return ChoiceChip(
                        label: Text(
                          m.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? Colors.white
                                : (dk
                                    ? Brand.darkTextSecondary
                                    : const Color(0xFF64748B)),
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Brand.royalBlue,
                        backgroundColor:
                            dk ? Brand.darkBg : Brand.scaffoldLight,
                        onSelected: (_) => setSS(() => method = m),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Reference field
                  TextField(
                    controller: refCtrl,
                    style: TextStyle(
                      color:
                          dk ? Brand.darkTextPrimary : const Color(0xFF1A1A2E),
                    ),
                    decoration: InputDecoration(
                      labelText: 'Reference Number (optional)',
                      labelStyle: TextStyle(
                        color: dk ? Brand.darkTextSecondary : Brand.subtleLight,
                      ),
                      filled: true,
                      fillColor: dk ? Brand.darkBg : Brand.scaffoldLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                        borderSide: BorderSide(
                          color: dk ? Brand.darkBorder : Brand.borderLight,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                        borderSide: const BorderSide(
                          color: Brand.royalBlue,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Notes field
                  TextField(
                    controller: noteCtrl,
                    style: TextStyle(
                      color:
                          dk ? Brand.darkTextPrimary : const Color(0xFF1A1A2E),
                    ),
                    decoration: InputDecoration(
                      labelText: 'Notes (optional)',
                      labelStyle: TextStyle(
                        color: dk ? Brand.darkTextSecondary : Brand.subtleLight,
                      ),
                      filled: true,
                      fillColor: dk ? Brand.darkBg : Brand.scaffoldLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                        borderSide: BorderSide(
                          color: dk ? Brand.darkBorder : Brand.borderLight,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                        borderSide: const BorderSide(
                          color: Brand.royalBlue,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetCtx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                            side: BorderSide(
                              color: dk
                                  ? Brand.darkBorderLight
                                  : Brand.borderLight,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Brand.r(12)),
                            ),
                            foregroundColor: dk
                                ? Brand.darkTextSecondary
                                : const Color(0xFF64748B),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(sheetCtx, true),
                          icon: const Icon(
                            Icons.check_rounded,
                            size: 18,
                          ),
                          label: const Text('Confirm'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Brand.lightGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Brand.r(12)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        }),
      );

      if (confirmed != true) return;
      if (!mounted) return;

      final result = await SupabaseConfig.client.rpc(
        'mark_installment_paid',
        params: {
          'p_payment_id': payment['id'],
          'p_payment_method': method,
          'p_payment_reference': refCtrl.text.isEmpty ? null : refCtrl.text,
          'p_notes': noteCtrl.text.isEmpty ? null : noteCtrl.text,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Fire-and-forget — never block UI on points
        final customerId = _plan?['user_id'] as String?;
        final paymentId = payment['id'] as String?;
        if (customerId != null) {
          PointsService.awardTo(
            customerId,
            'installment_paid',
            30,
            'On-time installment payment',
            paymentId,
            'installment',
          );
        }
        _snack(result['message'] ?? 'Marked as paid ✅');
        _load();
      } else {
        _snack(result['error'] ?? 'Failed', err: true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', err: true);
    } finally {
      // FIX: always dispose controllers
      refCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _verifyPayment(Map<String, dynamic> payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Verify Payment'),
        content: Text(
          'Mark installment #${payment['installment_number']} as paid? This will credit the plan and notify the customer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Brand.lightGreen,
                foregroundColor: Colors.white),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      await SupabaseConfig.client.from('installment_payments').update({
        'status': 'paid',
        'verified_at': DateTime.now().toUtc().toIso8601String(),
        'verified_by': userId,
      }).eq('id', payment['id']);

      // Notify customer (best-effort)
      try {
        final planUserId = _plan?['user_id'];
        if (planUserId != null) {
          await SupabaseConfig.client.from('notifications').insert({
            'user_id': planUserId,
            'title': 'Payment verified',
            'body':
                'Your installment #${payment['installment_number']} has been verified.',
            'type': 'payment_verified',
            'related_id': widget.planId,
            'related_type': 'installment',
            'is_read': false,
          });
        }
      } catch (e) {
        debugPrint('notify customer failed: $e');
      }

      _snack('Payment verified');
      await _load();
    } catch (e) {
      _snack('Failed: $e', err: true);
    }
  }

  Future<void> _rejectPayment(Map<String, dynamic> payment) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Reject the submitted payment for installment #${payment['installment_number']}?',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (confirmed != true) return;

    try {
      // Revert to pending — leave overdue recalculation to the plan refresh
      await SupabaseConfig.client.from('installment_payments').update({
        'status': 'pending',
        'paid_date': null,
        'payment_method': null,
        'payment_reference': null,
        'submitted_by': null,
        'verified_at': null,
        'verified_by': null,
      }).eq('id', payment['id']);

      try {
        final planUserId = _plan?['user_id'];
        if (planUserId != null) {
          await SupabaseConfig.client.from('notifications').insert({
            'user_id': planUserId,
            'title': 'Payment rejected',
            'body':
                'Your submitted payment needs attention. Please re-upload the receipt.',
            'type': 'payment_rejected',
            'related_id': widget.planId,
            'related_type': 'installment',
            'is_read': false,
          });
        }
      } catch (e) {
        debugPrint('notify customer failed: $e');
      }

      _snack('Payment rejected');
      await _load();
    } catch (e) {
      _snack('Failed: $e', err: true);
    }
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final dk = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = _role == 'admin';

    return Scaffold(
      backgroundColor: dk ? Brand.darkBg : Brand.scaffoldLight,
      appBar: DsPageHeader(
        title: 'Installment Plan',
        accent: HeroAccent.navy,
      ),
      body: _isLoading
          ? _buildLoadingSkeleton(dk)
          : _plan == null
              ? _buildEmptyState(dk)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: Brand.lightGreen,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildStatusBanner(dk),
                        const SizedBox(height: 16),
                        _buildMachineCard(dk),
                        const SizedBox(height: 16),
                        _buildCustomerCard(dk),
                        const SizedBox(height: 16),
                        _buildFinancialCard(dk),
                        const SizedBox(height: 16),
                        _buildProgressCard(dk),
                        const SizedBox(height: 16),
                        _buildPaymentTimeline(dk, isAdmin),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ── Reusable card shell ──
  Widget _card(bool dk, {required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: dk ? Brand.darkCard : Brand.cardLight,
          borderRadius: BorderRadius.circular(Brand.r(20)),
          border: Border.all(
            color: dk ? Brand.darkBorder : Brand.borderLight,
          ),
        ),
        child: child,
      );

  // ── Status banner ──
  Widget _buildStatusBanner(bool dk) {
    final status = (_plan!['payment_status'] ?? 'active').toString();

    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    switch (status) {
      case 'completed':
        // FIX: replaced .withOpacity() with .withAlpha()
        // 0.15 ≈ 38 alpha, 0.1 ≈ 26 alpha
        bgColor = dk
            ? Brand.lightGreen.withAlpha(38)
            : Brand.lightGreen.withAlpha(26);
        fgColor = dk ? Brand.lightGreenBright : Brand.lightGreenDark;
        icon = Icons.celebration_rounded;
        label = 'ALL PAYMENTS COMPLETE';
        break;
      case 'defaulted':
        bgColor = dk
            ? const Color(0xFFEF4444).withAlpha(38)
            : const Color(0xFFEF4444).withAlpha(26);
        fgColor = const Color(0xFFEF4444);
        icon = Icons.warning_amber_rounded;
        label = 'DEFAULTED';
        break;
      default:
        bgColor =
            dk ? Brand.royalBlue.withAlpha(38) : Brand.royalBlue.withAlpha(26);
        fgColor = dk ? Brand.royalBlueGlow : Brand.royalBlue;
        icon = Icons.payments_rounded;
        label = 'ACTIVE PLAN';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(Brand.r(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: fgColor, size: 24),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Machine card ──
  Widget _buildMachineCard(bool dk) {
    return _card(
      dk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            dk,
            Icons.precision_manufacturing_rounded,
            'Machine',
          ),
          const SizedBox(height: 12),
          _infoRow(dk, 'Name', (_plan!['machine_name'] ?? '—').toString()),
          _infoRow(dk, 'Brand', (_plan!['machine_brand'] ?? '—').toString()),
          _infoRow(dk, 'Model', (_plan!['model_number'] ?? '—').toString()),
          _infoRow(dk, 'Serial', (_plan!['serial_number'] ?? '—').toString()),
          _infoRow(
              dk, 'Category', (_plan!['machine_category'] ?? '—').toString()),
        ],
      ),
    );
  }

  // ── Customer card ──
  Widget _buildCustomerCard(bool dk) {
    return _card(
      dk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(dk, Icons.person_rounded, 'Customer'),
          const SizedBox(height: 12),
          _infoRow(dk, 'Name', (_plan!['customer_name'] ?? '—').toString()),
          _infoRow(dk, 'Email', (_plan!['customer_email'] ?? '—').toString()),
          _infoRow(dk, 'Phone', (_plan!['customer_phone'] ?? '—').toString()),
          if (_plan!['customer_company'] != null)
            _infoRow(
              dk,
              'Company',
              _plan!['customer_company'].toString(),
            ),
        ],
      ),
    );
  }

  // ── Financial card ──
  Widget _buildFinancialCard(bool dk) {
    final interestRate = (_plan!['interest_rate'] as num?) ?? 0;
    return _card(
      dk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            dk,
            Icons.account_balance_wallet_rounded,
            'Financial Summary',
          ),
          const SizedBox(height: 16),
          _finRow(
            dk,
            'Total Price',
            _fmtCur(_plan!['total_price'] as num? ?? 0),
          ),
          _finRow(
            dk,
            'Down Payment',
            '- ${_fmtCur(_plan!['down_payment'] as num? ?? 0)}',
          ),
          Divider(
            color: dk ? Brand.darkBorder : Brand.borderLight,
          ),
          _finRow(
            dk,
            'Remaining',
            _fmtCur(_plan!['remaining_amount'] as num? ?? 0),
          ),
          if (interestRate > 0) ...[
            _finRow(
              dk,
              'Interest (${interestRate.toStringAsFixed(1)}%)',
              '+ ${_fmtCur(_plan!['interest_amount'] as num? ?? 0)}',
              highlight: true,
            ),
            Divider(
              color: dk ? Brand.darkBorder : Brand.borderLight,
            ),
          ],
          _finRow(
            dk,
            'Total Payable',
            _fmtCur(
              _plan!['total_with_interest'] as num? ?? 0,
            ),
            bold: true,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  dk ? Brand.lightGreen.withAlpha(26) : Brand.lightGreenSurface,
              borderRadius: BorderRadius.circular(Brand.r(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_plan!['num_installments']} Monthly Installments',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: dk ? Brand.lightGreenBright : Brand.lightGreenDark,
                  ),
                ),
                Text(
                  _fmtCur(
                    _plan!['installment_amount'] as num? ?? 0,
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: dk ? Brand.lightGreenBright : Brand.lightGreenDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Receipt Date: ${_fmtDate(_plan!['receipt_date']?.toString())}',
            style: TextStyle(
              fontSize: 12,
              color: dk ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress card ──
  Widget _buildProgressCard(bool dk) {
    final paid = (_plan!['paid_count'] as num?)?.toDouble() ?? 0;
    final total = (_plan!['num_installments'] as num?)?.toDouble() ?? 1;
    final totalPaid = (_plan!['total_paid'] as num?)?.toDouble() ?? 0;
    final totalPayable =
        (_plan!['total_with_interest'] as num?)?.toDouble() ?? 1;
    // FIX: explicit double division — avoids integer division bug
    final progress = total > 0 ? paid / total : 0.0;

    return _card(
      dk,
      child: Column(
        children: [
          _cardHeader(
            dk,
            Icons.trending_up_rounded,
            'Payment Progress',
          ),
          const SizedBox(height: 16),
          // Progress bar
          Stack(
            children: [
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: dk ? Brand.darkBorderLight : Brand.borderLight,
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Brand.lightGreen,
                        Brand.lightGreenBright,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${paid.toInt()} / ${total.toInt()} payments',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: dk ? Brand.darkTextPrimary : const Color(0xFF1A1A2E),
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Brand.lightGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Collected: ${_fmtCur(totalPaid)}',
                style: TextStyle(
                  fontSize: 13,
                  color: dk ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
              Text(
                'Remaining: ${_fmtCur(totalPayable - totalPaid)}',
                style: TextStyle(
                  fontSize: 13,
                  color: dk ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Payment timeline ──
  Widget _buildPaymentTimeline(bool dk, bool isAdmin) {
    return _card(
      dk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            dk,
            Icons.event_note_rounded,
            'Payment Schedule',
          ),
          const SizedBox(height: 16),
          ..._payments.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final status = (p['status'] ?? 'pending').toString();
            final isLast = i == _payments.length - 1;

            Color dotColor;
            IconData dotIcon;
            switch (status) {
              case 'paid':
                dotColor = Brand.lightGreen;
                dotIcon = Icons.check_circle_rounded;
                break;
              case 'overdue':
                dotColor = const Color(0xFFEF4444);
                dotIcon = Icons.error_rounded;
                break;
              case 'submitted':
                dotColor = const Color(0xFFF59E0B);
                dotIcon = Icons.hourglass_bottom_rounded;
                break;
              default:
                dotColor = dk ? Brand.darkBorderLight : Brand.borderLight;
                dotIcon = Icons.radio_button_unchecked_rounded;
            }

            // FIX: replaced .withOpacity() with .withAlpha()
            // 0.1 ≈ 26 alpha, 0.05 ≈ 13 alpha, 0.08 ≈ 20 alpha
            Color itemBg;
            Color itemBorder;
            switch (status) {
              case 'overdue':
                itemBg = dk
                    ? const Color(0xFFEF4444).withAlpha(26)
                    : const Color(0xFFEF4444).withAlpha(13);
                itemBorder = const Color(0xFFEF4444).withAlpha(77);
                break;
              case 'paid':
                itemBg = dk
                    ? Brand.lightGreen.withAlpha(20)
                    : Brand.lightGreen.withAlpha(13);
                itemBorder = Brand.lightGreen.withAlpha(77);
                break;
              case 'submitted':
                itemBg = const Color(0xFFF59E0B).withAlpha(20);
                itemBorder = const Color(0xFFF59E0B).withAlpha(77);
                break;
              default:
                itemBg = dk ? Brand.darkBg : Brand.scaffoldLight;
                itemBorder = dk ? Brand.darkBorder : Brand.borderLight;
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline column
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Icon(
                          dotIcon,
                          size: 20,
                          color: dotColor,
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: status == 'paid'
                                  ? Brand.lightGreen.withAlpha(102)
                                  : (dk
                                      ? Brand.darkBorderLight
                                      : Brand.borderLight),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        bottom: isLast ? 0 : 12,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: itemBg,
                        borderRadius: BorderRadius.circular(Brand.r(12)),
                        border: Border.all(
                          color: itemBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '#${p['installment_number']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: dk
                                      ? Brand.darkTextPrimary
                                      : const Color(0xFF1A1A2E),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: dotColor.withAlpha(38),
                                  borderRadius: BorderRadius.circular(Brand.r(10)),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: dotColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Due: ${_fmtDate(p['due_date']?.toString())}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: dk
                                      ? Brand.darkTextSecondary
                                      : const Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                _fmtCur(
                                  p['amount'] as num? ?? 0,
                                ),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: dk
                                      ? Brand.darkTextPrimary
                                      : const Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                          if (status == 'paid') ...[
                            const SizedBox(height: 4),
                            Text(
                              'Paid: ${_fmtDate(p['paid_date']?.toString())} • ${(p['payment_method'] ?? '').toString().replaceAll('_', ' ')}${p['payment_reference'] != null ? ' • Ref: ${p['payment_reference']}' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Brand.lightGreen,
                              ),
                            ),
                          ],
                          if (status == 'overdue') ...[
                            const SizedBox(height: 4),
                            Builder(builder: (_) {
                              try {
                                final days = DateTime.now()
                                    .difference(
                                      DateTime.parse(
                                        p['due_date'].toString(),
                                      ),
                                    )
                                    .inDays;
                                return Text(
                                  'Overdue by $days day(s)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFEF4444),
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              } catch (_) {
                                return const SizedBox.shrink();
                              }
                            }),
                          ],
                          if (status == 'submitted') ...[
                            const SizedBox(height: 8),
                            _PaymentReceiptsStrip(
                              paymentId: p['id']?.toString() ?? '',
                              isDark: dk,
                            ),
                            if (isAdmin) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _verifyPayment(p),
                                      icon: const Icon(Icons.verified_rounded,
                                          size: 16),
                                      label: const Text('Verify'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Brand.lightGreen,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _rejectPayment(p),
                                      icon: const Icon(Icons.close_rounded,
                                          size: 16),
                                      label: const Text('Reject'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFFEF4444),
                                        side: const BorderSide(
                                            color: Color(0xFFEF4444)),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                          if (isAdmin &&
                              (status == 'pending' || status == 'overdue')) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _markPaid(p),
                                icon: const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Mark as Paid',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Brand.lightGreen,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
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

  // ── Shared card header ──
  Widget _cardHeader(
    bool dk,
    IconData icon,
    String title,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: dk ? Brand.royalBlueGlow : Brand.royalBlue,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: dk ? Brand.darkTextPrimary : Brand.royalBlue,
          ),
        ),
      ],
    );
  }

  // ── Info row ──
  Widget _infoRow(bool dk, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: dk ? Brand.darkTextSecondary : Brand.subtleLight,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: dk ? Brand.darkTextPrimary : const Color(0xFF1A1A2E),
                ),
              ),
            ),
          ],
        ),
      );

  // ── Financial row ──
  Widget _finRow(
    bool dk,
    String label,
    String value, {
    bool bold = false,
    bool highlight = false,
  }) {
    // FIX: replaced Colors.amber.shade700 with const color
    const amberColor = Color(0xFFB45309); // amber-700
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: highlight
                  ? amberColor
                  : (dk ? Brand.darkTextSecondary : const Color(0xFF64748B)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: highlight
                  ? amberColor
                  : (dk ? Brand.darkTextPrimary : const Color(0xFF1A1A2E)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ──
  Widget _buildEmptyState(bool dk) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 56,
              color: dk ? Brand.darkTextTertiary : Brand.subtleLight,
            ),
            const SizedBox(height: 16),
            Text(
              'No Data Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: dk ? Brand.darkTextPrimary : const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This installment plan could not be loaded.',
              style: TextStyle(
                fontSize: 14,
                color: dk ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
              textAlign: TextAlign.center,
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

  // ── Loading skeleton ──
  Widget _buildLoadingSkeleton(bool dk) {
    final shimmer = dk ? Brand.darkCardElevated : const Color(0xFFEEF0F5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status banner
          _shimBox(dk, shimmer, height: 60, radius: 16),
          const SizedBox(height: 16),
          // Machine card
          _shimBox(dk, shimmer, height: 160, radius: 20),
          const SizedBox(height: 16),
          // Customer card
          _shimBox(dk, shimmer, height: 140, radius: 20),
          const SizedBox(height: 16),
          // Financial card
          _shimBox(dk, shimmer, height: 220, radius: 20),
          const SizedBox(height: 16),
          // Progress card
          _shimBox(dk, shimmer, height: 130, radius: 20),
          const SizedBox(height: 16),
          // Timeline
          _shimBox(dk, shimmer, height: 320, radius: 20),
        ],
      ),
    );
  }

  Widget _shimBox(
    bool dk,
    Color color, {
    required double height,
    required double radius,
  }) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: dk ? Border.all(color: Brand.darkBorder) : null,
      ),
    );
  }
}

// ─── Receipts strip for a submitted payment ─────────────────
class _PaymentReceiptsStrip extends StatefulWidget {
  final String paymentId;
  final bool isDark;
  const _PaymentReceiptsStrip({
    required this.paymentId,
    required this.isDark,
  });

  @override
  State<_PaymentReceiptsStrip> createState() => _PaymentReceiptsStripState();
}

class _PaymentReceiptsStripState extends State<_PaymentReceiptsStrip> {
  bool _loading = true;
  List<Map<String, dynamic>> _receipts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await SupabaseConfig.client
          .from('payment_receipts')
          .select('*')
          .eq('payment_id', widget.paymentId)
          .order('uploaded_at', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows);

      // Resolve signed URLs for each file
      for (final r in list) {
        final path = r['file_url']?.toString();
        if (path == null || path.isEmpty) {
          debugPrint('warning: receipt has no file_url');
          r['_error'] = 'Missing file path';
          continue;
        }
        try {
          final signed = await SupabaseConfig.client.storage
              .from('payment-receipts')
              .createSignedUrl(path, 3600);
          r['_signed'] = signed;
        } catch (e) {
          debugPrint('signed url failed for $path: $e');
          r['_error'] = 'Unable to load receipt: ${e.toString()}';
        }
      }

      if (!mounted) return;
      setState(() {
        _receipts = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('receipts load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openFullScreen(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_receipts.isEmpty) {
      return Text(
        'No receipts attached',
        style: TextStyle(
          fontSize: 12,
          color: widget.isDark ? Brand.darkTextSecondary : Brand.subtleLight,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _receipts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = _receipts[i];
          final url = r['_signed']?.toString();
          final mime = r['mime_type']?.toString() ?? '';
          final isImage = mime.startsWith('image/');
          final fallbackBg = Brand.canvas(widget.isDark);
          final error = r['_error']?.toString();

          if (url == null) {
            return Tooltip(
              message: error ?? 'Failed to load receipt',
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withAlpha(26),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withAlpha(102),
                  ),
                ),
                child: const Icon(Icons.warning_rounded,
                    size: 20, color: Color(0xFFEF4444)),
              ),
            );
          }
          if (!isImage) {
            return GestureDetector(
              onTap: () => _openFullScreen(url),
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: fallbackBg,
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                  border: Border.all(
                    color: widget.isDark ? Brand.darkBorder : Brand.borderLight,
                  ),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 26,
                  color: Color(0xFFEF4444),
                ),
              ),
            );
          }
          return GestureDetector(
            onTap: () => _openFullScreen(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Brand.r(10)),
              child: CachedNetworkImage(
                imageUrl: url,
                width: 70,
                height: 70,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 70,
                  height: 70,
                  color: fallbackBg,
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 70,
                  height: 70,
                  color: fallbackBg,
                  child: const Icon(Icons.broken_image_rounded, size: 20),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
