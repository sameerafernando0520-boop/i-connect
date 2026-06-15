// ═══════════════════════════════════════════════════════════════
// FILE: lib/screens/engineering_admin/ea_ticket_chat_page.dart
// EA Ticket Chat — Full chat with [⚡ Dispatch] panel
// Renders all message_type variants including engineer_assigned
// as EngineerAssignedCard rich card.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/engineering_admin/engineer_assigned_card.dart';
import '../../widgets/common/estimate_chat_card.dart';
import '../../widgets/common/chat_message_attachments.dart';
import '../admin/create_quotation_page.dart';
import '../admin/admin_quotation_detail_page.dart';
import 'ea_assign_engineers_sheet.dart';

const Color _eaAccent = Color(0xFF16A34A);

class EaTicketChatPage extends StatefulWidget {
  final String ticketId;
  final String ticketTitle;

  const EaTicketChatPage({
    super.key,
    required this.ticketId,
    required this.ticketTitle,
  });

  @override
  State<EaTicketChatPage> createState() => _EaTicketChatPageState();
}

class _EaTicketChatPageState extends State<EaTicketChatPage> {
  // ── State ──
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _ticket;
  String? _currentUserId;

  // Pagination
  static const int _pageSize = 30;
  bool _hasMore = true;
  bool _loadingMore = false;

  // Offer countdown
  Timer? _offerCountdownTimer;
  Duration? _offerRemaining;

  // Realtime debounce
  Timer? _debounce;
  dynamic _channel;

  // Scroll + input
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _msgCtrl = TextEditingController();
  bool _sending = false;
  bool _expanded = false; // ticket info header expanded

  // Dispatch panel state
  bool _dispatchLoading = false;
  List<Map<String, dynamic>> _availableEngineers = [];

