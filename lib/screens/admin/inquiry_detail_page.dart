// lib/screens/admin/inquiry_detail_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/sales_stage_config.dart';
import '../../models/inquiry_detail.dart';
import '../../repositories/inquiry_detail_repository.dart';
import '../../utils/time_utils.dart';
import '../../widgets/admin/confirm_dialog.dart';
import '../../widgets/admin/inquiry/sales_pipeline.dart';
import '../../widgets/admin/inquiry/customer_info_card.dart';
import '../../widgets/admin/inquiry/machine_info_card.dart';
import '../../widgets/admin/inquiry/deal_value_card.dart';
import '../../widgets/admin/inquiry/internal_notes_card.dart';
import '../../widgets/admin/inquiry/inquiry_details_card.dart';
import '../../widgets/admin/inquiry/chat_button.dart';
import 'inquiry_chat_page.dart';
import 'create_quotation_page.dart';

class InquiryDetailPage extends StatefulWidget {
  final String inquiryId;

  const InquiryDetailPage({super.key, required this.inquiryId});

  @override
  State<InquiryDetailPage> createState() => _InquiryDetailPageState();
}

class _InquiryDetailPageState extends State<InquiryDetailPage> {
  final _repository = InquiryDetailRepository();

  InquiryDetail? _inquiry;
  bool _isLoading = true;
  String? _error;
  int _unreadMessages = 0;
  bool _hasChanges = false;

  // ═══════════════════════════════════════════════════════════
  //  THEME HELPERS — all receive isDark as param
  //  FIX: removed _isDark getter (Theme.of(context) outside build
  //       is an anti-pattern). Compute in build() and pass down.
  // ═══════════════════════════════════════════════════════════

  Color _scaffoldBg(bool isDark) =>
      // FIX: AdminColors.background doesn't exist → Brand.scaffoldLight
      isDark ? Brand.darkBg : Brand.scaffoldLight;

  Color _cardBg(bool isDark) =>
      isDark ? Brand.darkCard : Brand.cardLight;

  Color _textPrimary(bool isDark) =>
      // FIX: AdminColors.textPrimary doesn't exist
      isDark ? Brand.darkTextPrimary : Brand.royalBlueDark;

  Color _textSecondary(bool isDark) =>
      isDark ? Brand.darkTextSecondary : const Color(0xFF64748B);

  Color _textMuted(bool isDark) =>
      isDark ? Brand.darkTextTertiary : Colors.grey.shade400;

  Color _borderColor(bool isDark) =>
      isDark ? Brand.darkBorder : Brand.borderLight;

  List<BoxShadow> _softShadow(bool isDark) => isDark
      ? []
      : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  // ═══════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ═══════════════════════════════════════════════════════════
  //  DATA
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // FIX: explicit <dynamic> type on Future.wait
      final results = await Future.wait<dynamic>([
        _repository.fetchInquiry(widget.inquiryId),
        _repository.fetchUnreadCount(widget.inquiryId),
      ]);

