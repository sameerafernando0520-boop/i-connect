// ============================================================
// FILE: lib/screens/customer/customer_installments_page.dart
// ============================================================

import 'package:i_connect/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/customer/submit_payment_sheet.dart';
import '../admin/installment_detail_page.dart';
import '../../widgets/ds/ds_widgets.dart';

class CustomerInstallmentsPage extends StatefulWidget {
  const CustomerInstallmentsPage({super.key});

  @override
  State<CustomerInstallmentsPage> createState() =>
      _CustomerInstallmentsPageState();
}

class _CustomerInstallmentsPageState extends State<CustomerInstallmentsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _plans = [];

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
    setState(() => _isLoading = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      final result = await SupabaseConfig.client.rpc(
        'get_installment_plans',
        params: {'p_user_id_filter': userId, 'p_status_filter': null},
      );
      if (!mounted) return;
      setState(() {
        _plans = List<Map<String, dynamic>>.from(result['plans'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Installments load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = S.of(context)!;

    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      body: Column(children: [
        DsPageHeader(title: t.installmentMyInstallments),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: isDark ? Brand.darkIconActive : Brand.royalBlue,
            backgroundColor: Brand.surface(isDark),
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                    ),
                  )
                : _plans.isEmpty
                    ? _buildEmptyState(isDark, t)
                    : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _plans.length,
                    itemBuilder: (_, i) => _buildCard(isDark, t, _plans[i]),
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(bool isDark, S t) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            borderRadius: BorderRadius.circular(Brand.r(22)),
            border: isDark ? Border.all(color: Brand.darkBorder) : null,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color:
                      isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
                  borderRadius: BorderRadius.circular(Brand.r(24)),
                  border:
                      isDark ? Border.all(color: Brand.darkBorderLight) : null,
                ),
                child: Icon(
                  Icons.payments_outlined,
                  size: 38,
                  color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                t.installmentNoPlansTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                t.installmentNoPlansDescTwoLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(bool isDark, S t, Map<String, dynamic> plan) {
    final paidCount = (plan['paid_count'] as num?) ?? 0;
    final total = (plan['num_installments'] as num?) ?? 1;
    final overdueCount = (plan['overdue_count'] as num?) ?? 0;
    final progress = total > 0 ? paidCount / total : 0.0;
    final status = plan['payment_status'] ?? 'active';

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InstallmentDetailPage(planId: plan['id']),
          ),
        );
        if (mounted) _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Brand.surface(isDark),
          borderRadius: BorderRadius.circular(Brand.r(20)),
           border: isDark
           ? Border.all(color: Brand.darkBorder) : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Brand.royalBlue.withAlpha(((0.04) * 255).toInt()),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Machine name
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(Brand.r(14)),
                    border: isDark
                        ? Border.all(color: Brand.darkBorderLight)
                        : null,
                  ),
                  child: Icon(
                    Icons.precision_manufacturing_rounded,
                    color: isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['machine_name'] ?? t.installmentUnknownMachine,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      if (plan['serial_number'] != null)
                        Text(
                          t.installmentSerialLabel(plan['serial_number'].toString()),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Brand.darkTextSecondary
                                : Brand.subtleLight,
                          ),
                        ),
                    ],
                  ),
                ),
                if (status == 'completed')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Brand.lightGreen.withAlpha(30),
                      borderRadius: BorderRadius.circular(Brand.r(10)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 11,
                            color: isDark
                                ? Brand.lightGreenBright
                                : Brand.lightGreen),
                        const SizedBox(width: 4),
                        Text(
                          'PAID',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Brand.lightGreenBright
                                : Brand.lightGreen,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Monthly payment
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Brand.lightGreen.withAlpha(((0.08) * 255).toInt())
                    : Brand.lightGreenSurface,
                borderRadius: BorderRadius.circular(Brand.r(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t.installmentMonthlyPayment,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? Brand.lightGreenBright
                          : Brand.lightGreenDark,
                    ),
                  ),
                  Text(
                    _fmtCur(plan['installment_amount'] ?? 0),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Brand.lightGreenBright
                          : Brand.lightGreenDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Progress
            ClipRRect(
              borderRadius: BorderRadius.circular(Brand.r(4)),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor:
                    isDark ? Brand.darkBorderLight : Brand.borderLight,
                valueColor: AlwaysStoppedAnimation(
                    isDark ? Brand.lightGreenBright : Brand.lightGreen),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t.installmentPaymentsCount(paidCount.toInt(), total.toInt()),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                ),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Brand.lightGreenBright : Brand.lightGreen,
                  ),
                ),
              ],
            ),

            // Overdue warning
            if (overdueCount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(((isDark ? 0.1 : 0.05) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(10)),
                  border: Border.all(color: Colors.red.withAlpha(((0.2) * 255).toInt())),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(
                      t.installmentPaymentsOverdue(overdueCount.toInt()),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Next due
            if (plan['next_due_date'] != null && status != 'completed') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.event_rounded,
                      size: 14,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.installmentNextDueDetails(
                        _fmtDate(plan['next_due_date']),
                        _fmtCur(plan['next_due_amount'] ?? 0),
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 16,
                      color:
                          isDark ? Brand.darkTextTertiary : Brand.subtleLight),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => _openSubmitPayment(plan),
                  icon: const Icon(Icons.payments_rounded, size: 18),
                  label: Text(S.of(context)!.installmentPay),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Brand.royalBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
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

  Future<void> _openSubmitPayment(Map<String, dynamic> plan) async {
    final nextDueAmt =
        (plan['next_due_amount'] as num?)?.toDouble() ??
            (plan['installment_amount'] as num?)?.toDouble() ??
            0;
    final result = await SubmitPaymentSheet.show(
      context,
      planId: plan['id'].toString(),
      suggestedAmount: nextDueAmt,
      nextDueDate: plan['next_due_date']?.toString(),
      nextDueNumber: (plan['next_due_number'] as num?)?.toInt(),
    );
    if (result == true && mounted) {
      _load();
    }
  }
}
