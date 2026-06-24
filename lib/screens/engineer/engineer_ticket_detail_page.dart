// lib/screens/engineer/engineer_ticket_detail_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        RealtimeChannel,
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        RealtimeSubscribeStatus;
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../config/brand_colors.dart';
import '../../config/admin_theme.dart';
import '../../widgets/ds/ds_widgets.dart';
import '../../utils/time_utils.dart';
import '../../utils/string_utils.dart';
import '../../widgets/common/chat_attach_bar.dart';
import '../../widgets/common/chat_message_attachments.dart';

const Color _engAccent = Brand.cyanAccent;
const Color _engAccentDark = Brand.cyanAccentDark;

class EngineerTicketDetailPage extends StatefulWidget {
  final String ticketId;
  const EngineerTicketDetailPage({super.key, required this.ticketId});

  @override
  State<EngineerTicketDetailPage> createState() =>
      _EngineerTicketDetailPageState();
}

class _EngineerTicketDetailPageState extends State<EngineerTicketDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic> _ticket = {};
  Map<String, dynamic> _customer = {};
  Map<String, dynamic>? _machine;
  List<Map<String, dynamic>> _messages = [];

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isSending = false;
  bool _infoExpanded = true;
  bool _internalMode = false;

  RealtimeChannel? _msgChannel;
  RealtimeChannel? _ticketChannel;

  // ── Live location sharing (en-route) ──
  StreamSubscription<Position>? _locSub;


  // ── Pagination ──
  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;

  String? get _currentUserId => SupabaseConfig.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onChatScroll);
    _loadAll();
    _subscribeMessages();
    _subscribeTicket();
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.removeListener(_onChatScroll);
    _scrollCtrl.dispose();
    if (_msgChannel != null) {
      SupabaseConfig.client.removeChannel(_msgChannel!);
    }
    if (_ticketChannel != null) {
      SupabaseConfig.client.removeChannel(_ticketChannel!);
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  DATA LOADING
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final uid = _currentUserId;
      if (uid == null) return;

      final results = await Future.wait<dynamic>([
        SupabaseConfig.client.from('service_tickets').select('''
          *,
          customer:users!service_tickets_user_id_fkey(*),
          customer_machine:customer_machines(
            *, catalog_machine:machine_catalog(*)
          )
        ''').eq('id', widget.ticketId).single(),
        SupabaseConfig.client
            .from('chat_messages')
            .select('''
          *, sender:users!chat_messages_sender_id_fkey(
            full_name, role, profile_photo
          )
        ''')
            .eq('ticket_id', widget.ticketId)
            .order('created_at', ascending: false)
            .limit(_pageSize),
      ]);

      if (!mounted) return;

      final ticketRes = results[0] as Map<String, dynamic>;
      final messagesRes = results[1] as List;

      final msgList = List<Map<String, dynamic>>.from(messagesRes);
      setState(() {
        _ticket = Map<String, dynamic>.from(ticketRes);
        _customer = Map<String, dynamic>.from(_ticket['customer'] ?? {});
        _machine = _ticket['customer_machine'] != null
            ? Map<String, dynamic>.from(_ticket['customer_machine'])
            : null;
        _messages = msgList.reversed.toList();
        _hasMoreMessages = msgList.length >= _pageSize;
        _isLoading = false;
      });

      _scrollToBottom();

      // Resume live location sharing if this ticket is still en-route.
      if (_ticket['status'] == 'en_route' &&
          _ticket['assigned_to'] == uid &&
          _locSub == null) {
        _startLocationStream();
      }

      // Fire-and-forget: mark messages as read
      _markMessagesAsRead();
    } catch (e) {
      debugPrint('❌ Engineer ticket detail load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  REALTIME SUBSCRIPTIONS
  // ═══════════════════════════════════════════════════════════

  void _subscribeMessages() {
    _msgChannel = SupabaseConfig.client
        .channel('eng_ticket_${widget.ticketId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: widget.ticketId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final newId = payload.newRecord['id'] as String?;
            if (newId == null) return;
            _handleRealtimeMessage(newId);
          },
        )
        // UPDATE subscription — propagates is_read / delivered_at changes so
        // ticks update live without a full reload.
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
            final updated = payload.newRecord;
            final msgId = updated['id']?.toString();
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
          },
        )
        .onPresenceSync((_) {})
        .subscribe((RealtimeSubscribeStatus status, [Object? error]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _msgChannel!
                .track({'user_id': _currentUserId ?? 'anonymous'});
          }
        });
  }

  Future<void> _handleRealtimeMessage(String messageId) async {
    try {
      // Skip if already in list
      if (_messages.any((m) => m['id'] == messageId)) return;

      // Fetch with sender join so we have name/photo
      final msg = await SupabaseConfig.client.from('chat_messages').select('''
          *, sender:users!chat_messages_sender_id_fkey(
            full_name, role, profile_photo
          )
        ''').eq('id', messageId).single();

      if (!mounted) return;
      if (_messages.any((m) => m['id'] == msg['id'])) return;

      setState(() => _messages.add(Map<String, dynamic>.from(msg)));
      _scrollToBottom();

      if (msg['sender_type'] != 'engineer') {
        _markMessagesAsRead();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to fetch realtime message: $e');
    }
  }

  void _subscribeTicket() {
    _ticketChannel = SupabaseConfig.client
        .channel('eng_ticket_upd_${widget.ticketId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'service_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.ticketId,
          ),
          callback: (payload) {
            if (!mounted) return;
            // Merge realtime fields into existing ticket
            // (realtime doesn't include joined data)
            setState(() {
              _ticket = {
                ..._ticket,
                ...Map<String, dynamic>.from(payload.newRecord),
              };
            });
          },
        )
        .subscribe();
  }

  Future<void> _markMessagesAsRead() async {
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
          .neq('sender_type', 'engineer')
          .eq('is_read', false);
    } catch (_) {}
    // Clear notification badge so the bell stops showing this ticket as unread.
    // Ticket notifications store the ticket ID in metadata->>'ticket_id' (not
    // in related_id) so we use the JSONB filter to match the right rows.
    final uid = _currentUserId;
    if (uid != null) {
      try {
        await SupabaseConfig.client
            .from('notifications')
            .update({'is_read': true})
            .eq('user_id', uid)
            .eq('type', 'ticket_update')
            .filter('metadata->>ticket_id', 'eq', widget.ticketId)
            .eq('is_read', false);
      } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  PAGINATION
  // ═══════════════════════════════════════════════════════════

  void _onChatScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels <= 50 &&
        !_isLoadingMore &&
        _hasMoreMessages &&
        _messages.isNotEmpty) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty || _isLoadingMore || !_hasMoreMessages) return;
    setState(() => _isLoadingMore = true);

    final oldestCreatedAt = _messages.first['created_at'] as String;
    final pixelsBefore = _scrollCtrl.position.pixels;
    final extentBefore = _scrollCtrl.position.maxScrollExtent;

    try {
      final older = await SupabaseConfig.client
          .from('chat_messages')
          .select('''
        *, sender:users!chat_messages_sender_id_fkey(
          full_name, role, profile_photo
        )
      ''')
          .eq('ticket_id', widget.ticketId)
          .lt('created_at', oldestCreatedAt)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (!mounted) return;

      final olderList =
          List<Map<String, dynamic>>.from(older).reversed.toList();

      setState(() {
        _messages.insertAll(0, olderList);
        _hasMoreMessages = olderList.length >= _pageSize;
        _isLoadingMore = false;
      });

      // Maintain scroll position after prepending
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          final extentAfter = _scrollCtrl.position.maxScrollExtent;
          _scrollCtrl.jumpTo(pixelsBefore + (extentAfter - extentBefore));
        }
      });
    } catch (e) {
      debugPrint('❌ Load more messages error: $e');
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════════════

  Future<void> _sendAttachment({
    required String messageType,
    required List<String> attachments,
    Map<String, dynamic>? metadata,
  }) async {
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': uid,
        'sender_type': 'engineer',
        'message': '',
        'message_type': messageType,
        'attachments': attachments,
        'metadata': metadata ?? {},
        'is_read': false,
        'is_internal': false,
      });
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to send attachment: $e', isError: true);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    final wasInternal = _internalMode;
    setState(() => _isSending = true);

    try {
      final uid = _currentUserId;
      if (uid == null) return;

      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': uid,
        'sender_type': 'engineer',
        'message': text,
        'is_read': false,
        'is_internal': wasInternal,
      });
      if (!mounted) return;

      // Auto-progress for non-internal messages
      if (!wasInternal && ['open', 'assigned'].contains(_ticket['status'])) {
        await SupabaseConfig.client.from('service_tickets').update({
          'status': 'in_progress',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', widget.ticketId);
        if (!mounted) return;
        setState(() => _ticket = {..._ticket, 'status': 'in_progress'});
      }

      _msgCtrl.clear();

      // Auto-reset internal mode after send (handoff §25)
      if (wasInternal && mounted) {
        setState(() => _internalMode = false);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to send: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      final update = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (['resolved', 'closed'].contains(newStatus)) {
        update['closed_at'] = DateTime.now().toUtc().toIso8601String();
      } else {
        // Clear closed_at when reopening
        update['closed_at'] = null;
      }

      await SupabaseConfig.client
          .from('service_tickets')
          .update(update)
          .eq('id', widget.ticketId);
      if (!mounted) return;

      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': _currentUserId,
        'sender_type': 'system',
        'message':
            'Status updated to: ${newStatus.replaceAll('_', ' ').toUpperCase()}',
        'is_internal': false,
      });
      if (!mounted) return;

      setState(() => _ticket = {..._ticket, 'status': newStatus});
      if (newStatus != 'en_route') _stopLocationStream();
      _showSnackBar(
        'Status updated to ${newStatus.replaceAll("_", " ").toUpperCase()}',
        icon: Icons.check_circle_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to update: $e', isError: true);
    }
  }

  Future<void> _startLocationStream() async {
    // Prevent duplicate subscriptions if called multiple times in quick succession
    if (_locSub != null) return;

    final uid = _currentUserId;
    if (uid == null) return;

    try {
      _upsertLocation(uid, await Geolocator.getCurrentPosition());
    } catch (_) {}

    _locSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    ).listen((p) => _upsertLocation(uid, p));
  }

  Future<void> _upsertLocation(String uid, Position p) async {
    try {
      await SupabaseConfig.client.from('ticket_engineer_locations').upsert({
        'ticket_id': widget.ticketId,
        'engineer_id': uid,
        'lat': p.latitude,
        'lng': p.longitude,
        'heading': p.heading,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _stopLocationStream() async {
    await _locSub?.cancel();
    _locSub = null;
  }

  Future<void> _removeEscalation() async {
    try {
      await SupabaseConfig.client.from('service_tickets').update({
        'escalated': false,
        'escalated_at': null,
        'escalation_reason': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.ticketId);
      if (!mounted) return;

      await SupabaseConfig.client.from('chat_messages').insert({
        'ticket_id': widget.ticketId,
        'sender_id': _currentUserId,
        'sender_type': 'engineer',
        'message': 'Escalation removed by engineer',
        'is_internal': true,
      });
      if (!mounted) return;

      setState(() {
        _ticket = {
          ..._ticket,
          'escalated': false,
          'escalation_reason': null,
        };
      });
      _showSnackBar('Escalation removed', icon: Icons.check_circle_rounded);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed: $e', isError: true);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color _statusColor(String s) {
    switch (s) {
      case 'open':
        return Brand.darkIconActive;
      case 'assigned':
        return AdminColors.info;
      case 'in_progress':
        return AdminColors.warning;
      case 'waiting_customer':
        return StatusColors.assigned;
      case 'resolved':
        return Brand.lightGreenBright;
      case 'closed':
        return Brand.darkTextSecondary;
      default:
        return Brand.darkTextSecondary;
    }
  }

  void _showSnackBar(String message, {bool isError = false, IconData? icon}) {
    if (!mounted) return;
    final effectiveIcon =
        icon ?? (isError ? Icons.error_outline_rounded : null);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (effectiveIcon != null) ...[
              Icon(effectiveIcon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        backgroundColor: isError ? StatusColors.danger : _engAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.r(14))),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    return Scaffold(
      backgroundColor: Brand.canvas(isDark),
      appBar: DsPageHeader(
        title: 'Ticket #${_ticket['ticket_number'] ?? ''}',
        subtitle: _ticket['subject'] as String?,
        accent: HeroAccent.cyan,
      ),
      body: _isLoading ? _buildSkeleton(isDark) : _buildBody(isDark),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  BODY
  // ═══════════════════════════════════════════════════════════

  Widget _buildBody(bool isDark) {
    final isClosed = ['closed', 'resolved'].contains(_ticket['status']);

    return Column(
      children: [
        _buildInfoPanel(isDark),
        if (_ticket['escalated'] == true) _buildEscalationBanner(isDark),
        _buildChatHeader(isDark),
        Expanded(child: _buildChatArea(isDark)),
        if (!isClosed) _buildInputBar(isDark),
        if (isClosed) _buildClosedBanner(isDark),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  INFO PANEL
  // ═══════════════════════════════════════════════════════════

  Widget _buildInfoPanel(bool isDark) {
    final catalog = _machine?['catalog_machine'] as Map<String, dynamic>?;
    final ticketType = _ticket['ticket_type'] as String? ?? 'support';

    return Container(
      color: Brand.surface(isDark),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _infoExpanded = !_infoExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _ticket['subject'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Brand.darkTextPrimary
                            : Brand.royalBlueDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _infoExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _infoExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _infoChip(
                                Icons.person_rounded,
                                _customer['full_name'] ?? 'Unknown',
                                isDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _infoChip(
                                Icons.business_rounded,
                                _customer['company_name'] ?? '—',
                                isDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Contact actions — tap to call / email
                        Row(
                          children: [
                            if (_customer['phone_number'] != null &&
                                (_customer['phone_number'] as String)
                                    .isNotEmpty)
                              Expanded(
                                child: _contactAction(
                                  Icons.phone_rounded,
                                  _customer['phone_number'],
                                  Brand.lightGreenBright,
                                  isDark,
                                  onTap: () => _launchUrl(
                                    'tel:${_customer['phone_number']}',
                                  ),
                                ),
                              ),
                            if (_customer['phone_number'] != null &&
                                _customer['email'] != null)
                              const SizedBox(width: 8),
                            if (_customer['email'] != null &&
                                (_customer['email'] as String).isNotEmpty)
                              Expanded(
                                child: _contactAction(
                                  Icons.email_rounded,
                                  _customer['email'],
                                  isDark ? Brand.royalBlueGlow : Brand.royalBlue,
                                  isDark,
                                  onTap: () => _launchUrl(
                                    'mailto:${_customer['email']}',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (catalog != null) ...[
                          const SizedBox(height: 8),
                          _infoChip(
                            Icons.settings_suggest_rounded,
                            '${catalog['machine_name']} · ${catalog['model_number'] ?? ''}',
                            isDark,
                          ),
                          if (_machine?['serial_number'] != null) ...[
                            const SizedBox(height: 8),
                            _infoChip(
                              Icons.qr_code_rounded,
                              'S/N: ${_machine!['serial_number']}',
                              isDark,
                            ),
                          ],
                        ],
                        // Order metadata
                        if (ticketType == 'order' &&
                            _ticket['metadata'] != null &&
                            _ticket['metadata'] is Map &&
                            (_ticket['metadata'] as Map).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildOrderMetadata(isDark),
                        ],
                        if (_ticket['description'] != null &&
                            (_ticket['description'] as String).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Brand.darkCardElevated
                                  : Brand.royalBlueSurface,
                              borderRadius: BorderRadius.circular(Brand.r(12)),
                              border: Border.all(
                                color: isDark
                                    ? Brand.darkBorder
                                    : Brand.royalBlue.withAlpha(20),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Description',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Brand.darkTextTertiary
                                        : Brand.subtleLight,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _ticket['description'] ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Brand.darkTextSecondary
                                        : Brand.subtleLight,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 12,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Colors.black38,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Created ${_ticket['created_at'] != null ? TimeUtils.getTimeAgo(DateTime.parse(_ticket['created_at'])) : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Colors.black38,
                              ),
                            ),
                            if (_ticket['closed_at'] != null) ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 12,
                                color: isDark
                                    ? Brand.darkTextTertiary
                                    : Colors.black38,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Closed ${TimeUtils.getTimeAgo(DateTime.parse(_ticket['closed_at']))}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Brand.darkTextTertiary
                                      : Colors.black38,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Divider(
            height: 1,
            color: isDark ? Brand.darkBorder : Brand.borderLight,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderMetadata(bool isDark) {
    final meta = _ticket['metadata'] as Map<String, dynamic>? ?? {};
    final items = <Widget>[];

    void addRow(IconData icon, String label, String value) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 12, color: Brand.lightGreenBright),
            const SizedBox(width: 6),
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ));
    }

    if (meta['machine_name'] != null) {
      addRow(Icons.precision_manufacturing_rounded, 'Machine',
          meta['machine_name'].toString());
    }
    if (meta['quantity'] != null) {
      addRow(Icons.inventory_2_rounded, 'Qty', meta['quantity'].toString());
    }
    if (meta['company_name'] != null) {
      addRow(
          Icons.business_rounded, 'Company', meta['company_name'].toString());
    }
    if (meta['contact_number'] != null) {
      addRow(Icons.phone_rounded, 'Contact', meta['contact_number'].toString());
    }
    if (meta['delivery_address'] != null) {
      addRow(Icons.location_on_rounded, 'Delivery',
          meta['delivery_address'].toString());
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.lightGreenBright.withAlpha(((isDark ? 0.06 : 0.04) * 255).toInt()),
        borderRadius: BorderRadius.circular(Brand.r(12)),
        border: Border.all(color: Brand.lightGreenBright.withAlpha(38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shopping_bag_rounded,
                size: 13,
                color: isDark ? Brand.lightGreenBright : Brand.lightGreenDark,
              ),
              const SizedBox(width: 6),
              Text(
                'ORDER DETAILS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Brand.lightGreenBright : Brand.lightGreenDark,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items,
        ],
      ),
    );
  }

  Widget _buildEscalationBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AdminColors.internal.withAlpha(((isDark ? 0.08 : 0.05) * 255).toInt()),
        border: Border(
          bottom: BorderSide(color: AdminColors.internal.withAlpha(51)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AdminColors.internal.withAlpha(38),
              borderRadius: BorderRadius.circular(Brand.r(8)),
            ),
            child: Icon(Icons.warning_rounded,
                size: 15, color: AdminColors.internal[700]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Escalated to Admin',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.internal[700],
                  ),
                ),
                if (_ticket['escalation_reason'] != null)
                  Text(
                    _ticket['escalation_reason'],
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _removeEscalation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: AdminColors.internal.withAlpha(77)),
                borderRadius: BorderRadius.circular(Brand.r(8)),
              ),
              child: Text(
                'Remove',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.internal[700],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  CHAT HEADER
  // ═══════════════════════════════════════════════════════════

  Widget _buildChatHeader(bool isDark) {
    final totalMessages = _messages.length;
    final internalCount =
        _messages.where((m) => m['is_internal'] == true).length;
    final rating = _ticket['customer_rating'] as int?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Brand.darkCard.withAlpha(128)
            : Brand.cardLight.withAlpha(179),
        border: Border(
          bottom:
              BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.forum_rounded,
              size: 15,
              color: isDark ? Brand.darkTextTertiary : Brand.subtleLight),
          const SizedBox(width: 6),
          Text(
            '$totalMessages messages',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
            ),
          ),
          if (internalCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AdminColors.internal.withAlpha(((isDark ? 0.12 : 0.08) * 255).toInt()),
                borderRadius: BorderRadius.circular(Brand.r(10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 10, color: AdminColors.internal[700]),
                  const SizedBox(width: 3),
                  Text(
                    '$internalCount internal',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.internal[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          if (rating != null) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                return Icon(
                  i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 14,
                  color: i < rating
                      ? AdminColors.warning
                      : (isDark ? Brand.darkBorderLight : Brand.borderLight),
                );
              }),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showSnackBar('Could not open $url', isError: true);
      }
    } catch (e) {
      _showSnackBar('Failed to open: $e', isError: true);
    }
  }

  Widget _contactAction(
    IconData icon,
    String text,
    Color color,
    bool isDark, {
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: color.withAlpha(((isDark ? 0.1 : 0.06) * 255).toInt()),
            borderRadius: BorderRadius.circular(Brand.r(10)),
            border: Border.all(
              color: color.withAlpha(((isDark ? 0.25 : 0.2) * 255).toInt()),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withAlpha(((0.15) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(7)),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.open_in_new_rounded,
                  size: 12, color: color.withAlpha(153)),
            ],
          ),
        ),
      );

  Widget _infoChip(IconData icon, String text, bool isDark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? Brand.darkCardElevated : Brand.royalBlueSurface,
          borderRadius: BorderRadius.circular(Brand.r(10)),
          border: Border.all(
            color:
                isDark ? Brand.darkBorder : Brand.royalBlue.withAlpha(20),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 13,
                color: isDark ? Brand.darkTextSecondary : Brand.royalBlueLight),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Brand.darkTextSecondary : Brand.royalBlueDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  // ═══════════════════════════════════════════════════════════
  //  CHAT AREA + MESSAGE BUBBLE
  // ═══════════════════════════════════════════════════════════

  Widget _buildChatArea(bool isDark) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isDark ? Brand.darkCard : Brand.royalBlueSurface,
                borderRadius: BorderRadius.circular(Brand.r(20)),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 30,
                color: isDark ? Brand.darkTextSecondary : Brand.royalBlue,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start the conversation below',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Brand.darkTextTertiary : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }

    final offset = _isLoadingMore ? 1 : 0;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length + offset,
      itemBuilder: (_, i) {
        if (_isLoadingMore && i == 0) {
          return _buildLoadingMoreIndicator(isDark);
        }
        return _messageBubble(_messages[i - offset], isDark);
      },
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg, bool isDark) {
    final senderType = msg['sender_type'] as String? ?? 'customer';
    final isSystem = senderType == 'system';
    final isInternal = msg['is_internal'] == true;
    final isAdmin = senderType == 'admin';
    final sender = msg['sender'] as Map<String, dynamic>?;
    final text = msg['message'] as String? ?? '';
    final isMe = msg['sender_id'] == _currentUserId;

    // Time formatting
    final createdAt = msg['created_at'] as String?;
    final time = createdAt != null
        ? TimeUtils.formatMessageTime(DateTime.parse(createdAt).toLocal())
        : '';

    // System messages — centered
    if (isSystem || (isInternal && senderType == 'system')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Brand.darkCard : Brand.royalBlueSurface,
              borderRadius: BorderRadius.circular(Brand.r(20)),
              border: isDark
              ? Border.all(color: Brand.darkBorder)
              : null,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextSecondary : Brand.subtleLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    // Sender info
    String senderName;
    Color senderLabelColor;
    IconData senderIcon;

    if (isMe) {
      senderName = 'You';
      senderLabelColor = _engAccent;
      senderIcon = Icons.engineering_rounded;
    } else if (isAdmin) {
      senderName = sender?['full_name'] ?? 'Admin';
      senderLabelColor = isDark ? Brand.royalBlueGlow : Brand.royalBlue;
      senderIcon = Icons.support_agent_rounded;
    } else {
      senderName = sender?['full_name'] ?? _customer['full_name'] ?? 'Customer';
      senderLabelColor = isDark ? Brand.darkTextSecondary : Brand.subtleLight;
      senderIcon = Icons.person_rounded;
    }

    // Bubble color
    Color bubbleColor;
    if (isInternal) {
      bubbleColor = isDark
          ? AdminColors.internal.withAlpha(26)
          : AdminColors.internal.withAlpha(15);
    } else if (isMe) {
      bubbleColor = Colors.transparent;
    } else if (isAdmin) {
      bubbleColor =
          isDark ? Brand.royalBlue.withAlpha(38) : Brand.royalBlueSurface;
    } else {
      bubbleColor = Brand.surface(isDark);
    }

    // Avatar for non-self messages
    final senderPhoto = sender?['profile_photo'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAdmin
                    ? Brand.royalBlue.withAlpha(51)
                    : Brand.royalBlue.withAlpha(38),
              ),
              child: ClipOval(
                child: senderPhoto != null && senderPhoto.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: senderPhoto,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Center(
                          child: Text(
                            StringUtils.getInitials(senderName),
                            style: TextStyle(
                              color: isAdmin
                                  ? Brand.royalBlue
                                  : Brand.royalBlueLight,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Text(
                            StringUtils.getInitials(senderName),
                            style: TextStyle(
                              color: isAdmin
                                  ? Brand.royalBlue
                                  : Brand.royalBlueLight,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          StringUtils.getInitials(senderName),
                          style: TextStyle(
                            color: isAdmin
                                ? Brand.royalBlue
                                : Brand.royalBlueLight,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Sender label
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(senderIcon, size: 11, color: senderLabelColor),
                        const SizedBox(width: 4),
                        Text(
                          senderName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: senderLabelColor,
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Brand.royalBlue.withAlpha(26),
                              borderRadius: BorderRadius.circular(Brand.r(4)),
                            ),
                            child: Text(
                              'ADMIN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Brand.royalBlueGlow
                                    : Brand.royalBlue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                // Internal note label for own messages
                if (isInternal && isMe)
                  Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 10, color: AdminColors.internal[700]),
                        const SizedBox(width: 3),
                        Text(
                          'Internal Note',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.internal[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                // Bubble
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: (isMe && !isInternal)
                        ? LinearGradient(
                            colors: isDark
                                ? [_engAccent, _engAccentDark]
                                : [
                                    Brand.royalBlue,
                                    Brand.royalBlueLight,
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: (isMe && !isInternal) ? null : bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(Brand.r(18)),
                      topRight: Radius.circular(Brand.r(18)),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: isInternal
                        ? Border.all(
                            color: AdminColors.internal.withAlpha(89),
                            width: 1,
                          )
                        : (isMe
                            ? null
                            : Border.all(
                                color: isDark
                                    ? Brand.darkBorder
                                    : Brand.borderLight,
                              )),
                    boxShadow: isDark ? null : [
                      BoxShadow(
                        color: isMe ? Brand.royalBlue.withAlpha(51) : Brand.royalBlue.withAlpha(8),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isInternal && !isMe)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded,
                                  size: 10, color: AdminColors.internal[700]),
                              const SizedBox(width: 4),
                              Text(
                                'INTERNAL NOTE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AdminColors.internal[700],
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Attachments: image / voice / document / location
                      Builder(builder: (_) {
                        final msgType =
                            msg['message_type'] as String? ?? 'text';
                        final atts = msg['attachments'] is List
                            ? List<String>.from(
                                (msg['attachments'] as List)
                                    .map((e) => e.toString()))
                            : const <String>[];
                        final meta = msg['metadata'] is Map
                            ? Map<String, dynamic>.from(
                                msg['metadata'] as Map)
                            : null;
                        final pad = EdgeInsets.only(
                            bottom: text.isNotEmpty ? 8 : 0);
                        if (msgType == 'image' && atts.isNotEmpty) {
                          return Padding(
                            padding: pad,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Brand.r(12)),
                              child: CachedNetworkImage(
                                imageUrl: atts.first,
                                width: 200,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        }
                        final w = buildChatAttachment(
                          messageType: msgType,
                          attachments: atts,
                          metadata: meta,
                          isMe: isMe && !isInternal,
                          accent: _engAccent,
                        );
                        return w == null
                            ? const SizedBox.shrink()
                            : Padding(padding: pad, child: w);
                      }),
                      if (text.isNotEmpty)
                        Text(
                          text,
                          style: TextStyle(
                            color: (isMe && !isInternal)
                                ? Colors.white
                                : isInternal
                                    ? (isDark
                                        ? Brand.darkTextPrimary
                                        : Colors.black87)
                                    : (isDark
                                        ? Brand.darkTextPrimary
                                        : Brand.royalBlueDark),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Brand.darkTextTertiary : Colors.black38,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      if (isInternal)
                        Icon(
                          Icons.lock_rounded,
                          size: 11,
                          color: AdminColors.internal[700]!.withAlpha(128),
                        )
                      else
                        Builder(builder: (_) {
                          final isRead = msg['is_read'] == true;
                          final delivered = msg['delivered_at'] != null;
                          if (isRead) {
                            return const Icon(
                              Icons.done_all_rounded,
                              size: 13,
                              color: Color(0xFF58A6FF), // blue = read
                            );
                          }
                          if (delivered) {
                            return Icon(
                              Icons.done_all_rounded,
                              size: 13,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Colors.black26, // grey double = delivered
                            );
                          }
                          return Icon(
                            Icons.done_rounded,
                            size: 13,
                            color: isDark
                                ? Brand.darkTextTertiary
                                : Colors.black26, // grey single = sent
                          );
                        }),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  INPUT BAR
  // ═══════════════════════════════════════════════════════════

  Widget _buildInputBar(bool isDark) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomSafe + 12),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        border: Border(
          top: BorderSide(
            color: _internalMode
                ? AdminColors.internal.withAlpha(128)
                : (isDark ? Brand.darkBorder : Brand.borderLight),
            width: _internalMode ? 2 : 1,
          ),
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_internalMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, size: 13, color: AdminColors.internal[700]),
                  const SizedBox(width: 6),
                  Text(
                    'Internal note — not visible to customer',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.internal[700],
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _internalMode = !_internalMode),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _internalMode
                          ? AdminColors.internal.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt())
                          : (isDark
                              ? Brand.darkCardElevated
                              : Brand.scaffoldLight),
                      borderRadius: BorderRadius.circular(Brand.r(12)),
                      border: Border.all(
                        color: _internalMode
                            ? AdminColors.internal.withAlpha(102)
                            : (isDark
                                ? Brand.darkBorder
                                : Brand.royalBlue.withAlpha(26)),
                      ),
                    ),
                    child: Icon(
                      _internalMode
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 18,
                      color: _internalMode
                          ? AdminColors.internal[700]
                          : (isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              ChatAttachMenuButton(
                ticketId: widget.ticketId,
                accent: _engAccent,
                onSend: ({
                  required String messageType,
                  required List<String> attachments,
                  Map<String, dynamic>? metadata,
                }) =>
                    _sendAttachment(
                  messageType: messageType,
                  attachments: attachments,
                  metadata: metadata,
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Brand.darkCardElevated
                        : Brand.royalBlueSurface,
                    borderRadius: BorderRadius.circular(Brand.r(24)),
                    border: Border.all(
                      color: _internalMode
                          ? AdminColors.internal.withAlpha(77)
                          : (isDark
                              ? Brand.darkBorder
                              : Brand.royalBlue.withAlpha(26)),
                    ),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      color:
                          isDark ? Brand.darkTextPrimary : Brand.royalBlueDark,
                      fontSize: 14,
                    ),
                    cursorColor:
                        _internalMode ? AdminColors.internal[700] : _engAccent,
                    decoration: InputDecoration(
                      hintText: _internalMode
                          ? 'Write internal note...'
                          : 'Reply to customer...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? Brand.darkTextSecondary
                            : Brand.subtleLight,
                      ),
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Brand.r(24)),
                        borderSide: BorderSide(
                          color: isDark ? Brand.darkIconActive : _engAccent,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ChatVoiceRecorderButton(
                ticketId: widget.ticketId,
                accent: _engAccent,
                onSend: ({
                  required String messageType,
                  required List<String> attachments,
                  Map<String, dynamic>? metadata,
                }) =>
                    _sendAttachment(
                  messageType: messageType,
                  attachments: attachments,
                  metadata: metadata,
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isSending ? null : _sendMessage,
                  borderRadius: BorderRadius.circular(Brand.r(16)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: _internalMode
                          ? LinearGradient(
                              colors: [
                                AdminColors.internal[800]!,
                                AdminColors.internal[600]!,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : const LinearGradient(
                              colors: [
                                _engAccent,
                                _engAccentDark,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      borderRadius: BorderRadius.circular(Brand.r(16)),
                      boxShadow: [
                        BoxShadow(
                          color: (_internalMode ? AdminColors.internal : _engAccent)
                              .withAlpha(102),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _isSending
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
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  CLOSED BANNER
  // ═══════════════════════════════════════════════════════════

  Widget _buildClosedBanner(bool isDark) {
    final status = _ticket['status'] ?? 'closed';
    final statusColor = _statusColor(status);
    final rating = _ticket['customer_rating'] as int?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.surface(isDark),
        border: Border(
          top: BorderSide(color: isDark ? Brand.darkBorder : Brand.borderLight),
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Brand.royalBlue.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(((isDark ? 0.08 : 0.05) * 255).toInt()),
            borderRadius: BorderRadius.circular(Brand.r(16)),
            border: Border.all(color: statusColor.withAlpha(38)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(((isDark ? 0.15 : 0.1) * 255).toInt()),
                  borderRadius: BorderRadius.circular(Brand.r(12)),
                ),
                child: Icon(
                  status == 'resolved'
                      ? Icons.check_circle_rounded
                      : Icons.archive_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ticket ${status == 'resolved' ? 'Resolved' : 'Closed'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          ...List.generate(
                            5,
                            (i) => Icon(
                              i < rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 14,
                              color: i < rating
                                  ? AdminColors.warning
                                  : (isDark
                                      ? Brand.darkBorderLight
                                      : Brand.borderLight),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Customer rating',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Brand.darkTextTertiary
                                  : Brand.subtleLight,
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Text(
                        'No customer rating yet',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Brand.darkTextTertiary
                              : Brand.subtleLight,
                        ),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _updateStatus('in_progress'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        _engAccent,
                        _engAccentDark,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(Brand.r(10)),
                    boxShadow: [
                      BoxShadow(
                        color: _engAccent.withAlpha(89),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Reopen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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
  //  SKELETON LOADER
  // ═══════════════════════════════════════════════════════════

  Widget _buildSkeleton(bool isDark) {
    Widget sk(double w, double h, double r) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: isDark
                ? Brand.darkBorderLight.withAlpha(77)
                : Brand.royalBlue.withAlpha(13),
            borderRadius: BorderRadius.circular(r),
          ),
        );

    Widget bubbleRow(bool isRight) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment:
                isRight ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isRight) ...[
                sk(32, 32, 16),
                const SizedBox(width: 8),
              ],
              Column(
                crossAxisAlignment:
                    isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isRight) sk(60, 10, 4),
                  if (!isRight) const SizedBox(height: 4),
                  sk(isRight ? 180 : 200, 50, 16),
                  const SizedBox(height: 3),
                  sk(40, 8, 4),
                ],
              ),
              if (isRight) const SizedBox(width: 8),
            ],
          ),
        );

    return Column(
      children: [
        // Info panel skeleton
        Container(
          padding: const EdgeInsets.all(16),
          color: Brand.surface(isDark),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sk(double.infinity, 16, 6),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: sk(double.infinity, 32, 10)),
                  const SizedBox(width: 8),
                  Expanded(child: sk(double.infinity, 32, 10)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: sk(double.infinity, 32, 10)),
                  const SizedBox(width: 8),
                  Expanded(child: sk(double.infinity, 32, 10)),
                ],
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: isDark ? Brand.darkBorder : Brand.borderLight,
        ),
        // Chat header skeleton
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              sk(14, 14, 4),
              const SizedBox(width: 6),
              sk(90, 12, 4),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: isDark ? Brand.darkBorder : Brand.borderLight,
        ),
        // Message skeletons
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                bubbleRow(false),
                bubbleRow(false),
                bubbleRow(true),
                bubbleRow(false),
                bubbleRow(true),
              ],
            ),
          ),
        ),
        // Input skeleton
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Brand.surface(isDark),
            border: Border(
              top: BorderSide(
                color: isDark ? Brand.darkBorder : Brand.borderLight,
              ),
            ),
          ),
          child: Row(
            children: [
              sk(40, 40, 12),
              const SizedBox(width: 8),
              Expanded(child: sk(double.infinity, 44, 22)),
              const SizedBox(width: 10),
              sk(48, 48, 16),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  LOADING MORE INDICATOR
  // ═══════════════════════════════════════════════════════════

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
                color: isDark ? _engAccent : Brand.royalBlue,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading older messages…',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Brand.darkTextTertiary : Brand.subtleLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