  @override
  void initState() {
    super.initState();
    _currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _channel != null
        ? SupabaseConfig.client.removeChannel(_channel)
        : null;
    _debounce?.cancel();
    _offerCountdownTimer?.cancel();
    _scrollCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        // Ticket metadata
        SupabaseConfig.client
            .from('service_tickets')
            .select('''
              id, ticket_number, subject, status, priority, assigned_to,
              offer_expires_at,
              customer:users!user_id(id, full_name, profile_photo),
              engineer:users!assigned_to(id, full_name, profile_photo, phone_number),
              machine:customer_machines(
                id,
                machine_catalog(machine_name, category)
              )
            ''')
            .eq('id', widget.ticketId)
            .maybeSingle(),

        // Messages (newest first → reversed for display)
        SupabaseConfig.client
            .from('chat_messages')
            .select(
                '*, sender:users!sender_id(id, full_name, profile_photo, role)')
            .eq('ticket_id', widget.ticketId)
            .order('created_at', ascending: false)
            .limit(_pageSize),
      ]);

      if (!mounted) return;

      final ticketData = results[0] as Map<String, dynamic>?;
      final msgs = List<Map<String, dynamic>>.from(results[1] as List);

      setState(() {
        _ticket = ticketData;
        _messages = msgs;
        _hasMore = msgs.length == _pageSize;
        _loading = false;
      });

      _startOfferCountdown(ticketData);
      _subscribeRealtime();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);

    try {
      final oldest = _messages.last['created_at'] as String;
      final rows = await SupabaseConfig.client
          .from('chat_messages')
          .select(
              '*, sender:users!sender_id(id, full_name, profile_photo, role)')
          .eq('ticket_id', widget.ticketId)
          .lt('created_at', oldest)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (!mounted) return;
      final newMsgs = List<Map<String, dynamic>>.from(rows as List);
      setState(() {
        _messages.addAll(newMsgs);
        _hasMore = newMsgs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  // ── Realtime ─────────────────────────────────────────────────

  void _subscribeRealtime() {
    _channel = SupabaseConfig.client
        .channel('ea_chat_${widget.ticketId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: widget.ticketId,
          ),
          callback: _onNewMessage,
        )
        .subscribe();
  }

  Future<void> _onNewMessage(dynamic payload) async {
    try {
      final raw = payload.newRecord as Map<String, dynamic>;
      final msgId = raw['id'];

      // Re-fetch with sender join (established pattern)
      final enriched = await SupabaseConfig.client
          .from('chat_messages')
          .select(
              '*, sender:users!sender_id(id, full_name, profile_photo, role)')
          .eq('id', msgId)
          .maybeSingle();

      if (!mounted || enriched == null) return;

      setState(() {
        final exists = _messages.any((m) => m['id'] == enriched['id']);
        if (!exists) {
          _messages.insert(0, Map<String, dynamic>.from(enriched));
        }
      });

      // If the new message is engineer_assigned, reload ticket to update header
      final msgType = enriched['message_type'] as String? ?? 'text';
      if (msgType == 'engineer_assigned') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 2), () {
          if (mounted) _reloadTicketMeta();
        });
      }
    } catch (_) {}
  }

  Future<void> _reloadTicketMeta() async {
    try {
      final updated = await SupabaseConfig.client
          .from('service_tickets')
          .select('''
            id, ticket_number, subject, status, priority, assigned_to,
            offer_expires_at,
            customer:users!user_id(id, full_name, profile_photo),
            engineer:users!assigned_to(id, full_name, profile_photo, phone_number),
            machine:customer_machines(id, machine_catalog(machine_name, category))
          ''')
          .eq('id', widget.ticketId)
          .maybeSingle();
      if (!mounted || updated == null) return;
      setState(() => _ticket = updated);
      _startOfferCountdown(updated);
    } catch (_) {}
  }

  // ── Offer countdown ────────────────────────────────────────────

  void _startOfferCountdown(Map<String, dynamic>? ticket) {
    _offerCountdownTimer?.cancel();
    final expiresAt = ticket?['offer_expires_at'] as String?;
    if (expiresAt == null) {
      setState(() => _offerRemaining = null);
      return;
    }
    final expiry = DateTime.tryParse(expiresAt)?.toLocal();
    if (expiry == null) return;

    _updateCountdown(expiry);
    _offerCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateCountdown(expiry);
    });
  }

  void _updateCountdown(DateTime expiry) {
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) {
      setState(() => _offerRemaining = Duration.zero);
      _offerCountdownTimer?.cancel();
    } else {
      setState(() => _offerRemaining = remaining);
    }
  }

  // ── Send message ──────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();

    try {
      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': _currentUserId,
        'message': text,
        'message_type': 'text',
        'sender_type': 'admin',
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(10))),
          margin: const EdgeInsets.all(12),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Dispatch ──────────────────────────────────────────────────

  void _openDispatchPanel(BuildContext context, bool isDark) async {
    setState(() => _dispatchLoading = true);
    try {
      // Call RPC to get ranked available engineers for this ticket
      final result = await SupabaseConfig.client.rpc(
        'fn_get_available_engineers',
        params: {'p_ticket_id': widget.ticketId},
      );
      if (!mounted) return;
      setState(() {
        _availableEngineers =
            List<Map<String, dynamic>>.from(result as List? ?? []);
        _dispatchLoading = false;
      });
    } catch (_) {
      // Fallback: fetch present engineers manually
      try {
        final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
        final rows = await SupabaseConfig.client
            .from('engineer_attendance')
            .select('''
              engineer_id, status, check_in_time,
              engineer:users!engineer_id(id, full_name, profile_photo, assigned_zone)
            ''')
            .eq('date', today)
            .inFilter('status', ['present', 'late', 'half_day']);

        if (!mounted) return;
        setState(() {
          _availableEngineers =
              List<Map<String, dynamic>>.from(rows as List? ?? []);
          _dispatchLoading = false;
        });
      } catch (_) {
        if (mounted) setState(() => _dispatchLoading = false);
      }
    }

    if (!mounted || !context.mounted) return;
    _showDispatchSheet(context, isDark);
  }

  void _showDispatchSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Brand.darkCard : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => _DispatchPanel(
        ticketId: widget.ticketId,
        engineers: _availableEngineers,
        isDark: isDark,
        currentUserId: _currentUserId ?? '',
        onAssigned: () {
          Navigator.pop(sheetCtx);
          _reloadTicketMeta();
        },
      ),
    );
  }

  void _onReassign(BuildContext context, bool isDark) {
    _openDispatchPanel(context, isDark);
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _ticket;
    final isAssigned = t?['assigned_to'] != null;
    final offerPending = _offerRemaining != null &&
        _offerRemaining! > Duration.zero;

    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      appBar: AppBar(
        backgroundColor: Brand.isWorkshop
            ? Brand.canvas(isDark)
            : (isDark ? Brand.darkCard : Colors.white),
        elevation: 0,
        scrolledUnderElevation: Brand.isWorkshop ? 0 : 0.5,
        surfaceTintColor: Colors.transparent,
        shape: Brand.isWorkshop
            ? Border(
                bottom: BorderSide(
                    color: Brand.cardBorder(isDark), width: 1.5))
            : null,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(
            Brand.isWorkshop
                ? Icons.arrow_back_ios_new_rounded
                : Icons.arrow_back_rounded,
            color: Brand.isWorkshop
                ? Brand.ink(isDark)
                : AdminColors.text(context),
            size: Brand.isWorkshop ? 18 : 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.ticketTitle,
                style: TextStyle(
                  color: Brand.isWorkshop
                      ? Brand.ink(isDark)
                      : AdminColors.text(context),
                  fontWeight: Brand.isWorkshop ? FontWeight.w800 : FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: Brand.isWorkshop ? -0.5 : 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (t != null)
                Text(
                  _headerSubtitle(t),
                  style: TextStyle(
                    color: Brand.isWorkshop
                        ? Brand.inkSoft(isDark)
                        : AdminColors.textSub(context),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        actions: [
          // Offer countdown chip
          if (offerPending)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AdminColors.warning.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AdminColors.warning.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_rounded,
                      size: 13, color: AdminColors.warning),
                  const SizedBox(width: 4),
                  Text(
                    _formatCountdown(_offerRemaining!),
                    style: TextStyle(
                      color: AdminColors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          // Dispatch button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _dispatchLoading
                  ? null
                  : () => _openDispatchPanel(context, isDark),
              icon: _dispatchLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _eaAccent,
                      ),
                    )
                  : const Icon(Icons.bolt_rounded,
                      size: 18, color: _eaAccent),
              label: const Text(
                'Dispatch',
                style: TextStyle(
                  color: _eaAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: _eaAccent.withAlpha(15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
        // Expanded ticket info
        bottom: _expanded && t != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(80),
                child: _ExpandedHeader(ticket: t, isDark: isDark),
              )
            : null,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _eaAccent))
          : _error != null
              ? _buildError(context)
              : Column(
                  children: [
                    // Unassigned banner
                    if (!isAssigned)
                      _UnassignedBanner(
                        isDark: isDark,
                        onDispatch: () =>
                            _openDispatchPanel(context, isDark),
                      ),
                    // Messages
                    Expanded(
                      child: _buildMessageList(context, isDark),
                    ),
                    // Input bar
                    _buildInputBar(context, isDark),
                  ],
                ),
    );
  }

  Widget _buildMessageList(BuildContext context, bool isDark) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 48, color: AdminColors.textHint(context)),
            const SizedBox(height: 8),
            Text(
              'No messages yet',
              style: TextStyle(color: AdminColors.textSub(context)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      itemCount: _messages.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _eaAccent),
            ),
          );
        }

        final msg = _messages[i];
        final nextMsg =
            i + 1 < _messages.length ? _messages[i + 1] : null;
        final prevMsg = i > 0 ? _messages[i - 1] : null;

        // Date separator
        final showDate = nextMsg == null ||
            TimeUtils.isDifferentDay(
              DateTime.parse(msg['created_at'] as String),
              DateTime.parse(nextMsg['created_at'] as String),
            );

        return Column(
          children: [
            _MessageItem(
              message: msg,
              prevMessage: prevMsg,
              isDark: isDark,
              currentUserId: _currentUserId ?? '',
              onReassign: () => _onReassign(context, isDark),
            ),
            if (showDate)
              _DateSeparator(
                date:
                    DateTime.parse(msg['created_at'] as String).toLocal(),
                isDark: isDark,
              ),
          ],
        );
      },
    );
  }

  Widget _buildInputBar(BuildContext context, bool isDark) {
    return Container(
      color: isDark ? Brand.darkCard : Colors.white,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 8
            : math.max(8, MediaQuery.of(context).padding.bottom),
      ),
      child: Row(
        children: [
          // "+" action menu — Send Estimate / Image / Assign Engineers
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded,
                color: AdminColors.textSub(context)),
            onPressed: () => _showQuickActionsSheet(context),
          ),
          // Text field
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: TextStyle(
                  color: AdminColors.text(context), fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Message as Support Team...',
                hintStyle:
                    TextStyle(color: AdminColors.textHint(context)),
                filled: true,
                fillColor:
                    isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.r(24)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Send button
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _eaAccent,
                shape: BoxShape.circle,
              ),
              child: _sending
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick actions sheet (+ button in input bar) ──────────────────────
  void _showQuickActionsSheet(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final accepted = _hasAcceptedQuotation();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCard : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            0, 12, 0, 12 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AdminColors.border(ctx),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _QuickActionRow(
              icon: Icons.request_quote_rounded,
              iconColor: const Color(0xFF8B5CF6),
              label: 'Send estimate',
              subtitle: 'Build an itemized quotation and post it in chat',
              onTap: () {
                Navigator.pop(sheetCtx);
                _sendEstimate(ctx);
              },
            ),
            _QuickActionRow(
              icon: Icons.engineering_rounded,
              iconColor: _eaAccent,
              label: 'Assign engineers',
              subtitle: accepted
                  ? 'Pick engineers + arrival time for this visit'
                  : 'Customer must approve an estimate first',
              enabled: accepted,
              onTap: () {
                Navigator.pop(sheetCtx);
                _openAssignEngineers(ctx);
              },
            ),
            _QuickActionRow(
              icon: Icons.image_outlined,
              iconColor: AdminColors.info,
              label: 'Send image',
              subtitle: 'Photo from camera or gallery',
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndSendImage(ctx);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  bool _hasAcceptedQuotation() {
    // We track this via the latest 'quote' chat message metadata.status
    for (final m in _messages) {
      if ((m['message_type'] as String?) == 'quote') {
        final md = m['metadata'] as Map<String, dynamic>?;
        if (md?['status'] == 'accepted') return true;
      }
    }
    return false;
  }

  Future<void> _sendEstimate(BuildContext ctx) async {
    final customer = _ticket?['customer'] as Map<String, dynamic>?;
    final customerId = customer?['id'] as String?;
    if (customerId == null) return;

    final created = await Navigator.of(ctx).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateQuotationPage(
          customerId: customerId,
          customerName: customer?['full_name'] as String?,
          ticketId: widget.ticketId,
        ),
      ),
    );

    if (created != true || !mounted) return;

    // Find the latest quotation for this ticket — that's the one we just made.
    final latest = await SupabaseConfig.client
        .from('quotations')
        .select('id')
        .eq('ticket_id', widget.ticketId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final qid = latest?['id'] as String?;
    if (qid == null || _currentUserId == null) return;

    await EstimateChatActions.postEstimateMessage(
      ticketId: widget.ticketId,
      quotationId: qid,
      currentUserId: _currentUserId!,
    );

    if (mounted) await _load();
  }

  Future<void> _openAssignEngineers(BuildContext ctx) async {
    final result = await EaAssignEngineersSheet.show(
      ctx,
      ticketId: widget.ticketId,
      ticket: _ticket,
      currentUserId: _currentUserId,
    );
    if (result == true && mounted) {
      await _load();
    }
  }

  Future<void> _pickAndSendImage(BuildContext context) async {
    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (file == null || !mounted) return;

    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last;
      final path =
          '${widget.ticketId}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await SupabaseConfig.client.storage
          .from('chat-attachments')
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: 'image/$ext'));

      final url = SupabaseConfig.client.storage
          .from('chat-attachments')
          .getPublicUrl(path);

      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': _currentUserId,
        'message': url,
        'message_type': 'image',
        'sender_type': 'admin',
      });
    } catch (e) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload image: $e'),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.r(10))),
          margin: const EdgeInsets.all(12),
        ),
      );
    }
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AdminColors.error),
          const SizedBox(height: 12),
          Text(_error ?? '', style: TextStyle(color: AdminColors.textSub(context))),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(backgroundColor: _eaAccent),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _headerSubtitle(Map<String, dynamic> t) {
    final customer =
        (t['customer'] as Map?)?['full_name'] as String? ?? '';
    final machine =
        ((t['machine'] as Map?)?['machine_catalog'] as Map?)?['name'] as String? ?? '';
    final priority = t['priority'] as String? ?? '';
    final parts = [
      if (customer.isNotEmpty) customer,
      if (machine.isNotEmpty) machine,
      if (priority.isNotEmpty) 'Priority: ${_capitalize(priority)}',
    ];
    return parts.join(' · ');
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _formatCountdown(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════
// Message Item
// ═══════════════════════════════════════════════════════════════

class _MessageItem extends StatelessWidget {
  final Map<String, dynamic> message;
  final Map<String, dynamic>? prevMessage;
  final bool isDark;
  final String currentUserId;
  final VoidCallback onReassign;

  const _MessageItem({
    required this.message,
    required this.prevMessage,
    required this.isDark,
    required this.currentUserId,
    required this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final msgType = message['message_type'] as String? ?? 'text';
    final sender = message['sender'] as Map?;
    final senderId = sender?['id'] as String? ?? '';
    final senderRole = sender?['role'] as String? ?? '';

    // Special full-width message types
    final metadata = message['metadata'] as Map<String, dynamic>? ?? {};
    final kind = metadata['kind'] as String?;

    if (msgType == 'engineer_assigned' ||
        kind == 'engineer_assigned' ||
        kind == 'engineer_dispatch') {
      return EngineerAssignedCard(
        metadata: metadata,
        isDark: isDark,
        onReassign: onReassign,
      );
    }

    if (msgType == 'quote') {
      // EA-side: tapping View opens the existing AdminQuotationDetailPage.
      final qid = metadata['quotation_id'] as String?;
      return EstimateChatCard(
        message: message,
        metadata: metadata,
        isDark: isDark,
        isCustomerView: false,
        onApprove: null,
        onReject: null,
        onTapDetails: qid == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AdminQuotationDetailPage(quotationId: qid),
                  ),
                ),
      );
    }

    if (msgType == 'system') {
      return _SystemCard(message: message, isDark: isDark);
    }

    // Regular bubble (text, image, file)
    final isMe = senderId == currentUserId;
    final isEngineer = senderRole == 'engineer';
    final isEA = senderRole == 'engineering_admin';

    // Label below bubble
    String? senderLabel;
    if (!isMe) {
      if (isEngineer) {
        senderLabel = sender?['full_name'] as String? ?? 'Engineer';
      } else if (isEA) {
        senderLabel = 'Support Team';
      } else if (senderRole == 'admin') {
        senderLabel = 'Support Team';
      }
    } else {
      senderLabel = 'Support Team';
    }

    return _BubbleItem(
      message: message,
      isDark: isDark,
      isMe: isMe,
      senderLabel: senderLabel,
      sender: sender,
      prevMessage: prevMessage,
    );
  }
}

class _BubbleItem extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isDark;
  final bool isMe;
  final String? senderLabel;
  final Map? sender;
  final Map<String, dynamic>? prevMessage;

  const _BubbleItem({
    required this.message,
    required this.isDark,
    required this.isMe,
    required this.senderLabel,
    required this.sender,
    required this.prevMessage,
  });

  @override
  Widget build(BuildContext context) {
    final content = (message['message'] ?? message['content']) as String? ?? '';
    final msgType = message['message_type'] as String? ?? 'text';
    final createdAt = message['created_at'] as String?;
    final photoUrl = sender?['profile_photo'] as String?;
    final senderName = sender?['full_name'] as String? ?? '';

    // Determine if avatar should show (not shown for consecutive same sender)
    final prevSenderId = (prevMessage?['sender'] as Map?)?['id'];
    final thisSenderId = (message['sender'] as Map?)?['id'];
    final showAvatar =
        !isMe && (prevSenderId != thisSenderId);

    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 48 : 8,
        right: isMe ? 8 : 48,
        bottom: 3,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sender avatar
          if (!isMe)
            SizedBox(
              width: 30,
              child: showAvatar
                  ? _Avt(photoUrl: photoUrl, name: senderName, size: 28)
                  : null,
            ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // Bubble
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.68,
                ),
                padding: msgType == 'image'
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe
                      ? _eaAccent
                      : (isDark
                          ? Brand.darkCardElevated
                          : Colors.white),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(Brand.r(16)),
                    topRight: Radius.circular(Brand.r(16)),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  border: isMe
                      ? null
                      : Border.all(
                          color: AdminColors.border(context)),
                ),
                child: (msgType == 'voice' ||
                        msgType == 'document' ||
                        msgType == 'location')
                    ? Builder(builder: (_) {
                        final atts = message['attachments'] is List
                            ? List<String>.from(
                                (message['attachments'] as List)
                                    .map((e) => e.toString()))
                            : const <String>[];
                        final meta = message['metadata'] is Map
                            ? Map<String, dynamic>.from(
                                message['metadata'] as Map)
                            : null;
                        return buildChatAttachment(
                              messageType: msgType,
                              attachments: atts,
                              metadata: meta,
                              isMe: isMe,
                              accent: _eaAccent,
                            ) ??
                            const SizedBox.shrink();
                      })
                    : msgType == 'image'
                        ? _ImageContent(url: content)
                        : Text(
                            content,
                            style: TextStyle(
                              color: isMe
                                  ? Colors.white
                                  : AdminColors.text(context),
                              fontSize: 14,
                            ),
                          ),
              ),
              // Label + time
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isMe && senderLabel != null)
                      Text(
                        senderLabel!,
                        style: TextStyle(
                          color: AdminColors.textHint(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (!isMe && senderLabel != null)
                      const SizedBox(width: 6),
                    Text(
                      _formatTime(createdAt),
                      style: TextStyle(
                        color: AdminColors.textHint(context),
                        fontSize: 11,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.done_all_rounded,
                          size: 12,
                          color: AdminColors.textHint(context)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      return TimeUtils.formatMessageTime(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }
}

// ── System card ───────────────────────────────────────────────────────────────

class _SystemCard extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isDark;

  const _SystemCard({required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final content = (message['message'] ?? message['content']) as String? ?? '';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
          borderRadius: BorderRadius.circular(Brand.r(20)),
        ),
        child: Text(
          content,
          style: TextStyle(
            color: AdminColors.textSub(context),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Image content ─────────────────────────────────────────────────────────────

class _ImageContent extends StatelessWidget {
  final String url;

  const _ImageContent({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Brand.r(14)),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 200,
          height: 200,
          color: Brand.royalBlueSurface,
          child: const Center(
              child: CircularProgressIndicator(color: _eaAccent)),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 200,
          height: 200,
          color: Brand.royalBlueSurface,
          child: const Icon(Icons.broken_image_rounded,
              size: 40, color: Brand.royalBlue),
        ),
      ),
    );
  }
}

// ── Quick action row (in the + button sheet) ─────────────────────────────────

class _QuickActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _QuickActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(38),
                  borderRadius: BorderRadius.circular(Brand.r(14)),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AdminColors.text(context),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AdminColors.textSub(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AdminColors.textHint(context)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Date separator ────────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  final bool isDark;

  const _DateSeparator({required this.date, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
          borderRadius: BorderRadius.circular(Brand.r(16)),
        ),
        child: Text(
          TimeUtils.formatDateSeparator(date),
          style: TextStyle(
            color: AdminColors.textSub(context),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Unassigned banner ─────────────────────────────────────────────────────────

class _UnassignedBanner extends StatelessWidget {
  final bool isDark;
  final VoidCallback onDispatch;

  const _UnassignedBanner(
      {required this.isDark, required this.onDispatch});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEF4444).withAlpha(isDark ? 25 : 15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Engineer has not been assigned yet',
              style: TextStyle(
                color: AdminColors.text(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onDispatch,
            style: TextButton.styleFrom(
              foregroundColor: _eaAccent,
              padding: EdgeInsets.zero,
            ),
            child: const Text(
              'Dispatch',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Expanded header ───────────────────────────────────────────────────────────

class _ExpandedHeader extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final bool isDark;

  const _ExpandedHeader({required this.ticket, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final customer =
        (ticket['customer'] as Map?)?['full_name'] as String? ?? '';
    final machine =
        ((ticket['machine'] as Map?)?['machine_catalog'] as Map?)?['name'] as String? ?? '';
    final category = ((ticket['machine'] as Map?)?['machine_catalog']
            as Map?)?['category'] as String? ??
        '';
    final status = ticket['status'] as String? ?? '';
    final priority = ticket['priority'] as String? ?? '';
    final engineer =
        (ticket['engineer'] as Map?)?['full_name'] as String? ?? 'Unassigned';

    return Container(
      color: isDark ? Brand.darkCard : Colors.white,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: AdminColors.border(context)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person_rounded,
                  size: 13, color: AdminColors.textHint(context)),
              const SizedBox(width: 4),
              Text(customer,
                  style: TextStyle(
                      color: AdminColors.textSub(context),
                      fontSize: 12)),
              const SizedBox(width: 12),
              Icon(Icons.print_rounded,
                  size: 13, color: AdminColors.textHint(context)),
              const SizedBox(width: 4),
              Text('$machine ($category)',
                  style: TextStyle(
                      color: AdminColors.textSub(context),
                      fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.engineering_rounded,
                  size: 13, color: AdminColors.textHint(context)),
              const SizedBox(width: 4),
              Text(engineer,
                  style: TextStyle(
                      color: AdminColors.textSub(context),
                      fontSize: 12)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminColors.statusColor(status).withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: AdminColors.statusColor(status),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      AdminColors.priorityColor(priority).withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  priority,
                  style: TextStyle(
                    color: AdminColors.priorityColor(priority),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small avatar ──────────────────────────────────────────────────────────────

class _Avt extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double size;

  const _Avt({required this.photoUrl, required this.name, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorWidget: (_, __, ___) => _fallback(initial),
              )
            : _fallback(initial),
      ),
    );
  }

  Widget _fallback(String i) => Container(
        color: _eaAccent.withAlpha(20),
        child: Center(
          child: Text(i,
              style: TextStyle(
                  color: _eaAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.4)),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════
// Dispatch Panel (bottom sheet content)
// ═══════════════════════════════════════════════════════════════

class _DispatchPanel extends StatefulWidget {
  final String ticketId;
  final List<Map<String, dynamic>> engineers;
  final bool isDark;
  final String currentUserId;
  final VoidCallback onAssigned;

  const _DispatchPanel({
    required this.ticketId,
    required this.engineers,
    required this.isDark,
    required this.currentUserId,
    required this.onAssigned,
  });

  @override
  State<_DispatchPanel> createState() => _DispatchPanelState();
}

class _DispatchPanelState extends State<_DispatchPanel> {
  bool _assigning = false;
  String? _assigningEngineerId;

  Future<void> _assignDirect(
      BuildContext context, Map<String, dynamic> engineerRow) async {
    // engineerRow may be a flat attendance row or an RPC result
    final engineer = engineerRow['engineer'] as Map? ?? engineerRow;
    final engineerId = engineer['id'] as String? ?? engineerRow['engineer_id'] as String? ?? '';
    final engineerName = engineer['full_name'] as String? ?? 'Engineer';

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: widget.isDark ? Brand.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(18))),
        title: Text(
          'Assign Engineer',
          style: TextStyle(
            color: AdminColors.text(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Assign $engineerName to this ticket?',
          style: TextStyle(color: AdminColors.textSub(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel',
                style: TextStyle(color: AdminColors.textSub(context))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _eaAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.r(10))),
            ),
            child: const Text('Confirm Assignment'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _assigning = true;
      _assigningEngineerId = engineerId;
    });

    try {
      // Try RPC first
      try {
        await SupabaseConfig.client.rpc('fn_dispatch_engineer', params: {
          'p_ticket_id': widget.ticketId,
          'p_engineer_id': engineerId,
          'p_mode': 'direct',
          'p_note': null,
        });
      } catch (_) {
        // Fallback: manual direct assign
        await _manualDirectAssign(engineerId, engineerName, engineer);
      }

      if (!mounted) return;
      widget.onAssigned();
    } catch (e) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Assignment failed: $e')),
            ],
          ),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.r(10))),
          margin: const EdgeInsets.all(12),
        ),
      );
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _manualDirectAssign(
      String engineerId,
      String engineerName,
      Map engineerData) async {
    final profile = await SupabaseConfig.client
        .from('users')
        .select('full_name, profile_photo, employee_id, assigned_zone')
        .eq('id', engineerId)
        .maybeSingle();

    // Update ticket
    await SupabaseConfig.client.from('service_tickets').update({
      'assigned_to': engineerId,
      'status': 'assigned',
      'dispatched_by': widget.currentUserId,
      'dispatched_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', widget.ticketId);

    // Insert engineer_assigned chat message
    await SupabaseConfig.client.from('chat_messages').insert({
      'ticket_id': widget.ticketId,
      'sender_id': widget.currentUserId,
      'message_type': 'system',
      'message': 'Engineer assigned',
      'sender_type': 'system',
      'metadata': {
        'engineer_id': engineerId,
        'engineer_name': profile?['full_name'] ?? engineerName,
        'profile_photo': profile?['profile_photo'],
        'designation': 'Field Engineer',
        'skills': [],
        'avg_rating': 0.0,
        'total_jobs': 0,
        'assigned_by_name': 'Engineering Admin',
        'assigned_at': DateTime.now().toUtc().toIso8601String(),
        'zone': profile?['assigned_zone'] ?? '',
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final engineers = widget.engineers;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AdminColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Panel header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: _eaAccent, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Dispatch Engineer',
                  style: TextStyle(
                    color: AdminColors.text(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${engineers.length} available',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Divider(color: AdminColors.divider(context)),
          // Engineer list
          Expanded(
            child: engineers.isEmpty
                ? _EmptyAvailability(isDark: isDark)
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: engineers.length + 1,
                    itemBuilder: (_, i) {
                      if (i == engineers.length) {
                        return _BroadcastTile(
                          isDark: isDark,
                          onBroadcast: () {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                              content: Text(
                                  'Broadcast offer sent to all available engineers'),
                              behavior: SnackBarBehavior.floating,
                            ));
                          },
                        );
                      }
                      final row = engineers[i];
                      return _EngineerDispatchTile(
                        engineerRow: row,
                        isDark: isDark,
                        isAssigning: _assigning &&
                            _assigningEngineerId ==
                                (row['engineer'] as Map?)?['id'],
                        onAssign: () =>
                            _assignDirect(context, row),
                        onOffer: () {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                            content:
                                Text('Job offer sent to engineer'),
                            behavior: SnackBarBehavior.floating,
                          ));
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Engineer dispatch tile ────────────────────────────────────────────────────

class _EngineerDispatchTile extends StatelessWidget {
  final Map<String, dynamic> engineerRow;
  final bool isDark;
  final bool isAssigning;
  final VoidCallback onAssign;
  final VoidCallback onOffer;

  const _EngineerDispatchTile({
    required this.engineerRow,
    required this.isDark,
    required this.isAssigning,
    required this.onAssign,
    required this.onOffer,
  });

  @override
  Widget build(BuildContext context) {
    // Support both RPC result shape and fallback attendance shape
    final engineer = engineerRow['engineer'] as Map? ?? engineerRow;
    final name = engineer['full_name'] as String? ?? 'Engineer';
    final photo = engineer['profile_photo'] as String?;
    final zone = engineer['assigned_zone'] as String? ??
        engineerRow['assigned_zone'] as String? ??
        '—';
    final score = engineerRow['dispatch_score'] as num?;
    final skillMatch = engineerRow['skill_match'] as bool? ?? false;
    final jobsToday = engineerRow['jobs_today'] as num? ?? 0;
    final avgRating = (engineerRow['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final skills = (engineerRow['skills'] as List<dynamic>?)
            ?.map((s) => s.toString())
            .toList() ??
        [];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Brand.darkCardElevated : Brand.scaffoldLight,
        borderRadius: BorderRadius.circular(Brand.r(14)),
        border: Border.all(
          color: skillMatch
              ? const Color(0xFF10B981).withAlpha(60)
              : AdminColors.border(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: skillMatch
                        ? const Color(0xFF10B981).withAlpha(100)
                        : _eaAccent.withAlpha(60),
                  ),
                ),
                child: ClipOval(
                  child: photo != null && photo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photo,
                          fit: BoxFit.cover,
                          width: 38,
                          height: 38,
                          errorWidget: (_, __, ___) =>
                              _initials(name),
                        )
                      : _initials(name),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: AdminColors.text(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded,
                            size: 11,
                            color: AdminColors.textHint(context)),
                        Text(
                          zone,
                          style: TextStyle(
                            color: AdminColors.textSub(context),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (avgRating > 0) ...[
                          const Icon(Icons.star_rounded,
                              size: 11,
                              color: Color(0xFFF59E0B)),
                          Text(
                            avgRating.toStringAsFixed(1),
                            style: TextStyle(
                              color: AdminColors.textSub(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          'Jobs today: $jobsToday',
                          style: TextStyle(
                            color: AdminColors.textSub(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Dispatch score badge
              if (score != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _scoreColor(score.toDouble()).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    score.toInt().toString(),
                    style: TextStyle(
                      color: _scoreColor(score.toDouble()),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),

          // Skills
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: skills
                  .take(3)
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Brand.royalBlue.withAlpha(15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            color: isDark
                                ? Brand.darkIconActive
                                : Brand.royalBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],

          if (!skillMatch)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFF59E0B), size: 13),
                  const SizedBox(width: 4),
                  Text(
                    'No matching skill for this machine type',
                    style: TextStyle(
                      color: AdminColors.textHint(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 10),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isAssigning ? null : onOffer,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _eaAccent,
                    side: BorderSide(
                        color: _eaAccent.withAlpha(100)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Brand.r(10))),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text(
                    'Offer Job',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: isAssigning ? null : onAssign,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _eaAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Brand.r(10))),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: isAssigning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Assign Directly',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _initials(String name) {
    final i = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: _eaAccent.withAlpha(20),
      child: Center(
        child: Text(i,
            style: const TextStyle(
                color: _eaAccent,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 80) return const Color(0xFF10B981);
    if (score >= 60) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

// ── Broadcast tile ────────────────────────────────────────────────────────────

class _BroadcastTile extends StatelessWidget {
  final bool isDark;
  final VoidCallback onBroadcast;

  const _BroadcastTile({required this.isDark, required this.onBroadcast});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onBroadcast,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _eaAccent.withAlpha(15),
          borderRadius: BorderRadius.circular(Brand.r(14)),
          border:
              Border.all(color: _eaAccent.withAlpha(60)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _eaAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(Brand.r(10)),
              ),
              child: const Icon(Icons.broadcast_on_personal_rounded,
                  color: _eaAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Broadcast to All Available Engineers',
                    style: TextStyle(
                      color: AdminColors.text(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'First to accept gets the job',
                    style: TextStyle(
                      color: AdminColors.textSub(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _eaAccent),
          ],
        ),
      ),
    );
  }
}

// ── Empty availability ────────────────────────────────────────────────────────

class _EmptyAvailability extends StatelessWidget {
  final bool isDark;

  const _EmptyAvailability({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.engineering_rounded,
                size: 48, color: AdminColors.textHint(context)),
            const SizedBox(height: 12),
            Text(
              'No engineers available today',
              style: TextStyle(
                color: AdminColors.text(context),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'All engineers are absent, on leave, or not checked in.',
              style: TextStyle(
                color: AdminColors.textSub(context),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
