// lib/screens/admin/inquiry_chat_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/common/chat_message_attachments.dart';
// FIX: type-only imports acceptable per rules
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        RealtimeChannel,
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        RealtimeSubscribeStatus;
import '../../config/admin_theme.dart';
import '../../config/brand_colors.dart';
import '../../config/supabase_config.dart';
import '../../utils/time_utils.dart';

class InquiryChatPage extends StatefulWidget {
  final String ticketId;
  final String ticketNumber;
  final String customerName;

  const InquiryChatPage({
    super.key,
    required this.ticketId,
    required this.ticketNumber,
    required this.customerName,
  });

  @override
  State<InquiryChatPage> createState() => _InquiryChatPageState();
}

class _InquiryChatPageState extends State<InquiryChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSendingMessage = false;
  bool _showScrollToBottom = false;
  bool _hasText = false;
  bool _isInternalMode = false;
  bool _isOtherOnline = false;

  // ── Pagination ──
  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;

  String? _currentUserId;
  // Customer's user_id — fetched once on load so we can send them notifications
  // when the admin replies (non-internal messages only).
  String? _customerId;
  RealtimeChannel? _chatChannel;

  // L2: Pull warning palette from the shared StatusColors namespace instead
  // of redeclaring hex inline. `AdminColors.warning` isn't const so it can't
  // be used in a `static const`, but StatusColors constants are.
  static const Color _warningColor = StatusColors.warning;
  static const Color _warningDark = StatusColors.warningDark;

  // ─── Theme helpers (isDark passed from build) ───────────────
  // FIX: removed _isDark instance field mutated in build() — anti-pattern
  // All helpers now receive isDark as parameter or read from context

  Color _scaffoldBg(bool d) =>
      // FIX: AdminColors.background doesn't exist → Brand.scaffoldLight
      d ? Brand.darkBg : Brand.scaffoldLight;

  Color _cardBg(bool d) => d ? Brand.darkCard : Brand.cardLight;

  Color _cardElevated(bool d) =>
      // FIX: AdminColors.background doesn't exist
      d ? Brand.darkCardElevated : Brand.scaffoldLight;

  Color _textPrimary(bool d) =>
      // FIX: AdminColors.textPrimary doesn't exist
      d ? Brand.darkTextPrimary : Brand.royalBlueDark;

  Color _textSecondary(bool d) =>
      d ? Brand.darkTextSecondary : Colors.grey.shade500;

  Color _textMuted(bool d) => d ? Brand.darkTextTertiary : Colors.grey.shade400;

  Color _borderColor(bool d) => d ? Brand.darkBorder : Colors.grey.shade200;

  Color _primaryColor(bool d) => d ? Brand.royalBlueGlow : AdminColors.primary;

  // Quick reply templates
  final List<Map<String, String>> _quickReplies = [
    {
      'label': 'Acknowledge',
      'message': 'Thank you for your inquiry. We have received it and '
          'will get back to you shortly.'
    },
    {
      'label': 'Need Info',
      'message': 'Could you please provide more details about your '
          'requirements? This will help us prepare an accurate quotation.'
    },
    {
      'label': 'Quote Ready',
      'message': 'We have prepared a quotation for you. Please find '
          'the details attached.'
    },
    {
      'label': 'Follow Up',
      'message': 'Just checking in — have you had a chance to review '
          'our quotation? Please let us know if you have any questions.'
    },
    {
      'label': 'Schedule Demo',
      'message': 'We would like to schedule a demo for you. What '
          'dates and times work best?'
    },
  ];

  @override
  void initState() {
    super.initState();
    _currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    _scrollController.addListener(_onScrollChanged);
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
    _loadMessages();
    _subscribeToMessages();
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    // Mark messages read again on exit to catch any that arrived
    // during the session (prevents stale badge on parent page)
    _markMessagesAsRead();
    _messageController.dispose();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    // FIX: unsubscribe BEFORE removeChannel to prevent orphaned listeners
    if (_chatChannel != null) {
      _chatChannel!.unsubscribe();
      SupabaseConfig.client.removeChannel(_chatChannel!);
    }
    super.dispose();
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;

    // Scroll-to-bottom FAB visibility
    final isAtBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    final shouldShow = !isAtBottom;
    if (_showScrollToBottom != shouldShow) {
      setState(() => _showScrollToBottom = shouldShow);
    }

    // Load more when scrolled near top
    if (_scrollController.position.pixels <= 50 &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        _messages.isNotEmpty) {
      _loadMoreMessages();
    }
  }

  // ─── DATA ──────────────────────────────────────────────────

  Future<void> _loadMessages() async {
    try {
      // Fetch the ticket's customer (user_id) alongside messages so we can
      // create notifications when the admin replies.
      final ticketRow = await SupabaseConfig.client
          .from('service_tickets')
          .select('user_id')
          .eq('id', widget.ticketId)
          .maybeSingle();
      if (mounted && ticketRow != null) {
        _customerId = ticketRow['user_id'] as String?;
      }

      // FIX: fetch with sender join on initial load too
      final data = await SupabaseConfig.client
          .from('chat_messages')
          .select('''
            *,
            sender:users!sender_id(
              id, full_name, profile_photo, role
            )
          ''')
          .eq('ticket_id', widget.ticketId)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (!mounted) return;

      final msgList = List<Map<String, dynamic>>.from(data);
      setState(() {
        // Reverse so oldest is at top, newest at bottom
        _messages = msgList.reversed.toList();
        _hasMoreMessages = msgList.length >= _pageSize;
        _isLoading = false;
      });
      _scrollToBottom(animate: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Error loading messages', isError: true);
    }
  }

  void _subscribeToMessages() {
    _chatChannel = SupabaseConfig.client
        .channel('inquiry_chat_${widget.ticketId}')
        // ── INSERT: new messages ──────────────────────────────
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: widget.ticketId,
          ),
          callback: (payload) async {
            // FIX: wrap in try/catch per realtime pattern
            try {
              final raw = payload.newRecord;
              final msgId = raw['id'];
              if (msgId == null) return;

              // Mark as delivered if from a different sender
              if (raw['sender_id'] != _currentUserId &&
                  raw['delivered_at'] == null) {
                try {
                  await SupabaseConfig.client
                      .from('chat_messages')
                      .update(
                          {'delivered_at': DateTime.now().toUtc().toIso8601String()})
                      .eq('id', msgId)
                      .filter('delivered_at', 'is', null);
                } catch (e) {
                  debugPrint('delivered_at mark failed: $e');
                }
              }

              // Realtime sender join re-fetch pattern
              final enriched =
                  await SupabaseConfig.client.from('chat_messages').select('''
                    *,
                    sender:users!sender_id(
                      id, full_name, profile_photo, role
                    )
                  ''').eq('id', msgId).maybeSingle();

              if (!mounted || enriched == null) return;

              setState(() {
                // Replace optimistic message with real one, or add if new
                final existsById =
                    _messages.any((m) => m['id'] == enriched['id']);
                if (!existsById) {
                  _messages.removeWhere((m) =>
                      m['_optimistic'] == true &&
                      m['message'] == enriched['message'] &&
                      m['sender_id'] == enriched['sender_id']);
                  _messages.add(Map<String, dynamic>.from(enriched));
                }
              });

              // Mark as read if message is from someone else
              if (raw['sender_id'] != _currentUserId) {
                _markMessagesAsRead();
              }

              _scrollToBottomIfNeeded();
            } catch (e) {
              debugPrint('Realtime message enrich error: $e');
            }
          },
        )
        // ── UPDATE: read receipts & delivered_at changes ─────
        .onPostgresChanges(
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
              final msgId = updated['id'];
              if (msgId == null) return;
              setState(() {
                final idx = _messages.indexWhere((m) => m['id'] == msgId);
                if (idx != -1) {
                  _messages[idx] = {
                    ..._messages[idx],
                    'is_read': updated['is_read'],
                    'read_at': updated['read_at'],
                    'delivered_at': updated['delivered_at'],
                  };
                }
              });
            } catch (e) {
              debugPrint('Realtime update error: $e');
            }
          },
        )
        // ── PRESENCE: online status ───────────────────────────
        .onPresenceSync((_) {
          if (!mounted) return;
          try {
            final state = _chatChannel!.presenceState();
            final hasOthers = state.expand((s) => s.presences).any((p) {
              try {
                return (p.payload['user_id'] as String?) != _currentUserId;
              } catch (_) {
                return false;
              }
            });
            setState(() => _isOtherOnline = hasOthers);
          } catch (_) {}
        })
        .subscribe((RealtimeSubscribeStatus status, [Object? error]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            try {
              await _chatChannel!
                  .track({'user_id': _currentUserId ?? 'anonymous'});
            } catch (_) {}
          }
        });
  }

  Future<void> _markMessagesAsRead() async {
    if (_currentUserId == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await SupabaseConfig.client
          .from('chat_messages')
          .update({
            'is_read': true,
            'read_at': now,
            'delivered_at': now,
          })
          .eq('ticket_id', widget.ticketId)
          .neq('sender_id', _currentUserId!)
          .eq('is_read', false);
    } catch (_) {}
    // Clear notification badge for this inquiry. Ticket notifications store the
    // ticket ID in metadata->>'ticket_id', not in related_id. Use the JSONB
    // filter so the update actually matches the right rows.
    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _currentUserId!)
          .eq('type', 'ticket_update')
          .filter('metadata->>ticket_id', 'eq', widget.ticketId)
          .eq('is_read', false);
    } catch (_) {}
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty || _isLoadingMore || !_hasMoreMessages) return;

    // Skip optimistic messages
    final serverMessages =
        _messages.where((m) => m['_optimistic'] != true).toList();
    if (serverMessages.isEmpty) return;

    setState(() => _isLoadingMore = true);

    final oldestCreatedAt = serverMessages.first['created_at'] as String;
    final pixelsBefore = _scrollController.position.pixels;
    final extentBefore = _scrollController.position.maxScrollExtent;

    try {
      final older = await SupabaseConfig.client
          .from('chat_messages')
          .select('''
            *,
            sender:users!sender_id(
              id, full_name, profile_photo, role
            )
          ''')
          .eq('ticket_id', widget.ticketId)
          .lt('created_at', oldestCreatedAt)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      // FIX: mounted check after every await
      if (!mounted) return;

      final olderList =
          List<Map<String, dynamic>>.from(older).reversed.toList();

      setState(() {
        _messages.insertAll(0, olderList);
        _hasMoreMessages = olderList.length >= _pageSize;
        _isLoadingMore = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final extentAfter = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(pixelsBefore + (extentAfter - extentBefore));
        }
      });
    } catch (e) {
      debugPrint('Load more messages error: $e');
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _currentUserId == null) return;

    final isInternal = _isInternalMode;
    _messageController.clear();

    // FIX: optimistic message uses spread copy pattern
    final optimistic = <String, dynamic>{
      'ticket_id': widget.ticketId,
      'sender_id': _currentUserId,
      'sender_type': 'admin',
      'message': messageText,
      'is_internal': isInternal,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      '_optimistic': true,
      '_status': 'sending',
    };

    setState(() {
      _messages.add(optimistic);
      _isSendingMessage = true;
    });
    _scrollToBottom();

    try {
      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': _currentUserId,
        'sender_type': 'admin',
        'message': messageText,
        'is_internal': isInternal,
      });

      // Notify the customer that the admin replied — non-internal messages only.
      // The notification stores the ticket ID in metadata so that tapping it
      // navigates to the correct inquiry chat screen.
      if (!isInternal && _customerId != null) {
        try {
          await SupabaseConfig.client.from('notifications').insert({
            'user_id': _customerId,
            'title': 'New reply on your inquiry',
            'message':
                'Admin replied to inquiry #${widget.ticketNumber}: "${messageText.length > 60 ? '${messageText.substring(0, 60)}…' : messageText}"',
            'type': 'ticket_update',
            'metadata': {
              'ticket_id': widget.ticketId,
              'ticket_type': 'inquiry',
            },
            'is_read': false,
          });
        } catch (e) {
          debugPrint('⚠️ Inquiry reply notification failed (non-critical): $e');
        }
      }

      if (!mounted) return;
      setState(() {
        // Remove optimistic message — the realtime subscription
        // will deliver the real one with proper id + sender info
        _messages.removeWhere((m) =>
            m['_optimistic'] == true &&
            m['message'] == messageText &&
            m['sender_id'] == _currentUserId);
        _isSendingMessage = false;
        // Auto-disable internal mode after sending
        if (isInternal) _isInternalMode = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexOf(optimistic);
        if (idx != -1) {
          // FIX: spread copy on map update
          _messages[idx] = {
            ...optimistic,
            '_status': 'failed',
          };
        }
        _isSendingMessage = false;
      });
      _showSnackBar('Failed to send message', isError: true);
    }
  }

  Future<void> _retryMessage(Map<String, dynamic> failedMessage) async {
    setState(() {
      _messages.remove(failedMessage);
    });
    _messageController.text = failedMessage['message'] ?? '';
    _isInternalMode = failedMessage['is_internal'] == true;
    _sendMessage();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        if (animate) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  void _scrollToBottomIfNeeded() {
    if (!mounted) return;
    final sc = _scrollController;
    if (sc.hasClients) {
      // Near bottom: auto-scroll to show new message
      final distanceFromBottom =
          sc.position.maxScrollExtent - sc.position.pixels;
      if (distanceFromBottom < 150) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          sc.animateTo(
            sc.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    }
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
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AdminColors.error : AdminColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // FIX: compute isDark once in build, pass to all helpers
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _scaffoldBg(isDark),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            if (_isInternalMode) _buildInternalModeBanner(isDark),
            Expanded(
              child: Stack(
                children: [
                  _isLoading
                      ? _buildChatSkeleton(isDark)
                      : _messages.isEmpty
                          ? _buildEmptyChat(isDark)
                          : ListView.builder(
                              controller: _scrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 10, 20, 10),
                              itemCount:
                                  _messages.length + (_isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (_isLoadingMore && index == 0) {
                                  return _buildLoadingMoreIndicator(isDark);
                                }
                                final msgIndex =
                                    index - (_isLoadingMore ? 1 : 0);
                                return _buildMessageBubble(
                                  _messages[msgIndex],
                                  msgIndex,
                                  isDark,
                                );
                              },
                            ),
                  if (_showScrollToBottom)
                    Positioned(
                      right: 16,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: () => _scrollToBottom(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _cardBg(isDark),
                            shape: BoxShape.circle,
                            border: isDark
                                ? Border.all(color: Brand.darkBorder)
                                : null,
                            boxShadow: isDark
                                ? null
                                : [
                                    BoxShadow(
                                      // FIX: .withOpacity → .withAlpha
                                      color: Brand.royalBlue.withAlpha(26),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: isDark
                                ? Brand.darkIconActive
                                : AdminColors.primary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!_isLoading) _buildQuickRepliesBar(isDark),
            _buildMessageInput(isDark),
          ],
        ),
      ),
    );
  }

  // ─── INTERNAL MODE BANNER ──────────────────────────────────
  Widget _buildInternalModeBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      // FIX: .withOpacity() → .withAlpha()
      color: _warningColor.withAlpha(isDark ? 26 : 15),
      child: Row(
        children: [
          Icon(
            Icons.lock_rounded,
            size: 14,
            color: isDark ? _warningColor : _warningDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Internal note mode — messages won\'t be visible to customer',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? _warningColor : _warningDark,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isInternalMode = false),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: isDark ? _warningColor : _warningDark,
            ),
          ),
        ],
      ),
    );
  }

  // ─── SKELETON LOADING ──────────────────────────────────────
  Widget _buildChatSkeleton(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, index) {
        final isRight = index % 3 != 0;
        return Align(
          alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            width: MediaQuery.of(context).size.width * (isRight ? 0.6 : 0.7),
            height: 52 + (index % 2 == 0 ? 20.0 : 0.0),
            decoration: BoxDecoration(
              color: isRight
                  // FIX: .withOpacity() → .withAlpha()
                  ? AdminColors.primary.withAlpha(isDark ? 38 : 20)
                  : (isDark ? Brand.darkCardElevated : Colors.grey.shade100),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isRight ? 18 : 4),
                bottomRight: Radius.circular(isRight ? 4 : 18),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── HEADER ────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        border: isDark
            ? const Border(bottom: BorderSide(color: Brand.darkBorder))
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  // FIX: .withOpacity() → .withAlpha()
                  color: Brand.royalBlue.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _cardElevated(isDark),
                borderRadius: BorderRadius.circular(10),
                border:
                    isDark ? Border.all(color: Brand.darkBorderLight) : null,
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _primaryColor(isDark),
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              // FIX: .withOpacity() → .withAlpha()
              color: AdminColors.accent.withAlpha(isDark ? 38 : 26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                widget.customerName.isNotEmpty
                    ? widget.customerName[0].toUpperCase()
                    : 'C',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Brand.lightGreenBright : AdminColors.accent,
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
                  widget.customerName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor(isDark),
                  ),
                ),
                // ── Online presence indicator ──
                Row(
                  children: [
                    if (_isOtherOnline) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Online',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF4CAF50)
                              : Colors.green.shade600,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('·',
                          style: TextStyle(
                              fontSize: 11,
                              color: _textSecondary(isDark))),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      widget.ticketNumber,
                      style: TextStyle(
                          fontSize: 12, color: _textSecondary(isDark)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _loadMessages();
              _showSnackBar('Messages refreshed');
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _cardElevated(isDark),
                borderRadius: BorderRadius.circular(10),
                border:
                    isDark ? Border.all(color: Brand.darkBorderLight) : null,
              ),
              child: Icon(
                Icons.refresh_rounded,
                color: isDark ? Brand.darkTextSecondary : AdminColors.primary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY CHAT ────────────────────────────────────────────
  Widget _buildEmptyChat(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              // FIX: .withOpacity() → .withAlpha()
              color: AdminColors.primary.withAlpha(isDark ? 26 : 15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 32,
              color: _textMuted(isDark),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Send the first message to the customer',
            style: TextStyle(fontSize: 13, color: _textMuted(isDark)),
          ),
        ],
      ),
    );
  }

  // ─── MESSAGE BUBBLE ────────────────────────────────────────
  Widget _buildMessageBubble(
    Map<String, dynamic> message,
    int index,
    bool isDark,
  ) {
    final senderType = message['sender_type']?.toString() ?? '';
    final isAdmin = senderType == 'admin' || senderType == 'engineer';
    final isSystem = senderType == 'system';
    final isInternal = message['is_internal'] == true;
    final timestamp = DateTime.parse(message['created_at']);
    final isFailed = message['_status'] == 'failed';
    final isSending = message['_status'] == 'sending';
    final isCurrentUser = message['sender_id'] == _currentUserId;

    // Date separator
    Widget? dateSeparator;
    if (index == 0 ||
        TimeUtils.isDifferentDay(
          DateTime.parse(_messages[index - 1]['created_at']),
          timestamp,
        )) {
      dateSeparator = _buildDateSeparator(timestamp, isDark);
    }

    // ── System / internal-system messages ──
    if (isSystem || (isInternal && isAdmin && _isSystemLikeMessage(message))) {
      return Column(
        children: [
          if (dateSeparator != null) dateSeparator,
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCardElevated : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: isDark ? Border.all(color: Brand.darkBorderLight) : null,
            ),
            child: Text(
              message['message'] ?? '',
              style: TextStyle(
                fontSize: 12,
                color: _textSecondary(isDark),
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (dateSeparator != null) dateSeparator,
        Align(
          alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: () {
              HapticFeedback.mediumImpact();
              Clipboard.setData(ClipboardData(text: message['message'] ?? ''));
              _showSnackBar('Message copied');
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              child: Column(
                crossAxisAlignment:
                    isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // Sender label
                  Padding(
                    padding: EdgeInsets.only(
                      left: isAdmin ? 0 : 12,
                      right: isAdmin ? 12 : 0,
                      bottom: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isCurrentUser) ...[
                          Builder(builder: (_) {
                            final photo = (message['sender']
                                    as Map<String, dynamic>?)?['profile_photo']
                                as String?;
                            final tint =
                                isAdmin ? AdminColors.primary : Brand.royalBlue;
                            final fb = Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tint.withAlpha(30),
                              ),
                              child: Icon(
                                senderType == 'engineer'
                                    ? Icons.engineering_rounded
                                    : isAdmin
                                        ? Icons.support_agent_rounded
                                        : Icons.person_rounded,
                                size: 14,
                                color: tint,
                              ),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: (photo == null || photo.isEmpty)
                                  ? fb
                                  : ClipOval(
                                      child: CachedNetworkImage(
                                        imageUrl: photo,
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => fb,
                                        errorWidget: (_, __, ___) => fb,
                                      ),
                                    ),
                            );
                          }),
                        ],
                        Text(
                          isAdmin
                              ? (isCurrentUser
                                  ? 'You'
                                  : (senderType == 'engineer'
                                      ? 'Engineer'
                                      : 'Admin'))
                              : 'Customer',
                          style: TextStyle(
                            fontSize: 12,
                            color: _textMuted(isDark),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isInternal) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              // FIX: .withOpacity() → .withAlpha()
                              color: _warningColor.withAlpha(isDark ? 38 : 26),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'INTERNAL',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? _warningColor : _warningDark,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Bubble
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isFailed
                          // FIX: .withOpacity() → .withAlpha()
                          ? AdminColors.error.withAlpha(isDark ? 31 : 20)
                          : isInternal
                              ? _warningColor.withAlpha(isDark ? 31 : 20)
                              : isAdmin
                                  ? AdminColors.primary
                                  : (isDark
                                      ? Brand.darkCardElevated
                                      : Brand.cardLight),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isAdmin ? 18 : 4),
                        bottomRight: Radius.circular(isAdmin ? 4 : 18),
                      ),
                      border: isFailed
                          ? Border.all(
                              color: AdminColors.error
                                  .withAlpha(isDark ? 102 : 77))
                          : isInternal
                              ? Border.all(
                                  color:
                                      _warningColor.withAlpha(isDark ? 77 : 51))
                              : (isDark && !isAdmin)
                                  ? Border.all(color: Brand.darkBorderLight)
                                  : null,
                      boxShadow: isFailed || isDark
                          ? null
                          : [
                              BoxShadow(
                                // FIX: .withOpacity() → .withAlpha()
                                color: Brand.royalBlue.withAlpha(10),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (_) {
                          final mt =
                              message['message_type'] as String? ?? 'text';
                          if (mt != 'voice' &&
                              mt != 'document' &&
                              mt != 'location') {
                            return const SizedBox.shrink();
                          }
                          final atts = message['attachments'] is List
                              ? List<String>.from(
                                  (message['attachments'] as List)
                                      .map((e) => e.toString()))
                              : const <String>[];
                          final meta = message['metadata'] is Map
                              ? Map<String, dynamic>.from(
                                  message['metadata'] as Map)
                              : null;
                          final w = buildChatAttachment(
                            messageType: mt,
                            attachments: atts,
                            metadata: meta,
                            isMe: isAdmin,
                            accent:
                                isAdmin ? Colors.white : AdminColors.primary,
                          );
                          return w == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: w);
                        }),
                        Text(
                          message['message'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: isFailed
                                ? AdminColors.error
                                : isInternal
                                    ? (isDark
                                        ? _warningColor
                                        : Colors.orange.shade800)
                                    : isAdmin
                                        ? Colors.white
                                        : _textPrimary(isDark),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              TimeUtils.formatTime(timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: isAdmin && !isFailed && !isInternal
                                    // FIX: .withOpacity → .withAlpha
                                    ? Colors.white.withAlpha(128)
                                    : _textMuted(isDark),
                              ),
                            ),
                            if (isSending) ...[
                              const SizedBox(width: 4),
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  // FIX: .withOpacity → .withAlpha
                                  color: Colors.white.withAlpha(128),
                                ),
                              ),
                            ],
                            if (isFailed) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 12,
                                color: AdminColors.error,
                              ),
                            ],
                            // ── WhatsApp-style delivery/read ticks ──
                            if (isCurrentUser && !isSending && !isFailed) ...[
                              const SizedBox(width: 4),
                              Builder(builder: (_) {
                                final isRead = message['is_read'] == true;
                                final delivered =
                                    message['delivered_at'] != null;
                                if (isRead) {
                                  // Blue double tick = read
                                  return const Icon(Icons.done_all_rounded,
                                      size: 14,
                                      color: Color(0xFF58A6FF));
                                }
                                if (delivered) {
                                  // Grey double tick = delivered
                                  return Icon(Icons.done_all_rounded,
                                      size: 14,
                                      color: Colors.white.withAlpha(140));
                                }
                                // Single grey tick = sent
                                return Icon(Icons.done_rounded,
                                    size: 14,
                                    color: Colors.white.withAlpha(100));
                              }),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Retry button
                  if (isFailed)
                    GestureDetector(
                      onTap: () => _retryMessage(message),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 4, right: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded,
                                size: 12, color: AdminColors.error),
                            SizedBox(width: 4),
                            Text(
                              'Tap to retry',
                              style: TextStyle(
                                fontSize: 12,
                                color: AdminColors.error,
                                fontWeight: FontWeight.w500,
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

  bool _isSystemLikeMessage(Map<String, dynamic> message) {
    final msg = (message['message'] ?? '').toString().toLowerCase();
    return msg.startsWith('sales stage changed') ||
        msg.startsWith('quote sent') ||
        msg.startsWith('marked as hot lead') ||
        msg.startsWith('removed hot lead');
  }

  // ─── DATE SEPARATOR ────────────────────────────────────────
  Widget _buildDateSeparator(DateTime date, bool isDark) {
    final label = TimeUtils.formatDateSeparator(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: _borderColor(isDark))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: _textMuted(isDark),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: _borderColor(isDark))),
        ],
      ),
    );
  }

  // ─── LOADING MORE INDICATOR ────────────────────────────────
  Widget _buildLoadingMoreIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _primaryColor(isDark),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading older messages…',
              style: TextStyle(
                fontSize: 12,
                color: _textMuted(isDark),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── QUICK REPLIES ─────────────────────────────────────────
  Widget _buildQuickRepliesBar(bool isDark) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _quickReplies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final reply = _quickReplies[index];
          return GestureDetector(
            onTap: () {
              _messageController.text = reply['message']!;
              _messageController.selection = TextSelection.fromPosition(
                TextPosition(offset: _messageController.text.length),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                // FIX: .withOpacity() → .withAlpha()
                color: AdminColors.primary.withAlpha(isDark ? 31 : 15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AdminColors.primary.withAlpha(isDark ? 64 : 38),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flash_on_rounded,
                      size: 14, color: _primaryColor(isDark)),
                  const SizedBox(width: 4),
                  Text(
                    reply['label']!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor(isDark),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── MESSAGE INPUT ─────────────────────────────────────────
  Widget _buildMessageInput(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        border: isDark
            ? const Border(top: BorderSide(color: Brand.darkBorder))
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  // FIX: .withOpacity() → .withAlpha()
                  color: Brand.royalBlue.withAlpha(15),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Internal note toggle
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isInternalMode = !_isInternalMode);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 46,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _isInternalMode
                    // FIX: .withOpacity() → .withAlpha()
                    ? _warningColor.withAlpha(isDark ? 38 : 26)
                    : _cardElevated(isDark),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isInternalMode
                      ? _warningColor.withAlpha(isDark ? 102 : 77)
                      : (isDark ? Brand.darkBorderLight : Colors.grey.shade200),
                ),
              ),
              child: Icon(
                _isInternalMode ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 18,
                color: _isInternalMode
                    ? (isDark ? _warningColor : _warningDark)
                    : _textMuted(isDark),
              ),
            ),
          ),
          // Text input
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: _cardElevated(isDark),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isInternalMode
                      ? _warningColor.withAlpha(isDark ? 77 : 51)
                      : (isDark ? Brand.darkBorderLight : Colors.transparent),
                ),
              ),
              child: TextField(
                controller: _messageController,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 14, color: _textPrimary(isDark)),
                decoration: InputDecoration(
                  hintText: _isInternalMode
                      ? 'Type internal note...'
                      : 'Type your reply...',
                  hintStyle: TextStyle(
                    color: _isInternalMode
                        ? (isDark
                            ? _warningColor.withAlpha(128)
                            : _warningDark.withAlpha(102))
                        : _textMuted(isDark),
                    fontSize: 14,
                  ),
                  enabledBorder: InputBorder.none,
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                        color: isDark ? Brand.darkIconActive : Brand.royalBlue,
                        width: 1.5),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          GestureDetector(
            onTap: _isSendingMessage || !_hasText ? null : _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: _hasText && !_isSendingMessage
                    ? (_isInternalMode
                        ? const LinearGradient(colors: [
                            _warningColor,
                            _warningDark,
                          ])
                        : const LinearGradient(colors: [
                            AdminColors.primary,
                            Brand.royalBlueLight,
                          ]))
                    : null,
                color: _hasText && !_isSendingMessage
                    ? null
                    : (isDark ? Brand.darkBorder : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _hasText && !_isSendingMessage
                    ? [
                        BoxShadow(
                          color: (_isInternalMode
                                  ? _warningColor
                                  : AdminColors.primary)
                              // FIX: .withOpacity() → .withAlpha()
                              .withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: _isSendingMessage
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : Icon(
                      _isInternalMode ? Icons.lock_rounded : Icons.send_rounded,
                      color: _hasText
                          ? Colors.white
                          : (isDark ? Brand.darkTextTertiary : Colors.white),
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