      if (!mounted) return;
      setState(() {
        _inquiry = results[0] as InquiryDetail;
        _unreadMessages = results[1] as int;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════════════

  Future<void> _updateSalesStage(String newStage) async {
    if (_inquiry == null) return;
    final currentStage = _inquiry!.salesStage;
    if (currentStage == newStage) return;

    final stage = SalesStage.fromValue(newStage);
    if (stage.isTerminal) {
      final confirmed = await ConfirmDialog.show(
        context,
        title: 'Mark as ${stage.label}?',
        message: newStage == 'won'
            ? 'This will close the inquiry as a successful deal.'
                '${!_inquiry!.hasDealValue ? '\n\nConsider adding a deal value first.' : ''}'
            : 'This will close the inquiry as lost. You can reopen it later.',
        confirmLabel: 'Mark ${stage.label}',
        confirmColor: stage.color,
        icon: stage.icon,
      );
      if (confirmed != true || !mounted) return;
    }

    // Optimistic update — spread copy (never mutate maps directly)
    final previousInquiry = _inquiry!;
    setState(() {
      _inquiry = _inquiry!.copyWith(salesStage: newStage);
      _hasChanges = true;
    });

    try {
      await _repository.updateSalesStage(widget.inquiryId, newStage);
      if (!mounted) return;

      _showSnackBar('Stage updated to ${stage.label.toUpperCase()}');

      // System message is secondary — fire and forget
      _repository
          .addSystemMessage(
            widget.inquiryId,
            'Sales stage changed from '
            '${_formatStageLabel(currentStage)} to '
            '${_formatStageLabel(newStage)}',
          )
          .catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      // Revert only if the RPC itself failed
      setState(() => _inquiry = previousInquiry);
      _showSnackBar('Failed to update stage', isError: true);
    }
  }

  Future<void> _saveNotes(String notes) async {
    try {
      await _repository.updateNotes(widget.inquiryId, notes);
      if (!mounted) return;
      setState(() {
        _inquiry = _inquiry!.copyWith(adminNotes: notes);
        _hasChanges = true;
      });
      _showSnackBar('Notes saved');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to save notes', isError: true);
    }
  }

  Future<void> _saveDealValue(double? value) async {
    try {
      await _repository.updateDealValue(widget.inquiryId, value);
      if (!mounted) return;
      setState(() {
        if (value == null || value <= 0) {
          _inquiry = _inquiry!.copyWith(clearDealValue: true);
        } else {
          _inquiry = _inquiry!.copyWith(dealValue: value);
        }
        _hasChanges = true;
      });
      _showSnackBar('Deal value updated');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to update deal value', isError: true);
    }
  }

  Future<void> _markQuoteSent() async {
    try {
      await _repository.markQuoteSent(widget.inquiryId);
      if (!mounted) return;

      setState(() {
        _inquiry = _inquiry!.copyWith(
          salesStage: 'quoted',
          quoteSentDate: DateTime.now(),
        );
        _hasChanges = true;
      });
      _showSnackBar('Quote marked as sent');

      // System message — fire and forget
      _repository
          .addSystemMessage(
              widget.inquiryId, 'Quote sent to customer')
          .catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to update', isError: true);
    }
  }

  void _openChat() {
    if (_inquiry == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InquiryChatPage(
          ticketId: widget.inquiryId,
          ticketNumber: _inquiry!.ticketNumber,
          customerName:
              _inquiry!.customer?.fullName ?? 'Customer',
        ),
      ),
    ).then((_) {
      if (mounted) _loadAll();
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════

  String _formatStageLabel(String stage) {
    return stage.replaceAll('_', ' ').toUpperCase();
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,##0.00');
    return 'Rs. ${formatter.format(amount)}';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
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
                message,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor:
            isError ? AdminColors.error : AdminColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // FIX: compute isDark once in build, pass to all helpers
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Loading state
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _scaffoldBg(isDark),
        body: SafeArea(
            child: _buildLoadingSkeleton(isDark)),
      );
    }

    // Error state
    if (_error != null || _inquiry == null) {
      return Scaffold(
        backgroundColor: _scaffoldBg(isDark),
        body: SafeArea(child: _buildErrorState(isDark)),
      );
    }

    final inquiry = _inquiry!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: Scaffold(
        backgroundColor: _scaffoldBg(isDark),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopHeader(inquiry, isDark),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadAll,
                  color: isDark
                      ? Brand.lightGreenBright
                      : AdminColors.accent,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.fromLTRB(20, 0, 20, 30),
                    child: Column(
                      children: [
                        InquiryChatButton(
                          unreadCount: _unreadMessages,
                          onTap: _openChat,
                        ),
                        const SizedBox(height: 14),
                        SalesPipeline(
                          currentStage: inquiry.salesStage,
                          onStageChanged: _updateSalesStage,
                        ),
                        const SizedBox(height: 14),
                        // ── Create Quotation action ──
                        if (!inquiry.isTerminal)
                          _buildCreateQuotationButton(
                              inquiry, isDark),
                        if (!inquiry.isTerminal &&
                            inquiry.quoteSentDate == null &&
                            inquiry.salesStage != 'new')
                          _buildQuoteSentButton(isDark),
                        if (inquiry.customer != null) ...[
                          const SizedBox(height: 14),
                          CustomerInfoCard(
                            customer: inquiry.customer!,
                            onChatTap: _openChat,
                          ),
                        ],
                        if (inquiry.machine != null) ...[
                          const SizedBox(height: 14),
                          MachineInfoCard(
                              machine: inquiry.machine!),
                        ],
                        const SizedBox(height: 14),
                        DealValueCard(
                          initialValue: inquiry.dealValue,
                          onSave: _saveDealValue,
                        ),
                        const SizedBox(height: 14),
                        InternalNotesCard(
                          initialNotes: inquiry.adminNotes,
                          onSave: _saveNotes,
                        ),
                        const SizedBox(height: 14),
                        InquiryDetailsCard(inquiry: inquiry),
                        if (inquiry.isTerminal) ...[
                          const SizedBox(height: 14),
                          _buildTerminalBanner(inquiry, isDark),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  LOADING SKELETON
  // ═══════════════════════════════════════════════════════════

  Widget _buildLoadingSkeleton(bool isDark) {
    Widget sk(double w, double h, double r) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkCard
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(r),
            border: isDark
                ? Border.all(color: Brand.darkBorder)
                : null,
          ),
        );

    return Column(
      children: [
        // Header skeleton
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              sk(42, 42, 12),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sk(140, 18, 6),
                    const SizedBox(height: 6),
                    sk(100, 12, 4),
                  ],
                ),
              ),
              sk(42, 42, 12),
              const SizedBox(width: 8),
              sk(42, 42, 12),
            ],
          ),
        ),
        // Card skeletons
        Expanded(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            children: List.generate(5, (i) {
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                height: [80.0, 60.0, 120.0, 100.0, 140.0][i],
                decoration: BoxDecoration(
                  color: isDark
                      ? Brand.darkCard
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: isDark
                      ? Border.all(color: Brand.darkBorder)
                      : null,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  ERROR STATE
  // ═══════════════════════════════════════════════════════════

  Widget _buildErrorState(bool isDark) {
    return Column(
      children: [
        // Header with back button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _cardBg(isDark),
                    borderRadius: BorderRadius.circular(12),
                    border: isDark
                        ? Border.all(color: _borderColor(isDark))
                        : null,
                    boxShadow: _softShadow(isDark),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: isDark
                        ? Brand.darkTextSecondary
                        : AdminColors.primary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Inquiry Detail',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary(isDark),
                ),
              ),
            ],
          ),
        ),
        // Error content
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      // FIX: .withOpacity() → .withAlpha()
                      color: AdminColors.error
                          .withAlpha(isDark ? 31 : 20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 36,
                      color: AdminColors.error,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Failed to load inquiry',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ??
                        'Please check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _textSecondary(isDark),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _loadAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AdminColors.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            // Already .withAlpha() ✅
                            color: AdminColors.primary.withAlpha(77),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Retry',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TOP HEADER
  // ═══════════════════════════════════════════════════════════

  Widget _buildTopHeader(InquiryDetail inquiry, bool isDark) {
    final stage = SalesStage.fromValue(inquiry.salesStage);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context, _hasChanges),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _cardBg(isDark),
                borderRadius: BorderRadius.circular(12),
                border: isDark
                    ? Border.all(color: _borderColor(isDark))
                    : null,
                boxShadow: _softShadow(isDark),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark
                    ? Brand.darkTextSecondary
                    : AdminColors.primary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inquiry.ticketNumber,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: isDark
                        ? Brand.darkTextPrimary
                        : AdminColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        // FIX: .withOpacity() → .withAlpha()
                        color: stage.color
                            .withAlpha(isDark ? 38 : 26),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(stage.icon,
                              size: 12, color: stage.color),
                          const SizedBox(width: 4),
                          Text(
                            stage.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: stage.color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      TimeUtils.getTimeAgo(inquiry.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: _textMuted(isDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Chat icon button
          GestureDetector(
            onTap: _openChat,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                // FIX: .withOpacity() → .withAlpha()
                color: AdminColors.accent
                    .withAlpha(isDark ? 38 : 26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      Icons.chat_rounded,
                      color: isDark
                          ? Brand.lightGreenBright
                          : AdminColors.accent,
                      size: 22,
                    ),
                  ),
                  if (_unreadMessages > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AdminColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _scaffoldBg(isDark),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _unreadMessages > 9
                                ? '9+'
                                : '$_unreadMessages',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loadAll,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _cardBg(isDark),
                borderRadius: BorderRadius.circular(12),
                border: isDark
                    ? Border.all(color: _borderColor(isDark))
                    : null,
                boxShadow: _softShadow(isDark),
              ),
              child: Icon(
                Icons.refresh_rounded,
                color: isDark
                    ? Brand.darkTextSecondary
                    : AdminColors.primary,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  CREATE QUOTATION BUTTON
  // ═══════════════════════════════════════════════════════════

  Widget _buildCreateQuotationButton(
      InquiryDetail inquiry, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateQuotationPage(
              customerId: inquiry.customer?.id,
              ticketId: widget.inquiryId,
              customerName: inquiry.customer?.fullName,
              customerCompany: inquiry.customer?.companyName,
            ),
          ),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withAlpha(76),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.request_quote_rounded, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Create Quotation',
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
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  QUOTE SENT BUTTON
  // ═══════════════════════════════════════════════════════════

  Widget _buildQuoteSentButton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () async {
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Mark Quote as Sent?',
            message:
                'This will update the stage to "Quoted" and '
                'record today\'s date.',
            confirmLabel: 'Mark Sent',
            confirmColor: AdminColors.accent,
            icon: Icons.receipt_long_rounded,
          );
          if (confirmed == true && mounted) _markQuoteSent();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBg(isDark),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              // FIX: .withOpacity() → .withAlpha()
              color: AdminColors.accent
                  .withAlpha(isDark ? 77 : 51),
              width: 1.5,
            ),
            boxShadow: _softShadow(isDark),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  // FIX: .withOpacity() → .withAlpha()
                  color: AdminColors.accent
                      .withAlpha(isDark ? 38 : 26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: isDark
                      ? Brand.lightGreenBright
                      : AdminColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mark Quote as Sent',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary(isDark),
                      ),
                    ),
                    Text(
                      'Record that a quotation was sent',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.send_rounded,
                color: isDark
                    ? Brand.lightGreenBright
                    : AdminColors.accent,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TERMINAL BANNER
  // ═══════════════════════════════════════════════════════════

  Widget _buildTerminalBanner(InquiryDetail inquiry, bool isDark) {
    final isWon = inquiry.isWon;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isWon
              ? [AdminColors.accent, const Color(0xFF93A52E)]
              : [AdminColors.error, const Color(0xFFC62828)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            // FIX: .withOpacity() → .withAlpha()
            color: (isWon ? AdminColors.accent : AdminColors.error)
                .withAlpha(77),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              // FIX: .withOpacity() → .withAlpha()
              color: Colors.white.withAlpha(51),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isWon
                  ? Icons.emoji_events_rounded
                  : Icons.sentiment_dissatisfied_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWon ? 'Deal Won! 🎉' : 'Deal Lost',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isWon
                      ? (inquiry.hasDealValue
                          ? 'Value: ${_formatCurrency(inquiry.dealValue!)}'
                          : 'No deal value recorded')
                      : 'Closed on ${TimeUtils.formatDateFull(inquiry.updatedAt)}',
                  style: TextStyle(
                    fontSize: 13,
                    // FIX: .withOpacity() → .withAlpha()
                    color: Colors.white.withAlpha(204),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _updateSalesStage('negotiating'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                // FIX: .withOpacity() → .withAlpha()
                color: Colors.white.withAlpha(51),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Reopen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}