// ============================================================
// iFrontiers Connect — Support Options Hub
// Entry point for all customer support actions
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../l10n/s.dart';
import '../../utils/time_utils.dart';
import '../../widgets/common/ic_icons.dart';
import 'order_form_page.dart';
import 'my_schedule_page.dart';

class SupportOptionsHub extends StatefulWidget {
  const SupportOptionsHub({super.key});

  @override
  State<SupportOptionsHub> createState() => _SupportOptionsHubState();
}

class _SupportOptionsHubState extends State<SupportOptionsHub>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _recentTickets = [];
  List<Map<String, dynamic>> _customerMachines = [];
  bool _isLoading = true;

  late AnimationController _animCtrl;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────
  Future<void> _loadData() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final results = await Future.wait<dynamic>([
        SupabaseConfig.client
            .from('service_tickets')
            .select(
                'id, ticket_number, subject, status, priority, ticket_type, created_at')
            .eq('user_id', userId)
            .eq('is_deleted', false)
            .order('created_at', ascending: false)
            .limit(5),
        SupabaseConfig.client
            .from('customer_machines')
            .select(
                'id, serial_number, status, machine_catalog!inner(machine_name, model_number)')
            .eq('user_id', userId)
            .eq('status', 'active'),
      ]);

      if (!mounted) return;
      setState(() {
        _recentTickets = List<Map<String, dynamic>>.from(results[0] as List);
        _customerMachines = List<Map<String, dynamic>>.from(results[1] as List);
        _isLoading = false;
      });
      _animCtrl.forward();
    } catch (e) {
      debugPrint('SupportHub load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _animCtrl.forward();
    }
  }

  // ── Submit Ticket ────────────────────────────────────────
  Future<void> _submitTicket({
    required String ticketType,
    required String subject,
    required String description,
    required String priority,
    String? customerMachineId,
  }) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await SupabaseConfig.client.from('service_tickets').insert({
      'user_id': userId,
      'ticket_type': ticketType,
      'subject': subject,
      'description': description,
      'priority': priority,
      'status': 'open',
      'customer_machine_id': customerMachineId,
      'metadata': {},
    });
  }

  // ── Ticket Creation Bottom Sheet ─────────────────────────
  void _showCreateTicketSheet(String ticketType) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = S.of(context)!;
    final formKey = GlobalKey<FormState>();
    final subjectCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedMachineId;
    String priority = 'medium';
    bool isSubmitting = false;

    final isSupport = ticketType == 'support';
    final title = isSupport ? t.ticketCreateNew : t.inquiryCreateNew;
    final icon = isSupport ? Icons.build_rounded : Icons.help_outline_rounded;
    final accent = isSupport ? Brand.royalBlue : Brand.lightGreen;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.88,
              ),
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.cardLight,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Handle ──
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Brand.darkBorderLight
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // ── Header ──
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accent.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: accent, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Brand.darkTextPrimary
                                  : Brand.royalBlueDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Machine Dropdown (support only) ──
                      if (isSupport && _customerMachines.isNotEmpty) ...[
                        _sheetLabel(t.ticketSelectMachine, isDark),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration:
                              _inputDeco(isDark, t.ticketChooseMachineHint),
                          dropdownColor:
                              isDark ? Brand.darkCardElevated : Brand.cardLight,
                          style: TextStyle(
                            color:
                                isDark ? Brand.darkTextPrimary : Colors.black87,
                            fontSize: 14,
                          ),
                          items: _customerMachines.map((m) {
                            final cat =
                                m['machine_catalog'] as Map<String, dynamic>?;
                            final label =
                                '${cat?['machine_name'] ?? 'Machine'} — ${m['serial_number'] ?? 'N/A'}';
                            return DropdownMenuItem(
                              value: m['id'] as String,
                              child:
                                  Text(label, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (v) => selectedMachineId = v,
                        ),
                        const SizedBox(height: 18),
                      ],

                      // ── Subject ──
                      _sheetLabel('${t.ticketSubject} *', isDark),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: subjectCtrl,
                        style: TextStyle(
                          color:
                              isDark ? Brand.darkTextPrimary : Colors.black87,
                        ),
                        decoration: _inputDeco(isDark, t.ticketSubjectHint),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t.ticketSubjectRequired
                            : null,
                      ),
                      const SizedBox(height: 18),

                      // ── Description ──
                      _sheetLabel('${t.ticketDescription} *', isDark),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: descCtrl,
                        style: TextStyle(
                          color:
                              isDark ? Brand.darkTextPrimary : Colors.black87,
                        ),
                        decoration:
                            _inputDeco(isDark, t.ticketDescriptionHint),
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t.ticketDescriptionRequired
                            : null,
                      ),
                      const SizedBox(height: 18),

                      // ── Priority ──
                      _sheetLabel(t.labelPriority, isDark),
                      const SizedBox(height: 10),
                      Row(
                        children: ['low', 'medium', 'high', 'urgent'].map((p) {
                          final selected = priority == p;
                          final color = _priorityColor(p);
                          return Expanded(
                            child: Padding(
                              padding:
                                  EdgeInsets.only(right: p != 'urgent' ? 8 : 0),
                              child: GestureDetector(
                                onTap: () => setSheet(() => priority = p),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? color.withAlpha(((0.15) * 255).toInt())
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected
                                          ? color
                                          : (isDark
                                              ? Brand.darkBorder
                                              : Colors.grey.shade300),
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      p[0].toUpperCase() + p.substring(1),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: selected
                                            ? color
                                            : (isDark
                                                ? Brand.darkTextSecondary
                                                : Colors.grey.shade600),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 28),

                      // ── Submit ──
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setSheet(() => isSubmitting = true);

                                  try {
                                    await _submitTicket(
                                      ticketType: ticketType,
                                      subject: subjectCtrl.text.trim(),
                                      description: descCtrl.text.trim(),
                                      priority: priority,
                                      customerMachineId: selectedMachineId,
                                    );

                                    if (!sheetCtx.mounted) return;
                                    Navigator.pop(sheetCtx);

                                    if (!mounted) return;
                                    _showSuccessSnackbar(
                                      isSupport
                                          ? t.ticketCreatedSuccess
                                          : t.inquirySubmittedSuccess,
                                    );
                                    _loadData();
                                  } catch (e) {
                                    setSheet(() => isSubmitting = false);
                                    if (!sheetCtx.mounted) return;
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            const Icon(Icons.error_outline,
                                                color: Colors.white, size: 20),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                  'Failed to create ticket: $e'),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: Colors.red.shade600,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  isSupport ? t.ticketSubmit : t.inquirySubmit,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(
                          height: MediaQuery.of(sheetCtx).padding.bottom + 8),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(message),
          ],
        ),
        backgroundColor: Brand.lightGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────
  Widget _sheetLabel(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Brand.darkTextSecondary : Colors.grey.shade700,
        ),
      );

  InputDecoration _inputDeco(bool isDark, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Brand.darkTextTertiary : Colors.grey.shade400,
          fontSize: 14,
        ),
        filled: true,
        fillColor: isDark ? Brand.darkBg : Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Colors.grey.shade300,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Brand.darkBorder : Colors.grey.shade300,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Brand.royalBlueLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
      );

  Color _priorityColor(String p) {
    switch (p) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.deepOrange;
      case 'urgent':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'open':
        return Colors.blue;
      case 'assigned':
        return Colors.indigo;
      case 'in_progress':
        return Colors.orange;
      case 'waiting_customer':
        return Colors.amber.shade700;
      case 'resolved':
        return Brand.lightGreen;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = S.of(context)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: isDark ? Brand.darkBg : Brand.scaffoldLight,
        appBar: AppBar(
          title: Text(
            t.supportCenter,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
            ),
          ),
          backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
          elevation: 0,
          scrolledUnderElevation: 1,
          iconTheme: IconThemeData(
            color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
          ),
        ),
        body: RefreshIndicator(
          color: Brand.royalBlue,
          backgroundColor: isDark ? Brand.darkCard : Brand.cardLight,
          onRefresh: _loadData,
          child: _isLoading
              ? _buildShimmer(isDark)
              : FadeTransition(
                  opacity: _fadeIn,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                    children: [
                      _buildHeader(isDark),
                      const SizedBox(height: 28),
                      _buildOptionCard(
                        icon: Icons.build_rounded,
                        title: t.supportTechnical,
                        subtitle: t.supportTechnicalDesc,
                        accentColor: Brand.royalBlue,
                        isDark: isDark,
                        onTap: () => _showCreateTicketSheet('support'),
                      ),
                      _buildOptionCard(
                        icon: Icons.help_outline_rounded,
                        title: t.supportGeneralInquiry,
                        subtitle: t.supportGeneralInquiryDesc,
                        accentColor: Brand.lightGreen,
                        isDark: isDark,
                        onTap: () => _showCreateTicketSheet('inquiry'),
                      ),
                      _buildOptionCard(
                        icon: Icons.local_shipping_rounded,
                        title: t.supportPlaceOrder,
                        subtitle: t.supportPlaceOrderDesc,
                        accentColor: const Color(0xFFE65100),
                        isDark: isDark,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OrderFormPage(),
                          ),
                        ),
                      ),
                      _buildOptionCard(
                        icon: Icons.calendar_month_rounded,
                        title: t.supportMySchedules,
                        subtitle: t.supportMySchedulesDesc,
                        accentColor: const Color(0xFF14B8A6),
                        isDark: isDark,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MySchedulePage(),
                          ),
                        ),
                      ),
                      if (_recentTickets.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildRecentTickets(isDark),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ── Header ──
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  Brand.royalBlueDark,
                  const Color(0xFF0A1A3D),
                ]
              : [Brand.royalBlue, Brand.royalBlueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(((isDark ? 0.2 : 0.3) * 255).toInt()),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(((0.15) * 255).toInt()),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const IcChatGearIcon(color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context)!.supportHowCanWeHelp,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.of(context)!.supportChooseOption,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withAlpha(((0.8) * 255).toInt()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Option Card ──
  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Brand.darkBorder : Colors.grey.shade200,
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accentColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Brand.darkTextPrimary
                              : Brand.royalBlueDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(((isDark ? 0.1 : 0.06) * 255).toInt()),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: accentColor,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Recent Tickets ──
  Widget _buildRecentTickets(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              S.of(context)!.supportRecentTickets,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                S.of(context)!.commonViewAll,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Brand.royalBlueLight,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._recentTickets.map((t) => _buildRecentTicketCard(t, isDark)),
      ],
    );
  }

  Widget _buildRecentTicketCard(Map<String, dynamic> ticket, bool isDark) {
    final status = (ticket['status'] as String?) ?? 'open';
    final statusColor = _statusColor(status);
    final createdAt = ticket['created_at'] as String?;
    final timeAgo = createdAt != null
        ? TimeUtils.getTimeAgo(DateTime.parse(createdAt))
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCard : Brand.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Brand.darkBorder : Colors.grey.shade200,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // TODO: Navigate to ticket detail
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket['subject'] ?? 'No Subject',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Brand.darkTextPrimary : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${ticket['ticket_number'] ?? ''} • $timeAgo',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Brand.darkTextSecondary
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(((0.12) * 255).toInt()),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shimmer Loading ──
  Widget _buildShimmer(bool isDark) {
    final baseColor = isDark ? Brand.darkCard : Colors.grey.shade200;

    Widget shimmerBox(double w, double h, {double radius = 12}) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        shimmerBox(double.infinity, 100, radius: 22),
        const SizedBox(height: 28),
        shimmerBox(double.infinity, 90, radius: 20),
        const SizedBox(height: 14),
        shimmerBox(double.infinity, 90, radius: 20),
        const SizedBox(height: 14),
        shimmerBox(double.infinity, 90, radius: 20),
        const SizedBox(height: 14),
        shimmerBox(double.infinity, 90, radius: 20),
        const SizedBox(height: 28),
        shimmerBox(120, 20),
        const SizedBox(height: 12),
        shimmerBox(double.infinity, 70, radius: 16),
        const SizedBox(height: 10),
        shimmerBox(double.infinity, 70, radius: 16),
      ],
    );
  }
}
