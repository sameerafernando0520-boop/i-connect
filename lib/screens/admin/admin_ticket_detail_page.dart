// lib/screens/admin/admin_ticket_detail_page.dart
// ═══════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../config/supabase_config.dart';
import '../../models/ticket_detail.dart';
import '../../models/chat_message.dart';
import '../../repositories/ticket_detail_repository.dart';
import '../../services/points_service.dart';
import '../../utils/time_utils.dart';
import '../../widgets/admin/chat/message_bubble.dart';
import '../../widgets/admin/chat/quick_reply_bar.dart';
import '../../widgets/admin/chat/scroll_to_bottom_fab.dart';
import '../../widgets/admin/chat/message_input.dart';
import '../../widgets/admin/sheets/status_sheet.dart';
import '../../widgets/admin/sheets/actions_sheet.dart';
import '../../widgets/admin/admin_notes_panel.dart';
import 'create_invoice_page.dart';
import '../../utils/app_logger.dart';

class AdminTicketDetailPage extends StatefulWidget {
  final String ticketId;
  const AdminTicketDetailPage({super.key, required this.ticketId});

  @override
  State<AdminTicketDetailPage> createState() => _AdminTicketDetailPageState();
}

class _AdminTicketDetailPageState extends State<AdminTicketDetailPage>
    with WidgetsBindingObserver {
  // ─── FIELDS ──────────────────────────────────────────────
  final _repository = TicketDetailRepository();
  final _messageController = TextEditingController();
  final _chatScrollController = ScrollController();

  TicketDetail? _ticket;
  List<ChatMessage> _messages = [];

  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _isSendingMessage = false;
  final bool _showTicketInfo = true;
  bool _showQuickReplies = false;
  bool _showScrollToBottom = false;
  bool _hasChanges = false;
  bool _isInternalMode = false;

  String? _currentUserId;
  RealtimeChannel? _channel;
  Timer? _debounceTimer;


  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // ─── LIFECYCLE ───────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    _chatScrollController.addListener(_onScrollChanged);
    _loadAll();
    _setupRealtimeChat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _messageController.dispose();
    _chatScrollController.removeListener(_onScrollChanged);
    _chatScrollController.dispose();
    _cleanupRealtime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ticket != null && mounted) {
      _repository.markMessagesAsRead(widget.ticketId, _currentUserId ?? '');
    }
  }

  // ─── SCROLL ──────────────────────────────────────────────
  void _onScrollChanged() {
    if (!_chatScrollController.hasClients) return;
    final atBottom = _chatScrollController.position.pixels >=
        _chatScrollController.position.maxScrollExtent - 100;
    if (_showScrollToBottom == atBottom) {
      setState(() => _showScrollToBottom = !atBottom);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      final target = _chatScrollController.position.maxScrollExtent;
      if (animate) {
        _chatScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _chatScrollController.jumpTo(target);
      }
    });
  }

  // ─── DATA LOADING ────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _repository.fetchTicket(widget.ticketId),
        _repository.fetchMessages(widget.ticketId),
      ]);

      if (!mounted) return;

      setState(() {
        _ticket = results[0] as TicketDetail;
        _messages = results[1] as List<ChatMessage>;
        _isLoading = false;
      });

      await _repository.markMessagesAsRead(
          widget.ticketId, _currentUserId ?? '');
      if (!mounted) return;
      _scrollToBottom(animate: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  // ─── REALTIME ────────────────────────────────────────────
  void _setupRealtimeChat() {
    _channel = SupabaseConfig.client.channel('admin_chat_${widget.ticketId}');

    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'ticket_id',
        value: widget.ticketId,
      ),
      callback: (payload) async {
        try {
          if (!mounted) return;

          final raw = payload.newRecord;
          final msgId = raw['id'];
          if (msgId == null) return;

          // ── Re-fetch with sender join (BUG-6 fix) ──
          final enriched = await SupabaseConfig.client
              .from('chat_messages')
              .select(
                  '*, sender:users!sender_id(id, full_name, profile_photo, role)')
              .eq('id', msgId)
              .maybeSingle();

          if (!mounted || enriched == null) return;

          final incoming = ChatMessage.fromJson(enriched);

          setState(() {
            if (incoming.senderId == _currentUserId) {
              // Replace optimistic message if exists
              final idx = _messages.indexWhere((m) =>
                  m.id == null &&
                  m.message == incoming.message &&
                  m.status == MessageStatus.sending);
              if (idx != -1) {
                _messages[idx] = incoming;
              } else if (!_messages.any((m) => m.id == incoming.id)) {
                _messages.add(incoming);
              }
            } else {
              if (!_messages.any((m) => m.id == incoming.id)) {
                _messages.add(incoming);
              }
            }
          });

          if (incoming.senderId != _currentUserId) {
            // Debounced mark-as-read
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) {
                _repository.markMessagesAsRead(
                    widget.ticketId, _currentUserId ?? '');
              }
            });
          }

          if (!_showScrollToBottom) _scrollToBottom();
        } catch (e) {
          // Silently handle realtime errors — UI not affected
          AppLogger.debug('AdminTicketDetailPage', 'Realtime callback error: $e');
        }
      },
    );

    // ── UPDATE: propagate read-receipt changes to local list ──
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'chat_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'ticket_id',
        value: widget.ticketId,
      ),
      callback: (payload) {
        if (!mounted) return;
        try {
          final updated = payload.newRecord;
          final msgId = updated['id']?.toString();
          if (msgId == null) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == msgId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(
                isRead: updated['is_read'] == true,
                readAt: DateTime.tryParse(
                    updated['read_at']?.toString() ?? ''),
                deliveredAt: DateTime.tryParse(
                    updated['delivered_at']?.toString() ?? ''),
              );
            }
          });
        } catch (e) {
          AppLogger.debug('AdminTicketDetailPage', 'Realtime msg update error: $e');
        }
      },
    );

    _channel!.onPresenceSync((_) {});

    _channel!.subscribe((RealtimeSubscribeStatus status, [Object? error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await _channel!.track({'user_id': _currentUserId ?? 'anonymous'});
        } catch (_) {}
      }
    });
  }

  void _cleanupRealtime() {
    if (_channel != null) {
      _channel!.unsubscribe();
      SupabaseConfig.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  // ─── MESSAGING ───────────────────────────────────────────
  Future<void> _sendAttachment({
    required String messageType,
    required List<String> attachments,
    Map<String, dynamic>? metadata,
  }) async {
    if (_currentUserId == null) return;
    try {
      await _repository.sendMessage(
        ticketId: widget.ticketId,
        senderId: _currentUserId!,
        senderType: 'admin',
        message: '',
        messageType: messageType,
        attachments: attachments,
        metadata: metadata,
      );
    } catch (e) {
      if (mounted) _showSnackBar('Failed to send attachment: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUserId == null) return;

    _messageController.clear();
    setState(() => _showQuickReplies = false);

    final isInternal = _isInternalMode;

    final optimistic = ChatMessage.optimistic(
      ticketId: widget.ticketId,
      senderId: _currentUserId!,
      message: text,
      isInternal: isInternal,
    );

    setState(() {
      _messages.add(optimistic);
      _isSendingMessage = true;
    });
    _scrollToBottom();

    try {
      await _repository.sendMessage(
        ticketId: widget.ticketId,
        senderId: _currentUserId!,
        senderType: 'admin',
        message: text,
        isInternal: isInternal,
      );
      if (!mounted) return;
      setState(() => _isSendingMessage = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexOf(optimistic);
        if (idx != -1) {
          _messages[idx] = optimistic.copyWith(status: MessageStatus.failed);
        }
        _isSendingMessage = false;
      });
      _showSnackBar('Failed to send message', isError: true);
    }
  }

  Future<void> _retryMessage(ChatMessage failed) async {
    setState(() => _messages.remove(failed));

    final retry = ChatMessage.optimistic(
      ticketId: widget.ticketId,
      senderId: _currentUserId!,
      message: failed.message,
      isInternal: failed.isInternal,
    );

    setState(() {
      _messages.add(retry);
      _isSendingMessage = true;
    });

    try {
      await _repository.sendMessage(
        ticketId: widget.ticketId,
        senderId: _currentUserId!,
        senderType: 'admin',
        message: failed.message,
        isInternal: failed.isInternal,
      );
      if (!mounted) return;
      setState(() => _isSendingMessage = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexOf(retry);
        if (idx != -1) {
          _messages[idx] = retry.copyWith(status: MessageStatus.failed);
        }
        _isSendingMessage = false;
      });
      _showSnackBar('Failed to retry message', isError: true);
    }
  }

  // ─── TICKET ACTIONS ──────────────────────────────────────
  Future<void> _updateStatus(String newStatus) async {
    if (_ticket == null) return;
    final old = _ticket!.status;
    setState(() {
      _ticket = _ticket!.copyWith(status: newStatus);
      _hasChanges = true;
    });

    try {
      await _repository.updateStatus(widget.ticketId, newStatus);
      if (!mounted) return;

      // System log message is best-effort: a failed insert (e.g. RLS on
      // sender_type='system') must NOT roll back the visible status change.
      try {
        await _repository.addSystemMessage(
          widget.ticketId,
          'Status changed from ${_formatLabel(old)} to ${_formatLabel(newStatus)}',
        );
      } catch (e) {
        AppLogger.debug('AdminTicketDetailPage', 'addSystemMessage failed (non-fatal): $e');
      }

      if (!mounted) return;
      _showSnackBar('Status updated to ${_formatLabel(newStatus)}');

      // ── Award resolution points to customer ──
      if (newStatus == 'resolved' || newStatus == 'closed') {
        final customerId = _ticket?.customer?.id;
        if (customerId != null) {
          PointsService.awardTo(
            customerId,
            'ticket_resolved',
            50,
            'Service ticket resolved',
            widget.ticketId,
            'ticket',
          );
        }
      }
    } catch (e) {
      AppLogger.debug('AdminTicketDetailPage', 'updateStatus failed: $e');
      if (!mounted) return;
      setState(() => _ticket = _ticket!.copyWith(status: old));
      _showSnackBar('Failed to update status', isError: true);
    }
  }

  Future<void> _updatePriority(String newPriority) async {
    if (_ticket == null) return;
    final old = _ticket!.priority;
    setState(() {
      _ticket = _ticket!.copyWith(priority: newPriority);
      _hasChanges = true;
    });

    try {
      await _repository.updatePriority(widget.ticketId, newPriority);
      if (!mounted) return;
      try {
        await _repository.addSystemMessage(
          widget.ticketId,
          'Priority changed from ${_formatLabel(old)} to ${_formatLabel(newPriority)}',
        );
      } catch (e) {
        AppLogger.debug('AdminTicketDetailPage', 'addSystemMessage failed (non-fatal): $e');
      }
      if (!mounted) return;
      _showSnackBar('Priority updated to ${_formatLabel(newPriority)}');
    } catch (e) {
      AppLogger.debug('AdminTicketDetailPage', 'updatePriority failed: $e');
      if (!mounted) return;
      setState(() => _ticket = _ticket!.copyWith(priority: old));
      _showSnackBar('Failed to update priority', isError: true);
    }
  }

  Future<void> _updateAdminNotes(String notes) async {
    try {
      await _repository.updateAdminNotes(widget.ticketId, notes);
      if (!mounted) return;
      setState(() {
        _ticket = _ticket!.copyWith(adminNotes: notes);
        _hasChanges = true;
      });
      _showSnackBar('Notes saved');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to save notes', isError: true);
    }
  }

  Future<void> _assignEngineer() async {
    try {
      final engineers = await _repository.fetchEngineers();
      if (!mounted) return;

      if (engineers.isEmpty) {
        _showSnackBar('No engineers available', isError: true);
        return;
      }
      _showAssignSheet(engineers);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to load engineers', isError: true);
    }
  }

  void _showAssignSheet(List<Map<String, dynamic>> engineers) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final dark = Theme.of(sheetCtx).brightness == Brightness.dark;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.6,
          ),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AdminColors.card(sheetCtx),
            borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.r(28))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AdminColors.border(sheetCtx),
                  borderRadius: BorderRadius.circular(Brand.r(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Assign Engineer',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AdminColors.text(sheetCtx),
                ),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: engineers.length,
                  itemBuilder: (listCtx, index) {
                    final eng = engineers[index];
                    final isAssigned = _ticket!.assignedTo == eng['id'];
                    final avail =
                        eng['availability_status'] as String? ?? 'available';
                    final availColor = avail == 'available'
                        ? AdminColors.success
                        : avail == 'busy'
                            ? AdminColors.warning
                            : AdminColors.textHint(sheetCtx);

                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(sheetCtx);
                        try {
                          await _repository.assignEngineer(
                              widget.ticketId, eng['id'] as String);
                          if (!mounted) return;
                          await _repository.addSystemMessage(
                            widget.ticketId,
                            'Ticket assigned to ${eng['full_name']}',
                          );
                          if (!mounted) return;
                          setState(() {
                            _ticket = _ticket!.copyWith(
                              assignedTo: eng['id'] as String,
                              status: _ticket!.status == 'open'
                                  ? 'assigned'
                                  : _ticket!.status,
                              engineer: TicketUser(
                                id: eng['id'] as String,
                                fullName:
                                    eng['full_name'] as String? ?? 'Engineer',
                                email: eng['email'] as String?,
                                phoneNumber: eng['phone_number'] as String?,
                                role: 'engineer',
                                availabilityStatus: avail,
                              ),
                            );
                            _hasChanges = true;
                          });
                          _showSnackBar('Assigned to ${eng['full_name']}');
                        } catch (e) {
                          if (!mounted) return;
                          _showSnackBar('Assignment failed', isError: true);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isAssigned
                              ? AdminColors.accent.withAlpha(dark ? 30 : 15)
                              : AdminColors.bg(sheetCtx),
                          borderRadius: BorderRadius.circular(Brand.r(14)),
                          border: Border.all(
                            color: isAssigned
                                ? AdminColors.accent.withAlpha(80)
                                : AdminColors.border(sheetCtx),
                          ),
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AdminColors.primary.withAlpha(20),
                                    borderRadius: BorderRadius.circular(Brand.r(12)),
                                  ),
                                  child: const Icon(
                                    Icons.engineering_rounded,
                                    color: AdminColors.primary,
                                    size: 20,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: availColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AdminColors.card(sheetCtx),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    eng['full_name'] as String? ?? 'Engineer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AdminColors.text(sheetCtx),
                                    ),
                                  ),
                                  Text(
                                    eng['email'] as String? ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AdminColors.textSub(sheetCtx),
                                    ),
                                  ),
                                  if (eng['specializations'] != null &&
                                      (eng['specializations'] as List)
                                          .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Wrap(
                                        spacing: 4,
                                        children: (eng['specializations']
                                                as List)
                                            .take(3)
                                            .map(
                                              (s) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AdminColors.primary
                                                      .withAlpha(15),
                                                  borderRadius:
                                                      BorderRadius.circular(Brand.r(4)),
                                                ),
                                                child: Text(
                                                  s.toString(),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AdminColors.primary,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isAssigned)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AdminColors.accent,
                                  borderRadius: BorderRadius.circular(Brand.r(8)),
                                ),
                                child: const Text(
                                  'Assigned',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // ─── UTILITIES ───────────────────────────────────────────
  String _formatLabel(String v) => v.replaceAll('_', ' ').toUpperCase();

  void _showSnackBar(String message, {bool isError = false}) {
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
                message,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : AdminColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(12))),
        duration: Duration(seconds: isError ? 4 : 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ─── BUILD ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildErrorState();
    if (_isLoading || _ticket == null) return _buildLoadingState();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_hasChanges);
      },
      child: Scaffold(
        backgroundColor: AdminColors.bg(context),
        appBar: DsPageHeader(
          title: _ticket?.ticketNumber ?? 'Ticket',
          subtitle: _ticket?.subject,
          accent: HeroAccent.navy,
          onBack: () => Navigator.of(context).pop(_hasChanges),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: _showActionsSheet,
              tooltip: 'Actions',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_showTicketInfo) _buildTicketInfoPanel(),
              if (_showTicketInfo)
                AdminNotesPanel(
                  initialNotes: _ticket!.adminNotes,
                  onSave: _updateAdminNotes,
                ),
              if (_showQuickReplies)
                QuickReplyBar(
                  replies: _repository.getQuickReplies(),
                  onSelect: (msg) {
                    _messageController.text = msg;
                    setState(() => _showQuickReplies = false);
                  },
                  onClose: () => setState(() => _showQuickReplies = false),
                ),
              Expanded(
                child: RefreshIndicator(
                  color: AdminColors.primary,
                  onRefresh: _loadAll,
                  child: Stack(
                    children: [
                      _messages.isEmpty
                          ? _buildEmptyChat()
                          : ListView.builder(
                              controller: _chatScrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 10, 20, 10),
                              itemCount: _messages.length,
                              itemBuilder: (_, i) {
                                final msg = _messages[i];
                                final showDate = i == 0 ||
                                    TimeUtils.isDifferentDay(
                                      _messages[i - 1].createdAt,
                                      msg.createdAt,
                                    );
                                return MessageBubble(
                                  message: msg,
                                  showDateSeparator: showDate,
                                  isSelf: msg.senderId == _currentUserId,
                                  onRetry: msg.status == MessageStatus.failed
                                      ? () => _retryMessage(msg)
                                      : null,
                                );
                              },
                            ),
                      if (_showScrollToBottom)
                        ScrollToBottomFab(onTap: () => _scrollToBottom()),
                    ],
                  ),
                ),
              ),
              MessageInput(
                controller: _messageController,
                isSending: _isSendingMessage,
                isInternal: _isInternalMode,
                ticketId: widget.ticketId,
                onSendAttachment: _sendAttachment,
                onSend: _sendMessage,
                onToggleInternal: () =>
                    setState(() => _isInternalMode = !_isInternalMode),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ERROR STATE ─────────────────────────────────────────
  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildIconButton(
                    Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AdminColors.error.withAlpha(20),
                          borderRadius: BorderRadius.circular(Brand.r(24)),
                        ),
                        child: const Icon(
                          Icons.error_outline_rounded,
                          size: 40,
                          color: AdminColors.error,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Failed to load ticket',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AdminColors.text(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage ?? 'An unexpected error occurred',
                        style: TextStyle(
                          fontSize: 13,
                          color: AdminColors.textSub(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadAll,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Brand.r(12)),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── LOADING STATE ───────────────────────────────────────
  Widget _buildLoadingState() {
    return Scaffold(
      backgroundColor: AdminColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Back button available during load
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildIconButton(
                    Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(Brand.r(18)),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AdminColors.primary,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading ticket...',
                      style: TextStyle(
                        fontSize: 14,
                        color: AdminColors.textSub(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon, {
    VoidCallback? onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isActive
              ? AdminColors.primary.withAlpha(_isDark ? 40 : 25)
              : AdminColors.bg(context),
          borderRadius: BorderRadius.circular(Brand.r(10)),
        ),
        child: Icon(
          icon,
          color: _isDark
              ? AdminColors.primary.withAlpha(200)
              : AdminColors.primary,
          size: 18,
        ),
      ),
    );
  }

  // ─── TICKET INFO PANEL ───────────────────────────────────
  Widget _buildTicketInfoPanel() {
    final ticket = _ticket!;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Container(
        color: AdminColors.card(context),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          children: [
            Divider(color: AdminColors.divider(context), height: 1),
            const SizedBox(height: 12),
            if (ticket.customer != null) _buildCustomerRow(ticket.customer!),
            if (ticket.machine != null) _buildMachineRow(ticket.machine!),
            if (ticket.engineer != null) _buildEngineerRow(ticket.engineer!),
            if (ticket.description != null &&
                ticket.description!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdminColors.bg(context),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                child: Text(
                  ticket.description!,
                  style: TextStyle(
                    fontSize: 13,
                    color: AdminColors.textSub(context),
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (ticket.orderDetails != null)
              _buildOrderMetadata(ticket.orderDetails!),
            if (ticket.escalated) _buildEscalationBanner(ticket),
            if (!ticket.isClosed) ...[
              const SizedBox(height: 10),
              _buildSlaIndicator(ticket),
            ],
          ],
        ),
      ),
    );
  }

  // ── Customer Row ──
  Widget _buildCustomerRow(TicketUser customer) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AdminColors.primary.withAlpha(20),
                AdminColors.accent.withAlpha(20),
              ],
            ),
            borderRadius: BorderRadius.circular(Brand.r(12)),
          ),
          child: Center(
            child: Text(
              customer.initials,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AdminColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.fullName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.text(context),
                ),
              ),
              if (customer.companyName != null)
                Text(
                  customer.companyName!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AdminColors.textSub(context),
                  ),
                ),
            ],
          ),
        ),
        if (customer.phoneNumber != null)
          _buildContactButton(
            Icons.phone_rounded,
            AdminColors.accent,
            () => _launchPhone(customer.phoneNumber!),
          ),
        const SizedBox(width: 6),
        if (customer.email != null)
          _buildContactButton(
            Icons.email_rounded,
            AdminColors.primary,
            () => _launchEmail(customer.email!),
          ),
      ],
    );
  }

  // ── Machine Row ──
  Widget _buildMachineRow(TicketMachine machine) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AdminColors.bg(context),
          borderRadius: BorderRadius.circular(Brand.r(12)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AdminColors.card(context),
                borderRadius: BorderRadius.circular(Brand.r(8)),
              ),
              child: machine.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(Brand.r(8)),
                      child: CachedNetworkImage(
                        imageUrl: machine.imageUrl!,
                        fit: BoxFit.cover,
                        width: 36,
                        height: 36,
                        placeholder: (_, __) => const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.precision_manufacturing_rounded,
                            color: AdminColors.primary,
                            size: 18,
                          ),
                        ),
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.precision_manufacturing_rounded,
                          color: AdminColors.primary,
                          size: 18,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.precision_manufacturing_rounded,
                      color: AdminColors.primary,
                      size: 18,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    machine.machineName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.text(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'S/N: ${machine.serialNumber ?? 'N/A'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textSub(context),
                    ),
                  ),
                ],
              ),
            ),
            if (machine.brand != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AdminColors.primary.withAlpha(15),
                  borderRadius: BorderRadius.circular(Brand.r(4)),
                ),
                child: Text(
                  machine.brand!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Engineer Row ──
  Widget _buildEngineerRow(TicketUser engineer) {
    final avail = engineer.availabilityStatus ?? 'available';
    final availColor = avail == 'available'
        ? AdminColors.success
        : avail == 'busy'
            ? AdminColors.warning
            : AdminColors.textHint(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AdminColors.bg(context),
          borderRadius: BorderRadius.circular(Brand.r(12)),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AdminColors.info.withAlpha(20),
                    borderRadius: BorderRadius.circular(Brand.r(8)),
                  ),
                  child: const Icon(
                    Icons.engineering_rounded,
                    size: 18,
                    color: AdminColors.info,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: availColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AdminColors.bg(context),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    engineer.fullName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.text(context),
                    ),
                  ),
                  Text(
                    'Assigned Engineer',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textSub(context),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: availColor.withAlpha(20),
                borderRadius: BorderRadius.circular(Brand.r(10)),
              ),
              child: Text(
                avail.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: availColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Order Metadata ──
  Widget _buildOrderMetadata(Map<String, dynamic> order) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminColors.accent.withAlpha(_isDark ? 20 : 12),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: Border.all(color: AdminColors.accent.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shopping_cart_rounded,
                  size: 16, color: AdminColors.accent),
              SizedBox(width: 6),
              Text(
                'Order Details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AdminColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _orderRow('Machine', order['machine_name']?.toString()),
          _orderRow('Quantity', '${order['quantity'] ?? 1}'),
          _orderRow('Company', order['company_name']?.toString()),
          _orderRow('Contact', order['contact_number']?.toString()),
          _orderRow('Delivery', order['delivery_address']?.toString()),
          if (order['notes'] != null && order['notes'].toString().isNotEmpty)
            _orderRow('Notes', order['notes'].toString()),
        ],
      ),
    );
  }

  Widget _orderRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminColors.textSub(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: AdminColors.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Escalation Banner ──
  Widget _buildEscalationBanner(TicketDetail ticket) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminColors.error.withAlpha(_isDark ? 25 : 12),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: Border.all(color: AdminColors.error.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AdminColors.error.withAlpha(30),
              borderRadius: BorderRadius.circular(Brand.r(10)),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: AdminColors.error,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ESCALATED',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.error,
                    letterSpacing: 1,
                  ),
                ),
                if (ticket.escalationReason != null)
                  Text(
                    ticket.escalationReason!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.text(context),
                    ),
                  ),
                if (ticket.escalatedAt != null)
                  Text(
                    DateFormat('MMM d, h:mm a').format(ticket.escalatedAt!),
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textSub(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── SLA Indicator ──
  Widget _buildSlaIndicator(TicketDetail ticket) {
    final hours = ticket.age.inHours;
    final slaLimit = ticket.priority == 'urgent'
        ? 4
        : ticket.priority == 'high'
            ? 24
            : 72;
    final progress = (hours / slaLimit).clamp(0.0, 1.0);
    final overdue = hours > slaLimit;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: overdue
            ? AdminColors.error.withAlpha(_isDark ? 20 : 10)
            : AdminColors.bg(context),
        borderRadius: BorderRadius.circular(Brand.r(10)),
        border:
            overdue ? Border.all(color: AdminColors.error.withAlpha(50)) : null,
      ),
      child: Row(
        children: [
          Icon(
            overdue ? Icons.warning_amber_rounded : Icons.timer_outlined,
            size: 16,
            color: overdue ? AdminColors.error : AdminColors.textSub(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overdue
                      ? 'SLA Breached (${TimeUtils.formatDuration(ticket.age)} elapsed)'
                      : 'Response target: ${slaLimit}h',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: overdue
                        ? AdminColors.error
                        : AdminColors.textSub(context),
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Brand.r(4)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor:
                        _isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                      overdue
                          ? AdminColors.error
                          : progress > 0.7
                              ? AdminColors.warning
                              : AdminColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton(
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(Brand.r(10)),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  // ─── EMPTY CHAT ──────────────────────────────────────────
  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AdminColors.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(Brand.r(20)),
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 32,
              color: AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AdminColors.textSub(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Send the first reply to the customer',
            style: TextStyle(
              fontSize: 13,
              color: AdminColors.textHint(context),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _showQuickReplies = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AdminColors.primary.withAlpha(_isDark ? 25 : 15),
                borderRadius: BorderRadius.circular(Brand.r(10)),
                border: Border.all(color: AdminColors.primary.withAlpha(40)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flash_on_rounded,
                    size: 16,
                    color: _isDark
                        ? AdminColors.primary.withAlpha(200)
                        : AdminColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Use Quick Reply',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _isDark
                          ? AdminColors.primary.withAlpha(200)
                          : AdminColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showActionsSheet() {
    final ticket = _ticket;
    if (ticket == null) {
      _showSnackBar('Ticket is still loading…', isError: true);
      return;
    }
    ActionsSheet.show(
      context,
      title: 'Ticket Actions',
      actions: [
        ActionItem(
          icon: Icons.edit_rounded,
          title: 'Update Status',
          subtitle: 'Change ticket status',
          color: AdminColors.primary,
          onTap: () => SelectionSheet.show(
            context,
            title: 'Update Status',
            options: SelectionSheet.statusOptions,
            currentValue: ticket.status,
            onSelect: _updateStatus,
            confirmMessage: 'This will also notify the customer.',
          ),
        ),
        ActionItem(
          icon: Icons.flag_rounded,
          title: 'Update Priority',
          subtitle: 'Change priority level',
          color: AdminColors.warning,
          onTap: () => SelectionSheet.show(
            context,
            title: 'Update Priority',
            options: SelectionSheet.priorityOptions,
            currentValue: ticket.priority,
            onSelect: _updatePriority,
          ),
        ),
        ActionItem(
          icon: Icons.engineering_rounded,
          title: 'Assign Engineer',
          subtitle: 'Assign to a team member',
          color: AdminColors.info,
          onTap: _assignEngineer,
        ),
        ActionItem(
          icon: Icons.receipt_long_rounded,
          title: 'Create Invoice',
          subtitle: 'Generate invoice for this ticket',
          color: Brand.lightGreen,
          onTap: () {
            final customerId = ticket.customer?.id;
            if (customerId == null) {
              _showSnackBar(
                'Cannot create invoice: customer not loaded',
                isError: true,
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateInvoicePage(
                  customerId: customerId,
                  ticketId: widget.ticketId,
                  customerName: ticket.customer?.fullName,
                  customerCompany: ticket.customer?.companyName,
                ),
              ),
            );
          },
        ),
        ActionItem(
          icon: Icons.refresh_rounded,
          title: 'Reload Ticket',
          subtitle: 'Refresh all data',
          color: AdminColors.info,
          onTap: _loadAll,
        ),
        if (!ticket.isClosed)
          ActionItem(
            icon: Icons.check_circle_rounded,
            title: 'Resolve Ticket',
            subtitle: 'Mark as resolved',
            color: AdminColors.success,
            onTap: () => _updateStatus('resolved'),
          ),
      ],
    );
  }
}
